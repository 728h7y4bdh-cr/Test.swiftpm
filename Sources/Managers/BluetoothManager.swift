import CoreBluetooth
import Foundation

/// データ受信処理（PS設計書 6.6「データ受信処理」）の結果をUI層（ReceiveViewController）へ伝えるためのデリゲート。
protocol BluetoothManagerReceiveDelegate: AnyObject {
    /// チェックOKのデータを検出した（PS設計書 6.6「チェックOK時：コール元に『受信検出あり』を通知」）
    func bluetoothManager(_ manager: BluetoothManager, didDetect payload: Payload)
    /// チェックNGだった（PS設計書 6.6「チェックNG時：コール元に『受信検出なし』を通知」）
    func bluetoothManagerDidFailToDetect(_ manager: BluetoothManager)
    /// 受信中に相手端末との接続が予期せず切断された（PS設計書 7章「エラーハンドリング方針」対応）
    func bluetoothManagerDidDisconnectUnexpectedly(_ manager: BluetoothManager)
}

/// Core Bluetoothを用いた通信制御全般（PS設計書 5章「Core Bluetooth設計」・6章「処理仕様」）。
///
/// 「接続開始」操作時はCentral役、「待受開始」操作時はPeripheral役として動作する
/// （PS設計書 0.1 補足事項 No.3「Central/Peripheral役割」）。
/// GATTのService／Characteristic定義は`BluetoothGATT`（PS設計書 5.2）を参照。
final class BluetoothManager: NSObject {
    static let shared = BluetoothManager()

    weak var receiveDelegate: BluetoothManagerReceiveDelegate?

    private override init() {
        super.init()
    }

    // MARK: - ロール（PS設計書 5.1「Central/Peripheral役割」）

    /// 現在このインスタンスがどちらの役割で動作しているか。
    /// 「接続開始」＝Central、「待受開始」＝Peripheral（PS設計書 5.1の対応表）。
    private enum Role {
        case none
        case central
        case peripheral
    }

    private var role: Role = .none

    // MARK: - Central側（PS設計書 6.2 Bluetooth通信開始処理／6.5 データ送信処理）

    /// スキャン・接続を行うCore Bluetoothのマネージャ本体
    private var centralManager: CBCentralManager?
    /// 接続先の相手端末（Peripheral役の端末）
    private var remotePeripheral: CBPeripheral?
    /// Request/Dataキャラクタリスティック（Write用。PS設計書 5.2）
    private var requestCharacteristic: CBCharacteristic?
    /// Responseキャラクタリスティック（Notify用。PS設計書 5.2）
    private var responseCharacteristic: CBCharacteristic?
    /// poweredOnになり次第スキャンを開始すべきかどうかのフラグ
    private var centralScanRequested = false

    /// Central役として現在進行中の処理。
    /// 進行中の処理に応じて、CBCentralManagerDelegate/CBPeripheralDelegateの各コールバックの
    /// 振る舞いを振り分ける（例：Writeの成功が「通信開始要求の送信成功」なのか
    /// 「データ送信の成功」なのかは、このcentralOperationの値で判断する）。
    private enum CentralOperation {
        case none
        /// PS設計書 6.2「Bluetooth通信開始処理」実行中（30秒応答待ちを含む）
        case connectingHandshake(myID: String, targetID: String, completion: (Bool) -> Void)
        /// PS設計書 6.5「データ送信処理」実行中
        case sendingData(completion: (Bool) -> Void)
    }
    private var centralOperation: CentralOperation = .none

    // MARK: - Peripheral側（PS設計書 6.3 Bluetooth待受開始処理／6.6 データ受信処理）

    /// アドバタイズ・GATTサーバーを提供するCore Bluetoothのマネージャ本体
    private var peripheralManager: CBPeripheralManager?
    /// Request/Dataキャラクタリスティック（自分がPeripheral役の時に公開する側の実体）
    private var mutableRequestCharacteristic: CBMutableCharacteristic?
    /// Responseキャラクタリスティック（自分がPeripheral役の時に公開する側の実体）
    private var mutableResponseCharacteristic: CBMutableCharacteristic?
    /// poweredOnになり次第アドバタイズを開始すべきかどうかのフラグ
    private var peripheralAdvertiseRequested = false
    /// updateValueが送信キュー詰まりで失敗した際、送信待ちとして保持する応答ペイロード
    /// （peripheralManagerIsReady(toUpdateSubscribers:)で再送する）
    private var pendingResponsePayload: Payload?

    /// Peripheral役として現在進行中の処理（ハンドシェイク＝通信開始要求の待受・応答のみを対象とする）。
    private enum PeripheralOperation {
        case none
        /// PS設計書 6.3「Bluetooth待受開始処理」実行中（30秒間の通信開始要求待受を含む）
        case listeningHandshake(myID: String, targetID: String, completion: (Bool) -> Void)
    }
    private var peripheralOperation: PeripheralOperation = .none

    /// データ受信処理（PS設計書 6.6）が実行中かどうか。
    /// ハンドシェイク（peripheralOperation）とは別に管理し、待受成功後〜「受信終了要求」検出まで
    /// trueとなる（「受信再開」でも再度trueに戻る）。
    private var isReceiving = false
    /// データ受信処理でのチェックに使用する自端末ID（PS設計書 6.6のチェック内容：送信先ID＝自端末ID）
    private var receiveMyID = ""
    /// データ受信処理でのチェックに使用する接続先ID（PS設計書 6.6のチェック内容：送信元ID＝接続先ID）
    private var receiveTargetID = ""

    /// Central役の処理（接続開始ハンドシェイク／データ送信）が進行中かどうか
    private var isCentralOperationActive: Bool {
        if case .none = centralOperation { return false }
        return true
    }

    /// Peripheral役のハンドシェイク（待受開始処理）が進行中かどうか
    private var isPeripheralOperationActive: Bool {
        if case .none = peripheralOperation { return false }
        return true
    }

    // MARK: - タイムアウト（PS設計書 6.2・6.3：30秒間の待受タイマー）

    private var handshakeTimer: Timer?

    // MARK: - Public: Bluetooth通信開始処理（PS設計書 6.2, Central役）

    /// PS設計書 6.2「Bluetooth通信開始処理」を開始する。
    /// 呼び出し元（ConnectionViewControllerの「接続開始」ボタン処理）には、
    /// 30秒以内に相手からの応答を検出できればtrue（正常終了）、
    /// できなければfalse（異常終了、切断処理済み）をcompletionで通知する。
    func startConnecting(myID: String, targetID: String, completion: @escaping (Bool) -> Void) {
        // PS設計書 5.4／6.2：「現在、接続中の端末がある場合は切断後」に処理を開始する
        disconnect {
            self.role = .central
            StatusManager.shared.update(.connecting) // PS設計書 3.2 No.3：通信開始のデータ送信時にconnectingへ遷移
            self.centralOperation = .connectingHandshake(myID: myID, targetID: targetID, completion: completion)

            if self.centralManager == nil {
                // CBCentralManagerの生成が、必要に応じてOS標準のBluetooth使用許可ダイアログの契機にもなる
                self.centralManager = CBCentralManager(delegate: self, queue: nil)
            }
            self.centralScanRequested = true
            self.beginScanIfReady() // poweredOn済みなら直ちにスキャン開始、そうでなければdidUpdateState待ち
        }
    }

    // MARK: - Public: Bluetooth待受開始処理（PS設計書 6.3, Peripheral役）

    /// PS設計書 6.3「Bluetooth待受開始処理」を開始する。
    /// 呼び出し元（ConnectionViewControllerの「待受開始」ボタン処理）には、
    /// 30秒以内に通信開始要求を検出し応答送信できればtrue（正常終了）、
    /// できなければfalse（異常終了、切断処理済み）をcompletionで通知する。
    func startListening(myID: String, targetID: String, completion: @escaping (Bool) -> Void) {
        // PS設計書 6.3：「現在、接続中の端末がある場合は切断後」に30秒間の待受を開始する
        disconnect {
            self.role = .peripheral
            StatusManager.shared.update(.listening) // PS設計書 3.2 No.6：30秒間のデータ待受開始時にlisteningへ遷移
            self.receiveMyID = myID
            self.receiveTargetID = targetID
            self.peripheralOperation = .listeningHandshake(myID: myID, targetID: targetID, completion: completion)

            if self.peripheralManager == nil {
                self.peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
            }
            self.peripheralAdvertiseRequested = true
            self.beginAdvertisingIfReady() // poweredOn済みなら直ちにアドバタイズ開始、そうでなければdidUpdateState待ち
        }
    }

    // MARK: - Public: Bluetooth通信切断処理（PS設計書 6.4）

    /// PS設計書 6.4「Bluetooth通信切断処理」：Bluetooth通信を切断し、完了後にステータスを初期化（アイドル）する。
    /// Central/Peripheralどちらの役割で動作中でも安全に呼び出せる（該当しない側の処理は実質no-op）。
    func disconnect(completion: (() -> Void)? = nil) {
        handshakeTimer?.invalidate()
        handshakeTimer = nil
        centralOperation = .none
        peripheralOperation = .none
        isReceiving = false
        centralScanRequested = false
        peripheralAdvertiseRequested = false
        pendingResponsePayload = nil

        // Central役の後始末：接続中の相手端末があれば切断し、スキャンも停止する
        if let remotePeripheral {
            centralManager?.cancelPeripheralConnection(remotePeripheral)
        }
        centralManager?.stopScan()
        remotePeripheral = nil
        requestCharacteristic = nil
        responseCharacteristic = nil

        // Peripheral役の後始末：アドバタイズを停止し、公開していたGATTサービスを取り下げる
        if let peripheralManager, peripheralManager.isAdvertising {
            peripheralManager.stopAdvertising()
        }
        peripheralManager?.removeAllServices()
        mutableRequestCharacteristic = nil
        mutableResponseCharacteristic = nil

        role = .none
        StatusManager.shared.resetToIdle() // PS設計書 3.2 No.2：切断処理完了後にアイドルへ遷移
        completion?()
    }

    // MARK: - Public: データ送信処理（PS設計書 6.5, Central役）

    /// PS設計書 6.5「データ送信処理」：送信データ（"YAMA"/"KAWA"）を24byte改め18byteペイロードに
    /// 変換し、接続先へ1回送信する。結果はcompletionでコール元（SendViewController）へ通知する。
    func sendData(myID: String, targetID: String, text: String, completion: @escaping (Bool) -> Void) {
        guard let remotePeripheral, let requestCharacteristic else {
            completion(false)
            return
        }

        StatusManager.shared.update(.sending) // PS設計書 3.2 No.10：データ送信開始時にsendingへ遷移
        centralOperation = .sendingData(completion: completion)

        // PS設計書 6.5送信データ：送信種別0x29固定・通信種別0x02、
        // 入力データは選択されたテストデータをASCII変換し0x20埋め（PayloadCodec.paddedInputData）
        let payload = Payload(
            payloadType: .request,
            communicationType: .data,
            sourceID: myID,
            destinationID: targetID,
            inputData: PayloadCodec.paddedInputData(from: text)
        )
        remotePeripheral.writeValue(PayloadCodec.encode(payload), for: requestCharacteristic, type: .withResponse)
        // 結果はperipheral(_:didWriteValueFor:error:)（CBPeripheralDelegate）で受け取る
    }

    // MARK: - Public: データ受信処理（PS設計書 6.6, Peripheral役）

    /// データ受信処理を開始する（PS設計書 6.3成功直後、または「受信再開」ボタン押下時の2箇所から呼ばれる）。
    /// 実際の受信データの検査は、Writeを受信する`peripheralManager(_:didReceiveWrite:)`で行われる。
    func startReceiving() {
        // PS設計書 3.2 No.7/No.8：待受処理の正常終了通知時、または「再開」ボタンタップ時にwaitingToReceiveへ遷移
        StatusManager.shared.update(.waitingToReceive)
        isReceiving = true
    }

    /// PS設計書 6.6「受信終了要求」の通知を受け、データ受信処理を終了する。
    /// 完了後（ステータスをreceiveStoppingに遷移させた後）に「受信終了完了」としてcompletionを呼び出す。
    /// Bluetooth接続自体は切断しない点に注意（切断は呼び出し元が別途`disconnect`を呼ぶ設計。SS設計書 6.4参照）。
    func stopReceiving(completion: @escaping () -> Void) {
        isReceiving = false
        // PS設計書 3.2 No.9：「受信終了要求」検出→「受信終了完了」通知時にreceiveStoppingへ遷移
        StatusManager.shared.update(.receiveStopping)
        DispatchQueue.main.async {
            completion()
        }
    }

    // MARK: - Private: 共通

    /// ペイロードが期待する内容と一致するかを判定する（送信種別／通信種別／送信元ID／送信先IDの4項目）。
    /// PS設計書 6.2〜6.3のハンドシェイクにおけるデータチェックに使用する共通ヘルパー。
    private func matches(_ payload: Payload, type: PayloadType, communication: CommunicationType, sourceID: String, destinationID: String) -> Bool {
        payload.payloadType == type
            && payload.communicationType == communication
            && payload.sourceID == sourceID
            && payload.destinationID == destinationID
    }

    /// PS設計書 6.2・6.3で規定される「30秒間の待受」タイマーを開始する。
    private func startHandshakeTimeoutTimer(onTimeout: @escaping () -> Void) {
        handshakeTimer?.invalidate()
        handshakeTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
            self?.handshakeTimer = nil
            onTimeout()
        }
    }

    /// 相手端末との接続が予期せず失われた場合の共通処理（PS設計書 7章「エラーハンドリング方針」：
    /// 「進行中の処理があれば異常終了としてコール元に通知」に対応）。
    /// 進行中の処理の種類によって、通知先・処理内容を振り分ける。
    private func handleUnexpectedDisconnection() {
        switch centralOperation {
        case .connectingHandshake, .sendingData:
            // Central役でハンドシェイク中／データ送信中に切断された場合は、それぞれの異常終了として扱う
            failCentralOperation()
            return
        case .none:
            break
        }

        if case .listeningHandshake = peripheralOperation {
            // Peripheral役でハンドシェイク中に切断された場合も異常終了として扱う
            failPeripheralHandshake()
            return
        }

        if isReceiving {
            // データ受信処理中（ハンドシェイク完了後）の切断は、受信画面へ想定外切断として通知する
            disconnect()
            receiveDelegate?.bluetoothManagerDidDisconnectUnexpectedly(self)
        }
    }

    // MARK: - Private: Central 補助

    /// CBCentralManagerがpoweredOnであり、かつスキャン要求済みであればスキャンを開始する
    /// （PS設計書 6.2：通信開始のデータ送信の前段として、まず相手端末を発見する必要がある）。
    private func beginScanIfReady() {
        guard centralScanRequested, let centralManager, centralManager.state == .poweredOn else { return }
        centralScanRequested = false
        // BluetoothGATT.serviceUUIDをアドバタイズしている端末（＝待受中の相手）のみをスキャン対象にする
        centralManager.scanForPeripherals(withServices: [BluetoothGATT.serviceUUID], options: nil)
    }

    /// Central役の処理（接続開始ハンドシェイク／データ送信）を異常終了として終了する。
    /// PS設計書 6.2／6.5共通：「Bluetooth通信を切断して、処理のコール元に異常終了を通知する」。
    private func failCentralOperation() {
        let operation = centralOperation
        centralOperation = .none
        disconnect {
            switch operation {
            case .connectingHandshake(_, _, let completion):
                completion(false)
            case .sendingData(let completion):
                completion(false)
            case .none:
                break
            }
        }
    }

    // MARK: - Private: Peripheral 補助

    /// CBPeripheralManagerがpoweredOnであり、かつアドバタイズ要求済みであれば、
    /// GATTサービス（Request/Data・Responseキャラクタリスティック）を構築してPeripheralに追加する。
    /// アドバタイズ自体はサービス追加完了後の`peripheralManager(_:didAdd:error:)`で開始する。
    /// （PS設計書 5.2「GATTプロファイル定義」・6.3「Bluetooth待受開始処理」）
    private func beginAdvertisingIfReady() {
        guard peripheralAdvertiseRequested, let peripheralManager, peripheralManager.state == .poweredOn else { return }
        peripheralAdvertiseRequested = false

        // Request/Dataキャラクタリスティック：Central→Peripheralへの書き込み専用（PS設計書 5.2）
        let requestChar = CBMutableCharacteristic(
            type: BluetoothGATT.requestCharacteristicUUID,
            properties: [.write],
            value: nil,
            permissions: [.writeable]
        )
        // Responseキャラクタリスティック：Peripheral→Centralへの通知専用（PS設計書 5.2）
        let responseChar = CBMutableCharacteristic(
            type: BluetoothGATT.responseCharacteristicUUID,
            properties: [.notify],
            value: nil,
            permissions: [.readable]
        )
        mutableRequestCharacteristic = requestChar
        mutableResponseCharacteristic = responseChar

        let service = CBMutableService(type: BluetoothGATT.serviceUUID, primary: true)
        service.characteristics = [requestChar, responseChar]
        peripheralManager.add(service)
    }

    /// Peripheral役のハンドシェイク（待受開始処理）を異常終了として終了する。
    /// PS設計書 6.3：「Bluetooth通信を切断して、処理のコール元に異常終了を通知する」。
    private func failPeripheralHandshake() {
        let operation = peripheralOperation
        peripheralOperation = .none
        disconnect {
            if case .listeningHandshake(_, _, let completion) = operation {
                completion(false)
            }
        }
    }

    /// Peripheral役のハンドシェイク（待受開始処理）を正常終了として終了する。
    /// PS設計書 6.3：「送信が成功した場合は、処理のコール元に正常終了を通知する」。
    private func completeListeningHandshakeSuccess() {
        guard case .listeningHandshake(_, _, let completion) = peripheralOperation else { return }
        peripheralOperation = .none
        StatusManager.shared.update(.waitingToReceive) // PS設計書 3.2 No.7：待受処理の正常終了通知時にwaitingToReceiveへ遷移
        completion(true)
    }

    /// Peripheral役として受信したRequest（Central側からのWrite）を処理する。
    /// PS設計書 6.3のハンドシェイク中か、6.6のデータ受信処理中かによって処理を振り分ける。
    private func handleReceivedRequestPayload(_ payload: Payload) {
        if case .listeningHandshake(let myID, let targetID, _) = peripheralOperation {
            // PS設計書 6.3「待受内容」：送信種別0x29固定・通信種別0x01、
            // 送信元ID＝接続先ID、送信先ID＝自端末ID、入力データ＝0x20埋め、であることを確認する
            guard matches(payload, type: .request, communication: .connection, sourceID: targetID, destinationID: myID) else {
                return // 一致しない場合は無視し、タイムアウトまで待ち続ける
            }
            handshakeTimer?.invalidate()
            handshakeTimer = nil

            // PS設計書 6.3「検出時送信データ」：送信種別0x92固定・通信種別0x01、
            // 送信元ID＝自端末ID、送信先ID＝接続先ID、入力データ＝0x20埋め、を1回送信する
            let responsePayload = Payload(
                payloadType: .response,
                communicationType: .connection,
                sourceID: myID,
                destinationID: targetID,
                inputData: PayloadCodec.blankInputData
            )
            sendResponseOrQueue(responsePayload)
            return
        }

        // ここに到達するのはハンドシェイク完了後（＝PS設計書 6.6「データ受信処理」中）のWrite。
        guard isReceiving else { return } // 受信終了要求後（受信停止中）に届いたWriteは無視する

        // PS設計書 9章／6.6「データチェック内容」：送信種別0x29・通信種別0x02、
        // 送信元ID＝接続先ID、送信先ID＝自端末ID、入力データ＝ASCII"YAMA"または"KAWA"（0x20埋め）
        guard payload.communicationType == .data, payload.payloadType == .request,
              payload.sourceID == receiveTargetID, payload.destinationID == receiveMyID,
              payload.inputDataText == "YAMA" || payload.inputDataText == "KAWA" else {
            // チェックNG：PS設計書「受信検出なし」をコール元へ通知
            receiveDelegate?.bluetoothManagerDidFailToDetect(self)
            return
        }
        // チェックOK：PS設計書「受信検出あり」をコール元へ通知（受信データを含む）
        receiveDelegate?.bluetoothManager(self, didDetect: payload)
    }

    /// 応答ペイロードをNotifyで送信する。送信キューが詰まっている場合は`pendingResponsePayload`に
    /// 保持しておき、`peripheralManagerIsReady(toUpdateSubscribers:)`で再送する
    /// （PS設計書 6.3「送信失敗の場合は…異常終了を通知する」に対する再試行の実装上の補足）。
    private func sendResponseOrQueue(_ payload: Payload) {
        guard let peripheralManager, let mutableResponseCharacteristic else { return }
        let data = PayloadCodec.encode(payload)
        if peripheralManager.updateValue(data, for: mutableResponseCharacteristic, onSubscribedCentrals: nil) {
            completeListeningHandshakeSuccess()
        } else {
            // 送信キューが空くとperipheralManagerIsReady(toUpdateSubscribers:)で再送する
            pendingResponsePayload = payload
        }
    }
}

// MARK: - CBCentralManagerDelegate（Central役：PS設計書 6.2 通信開始処理／6.5 データ送信処理）

extension BluetoothManager: CBCentralManagerDelegate {
    /// Bluetoothのオン/オフ・権限状態が変化した際に呼ばれる。
    /// poweredOnになったタイミングでスキャン開始要求を消化し、
    /// 逆にオフ／権限なしに変化した場合は進行中の処理を異常終了させる（PS設計書 7章）。
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            beginScanIfReady()
        case .poweredOff, .unauthorized, .unsupported:
            if centralScanRequested || isCentralOperationActive {
                failCentralOperation()
            }
        default:
            break
        }
    }

    /// スキャン中にBluetoothGATT.serviceUUIDをアドバタイズしている端末（＝待受中の相手）を発見した際に呼ばれる。
    /// PS設計書 6.2の「相手端末を発見する」処理に対応。発見後は即座に接続を試みる。
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        central.stopScan()
        remotePeripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    /// 相手端末への接続が確立した際に呼ばれる。続けてGATTサービスを検索する。
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([BluetoothGATT.serviceUUID])
    }

    /// 相手端末への接続に失敗した際に呼ばれる。PS設計書 6.2／6.5の異常終了として扱う。
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        failCentralOperation()
    }

    /// 接続していた相手端末との接続が切れた際に呼ばれる（自分からの切断・相手からの切断の両方を含む）。
    /// PS設計書 7章「予期しない切断」に対応：進行中の処理があれば異常終了として通知する。
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard role == .central else { return }
        handleUnexpectedDisconnection()
    }
}

// MARK: - CBPeripheralDelegate（Central役：相手端末(Peripheral)に対する処理）

extension BluetoothManager: CBPeripheralDelegate {
    /// サービス検索が完了した際に呼ばれる。BluetoothGATT.serviceUUIDのサービスが見つかれば、
    /// 続けてRequest/Data・Responseの2キャラクタリスティックを検索する。
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == BluetoothGATT.serviceUUID }) else {
            failCentralOperation()
            return
        }
        peripheral.discoverCharacteristics(
            [BluetoothGATT.requestCharacteristicUUID, BluetoothGATT.responseCharacteristicUUID],
            for: service
        )
    }

    /// キャラクタリスティック検索が完了した際に呼ばれる。両方を保持したうえで、
    /// Responseキャラクタリスティック（Notify）の購読を開始する
    /// （相手からの応答をWrite送信前に受け取れるようにしておくため。PS設計書 5.4関連の実装上の順序）。
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let characteristics = service.characteristics else {
            failCentralOperation()
            return
        }
        for characteristic in characteristics {
            if characteristic.uuid == BluetoothGATT.requestCharacteristicUUID {
                requestCharacteristic = characteristic
            } else if characteristic.uuid == BluetoothGATT.responseCharacteristicUUID {
                responseCharacteristic = characteristic
            }
        }
        guard let responseCharacteristic else {
            failCentralOperation()
            return
        }
        peripheral.setNotifyValue(true, for: responseCharacteristic)
    }

    /// Notify購読の状態が確定した際に呼ばれる。購読が有効になったら、
    /// PS設計書 6.2「送信後30秒間、以下のデータを待受する」のタイマーを開始したうえで、
    /// 通信開始要求（送信種別0x29・通信種別0x01）を1回送信する。
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, characteristic.uuid == BluetoothGATT.responseCharacteristicUUID else {
            failCentralOperation()
            return
        }
        guard case .connectingHandshake(let myID, let targetID, _) = centralOperation,
              let requestCharacteristic else {
            return
        }

        // PS設計書 0.1 No.5／5.3「送信サイズ確認方針」：18byte以上であることを確認してから1回で送信する
        guard peripheral.maximumWriteValueLength(for: .withResponse) >= Payload.totalLength else {
            failCentralOperation()
            return
        }

        // PS設計書 6.2「送信データ」：送信種別0x29固定・通信種別0x01、
        // 送信元ID＝自端末ID、送信先ID＝接続先ID、入力データ＝0x20埋め
        let payload = Payload(
            payloadType: .request,
            communicationType: .connection,
            sourceID: myID,
            destinationID: targetID,
            inputData: PayloadCodec.blankInputData
        )

        startHandshakeTimeoutTimer { [weak self] in
            self?.failCentralOperation()
        }
        peripheral.writeValue(PayloadCodec.encode(payload), for: requestCharacteristic, type: .withResponse)
    }

    /// Writeの結果（成功／失敗）が返ってきた際に呼ばれる。
    /// 現在進行中の処理（centralOperation）によって、意味が異なる点に注意：
    ///   - 通信開始ハンドシェイク中：これは要求送信の結果。成功してもここでは完了とせず、
    ///     相手からのNotify応答（didUpdateValueFor）を待つ（PS設計書 6.2）。
    ///   - データ送信中：これがそのまま送信結果そのもの（PS設計書 6.5「送信が成功した場合は…」）。
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        switch centralOperation {
        case .connectingHandshake:
            if error != nil {
                failCentralOperation()
            }
            // 成功時はここでは何もせず、Notifyでの応答受信(didUpdateValueFor)を待つ
        case .sendingData(let completion):
            handshakeTimer?.invalidate()
            handshakeTimer = nil
            centralOperation = .none
            if error != nil {
                // PS設計書 6.5「送信失敗の場合は…切断して、処理のコール元に異常終了を通知する」
                disconnect {
                    completion(false)
                }
            } else {
                // PS設計書 3.2 No.5：データ送信完了時にwaitingToSendへ遷移
                StatusManager.shared.update(.waitingToSend)
                completion(true)
            }
        case .none:
            break
        }
    }

    /// Responseキャラクタリスティックの値がNotifyで更新された際（＝相手からの応答を受信した際）に呼ばれる。
    /// PS設計書 6.2「30秒以内に待ち受けしたデータを検出した場合」の判定処理に対応する。
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == BluetoothGATT.responseCharacteristicUUID, error == nil, let data = characteristic.value else { return }
        guard case .connectingHandshake(let myID, let targetID, let completion) = centralOperation else { return }
        guard let payload = PayloadCodec.decode(data) else { return }

        // PS設計書 6.2「待受内容」：送信種別0x92固定・通信種別0x01、
        // 送信元ID＝送信時の送信先ID、送信先ID＝送信時の送信元ID、入力データ＝0x20埋め、であることを確認する
        guard matches(payload, type: .response, communication: .connection, sourceID: targetID, destinationID: myID) else {
            return // 不一致のデータは無視し、タイムアウトまで待ち続ける
        }

        handshakeTimer?.invalidate()
        handshakeTimer = nil
        centralOperation = .none
        // PS設計書 3.2 No.4：通信開始処理の正常終了通知時にwaitingToSendへ遷移
        StatusManager.shared.update(.waitingToSend)
        completion(true)
    }
}

// MARK: - CBPeripheralManagerDelegate（Peripheral役：PS設計書 6.3 待受開始処理／6.6 データ受信処理）

extension BluetoothManager: CBPeripheralManagerDelegate {
    /// Bluetoothのオン/オフ・権限状態が変化した際に呼ばれる。
    /// poweredOnになったタイミングでアドバタイズ開始要求を消化し、
    /// 逆にオフ／権限なしに変化した場合は進行中の処理を異常終了させる（PS設計書 7章）。
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            beginAdvertisingIfReady()
        case .poweredOff, .unauthorized, .unsupported:
            if peripheralAdvertiseRequested || isPeripheralOperationActive || isReceiving {
                handleUnexpectedDisconnection()
            }
        default:
            break
        }
    }

    /// GATTサービスの追加が完了した際に呼ばれる。追加成功後にアドバタイズを開始し、
    /// ハンドシェイク中であればPS設計書 6.3「30秒間のデータ待受」タイマーを開始する。
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard error == nil else {
            failPeripheralHandshake()
            return
        }
        peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [BluetoothGATT.serviceUUID]])

        if case .listeningHandshake = peripheralOperation {
            startHandshakeTimeoutTimer { [weak self] in
                self?.failPeripheralHandshake()
            }
        }
    }

    /// 接続していたCentral側が購読（Notify）を解除した際に呼ばれる（＝相手からの切断とみなす）。
    /// PS設計書 7章「予期しない切断」に対応：進行中の処理があれば異常終了として通知する。
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        guard role == .peripheral else { return }
        handleUnexpectedDisconnection()
    }

    /// Central側からのWrite要求を受信した際に呼ばれる（PS設計書 6.3のハンドシェイク要求、
    /// および6.6のデータ送受信の両方がここに届く）。
    /// 受信したことのACK（`.success`応答）は内容の正当性に関わらず常に返し、
    /// 内容のチェックは`handleReceivedRequestPayload`に委譲する。
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            peripheral.respond(to: request, withResult: .success)
            guard let data = request.value, let payload = PayloadCodec.decode(data) else { continue }
            handleReceivedRequestPayload(payload)
        }
    }

    /// Notify送信キューに空きができた際に呼ばれる。ハンドシェイク応答の送信が
    /// キュー詰まりで保留されていた場合（`pendingResponsePayload`）、ここで再送する。
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        guard let pendingResponsePayload else { return }
        self.pendingResponsePayload = nil
        sendResponseOrQueue(pendingResponsePayload)
    }
}
