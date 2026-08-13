import CoreBluetooth
import Foundation

/// データ受信処理（PS設計書 6.6）の結果をUI層へ伝えるためのデリゲート
protocol BluetoothManagerReceiveDelegate: AnyObject {
    /// チェックOKのデータを検出した（受信検出あり）
    func bluetoothManager(_ manager: BluetoothManager, didDetect payload: Payload)
    /// チェックNGだった（受信検出なし）
    func bluetoothManagerDidFailToDetect(_ manager: BluetoothManager)
    /// 受信中に相手端末との接続が予期せず切断された
    func bluetoothManagerDidDisconnectUnexpectedly(_ manager: BluetoothManager)
}

/// Core Bluetoothを用いた通信制御全般（PS設計書 5章・6章）
///
/// 「接続開始」操作時はCentral役、「待受開始」操作時はPeripheral役として動作する
/// （PS設計書 0.1 補足事項 No.3）。
final class BluetoothManager: NSObject {
    static let shared = BluetoothManager()

    weak var receiveDelegate: BluetoothManagerReceiveDelegate?

    private override init() {
        super.init()
    }

    // MARK: - ロール

    private enum Role {
        case none
        case central
        case peripheral
    }

    private var role: Role = .none

    // MARK: - Central側（Bluetooth通信開始処理／データ送信処理）

    private var centralManager: CBCentralManager?
    private var remotePeripheral: CBPeripheral?
    private var requestCharacteristic: CBCharacteristic?
    private var responseCharacteristic: CBCharacteristic?
    private var centralScanRequested = false

    private enum CentralOperation {
        case none
        case connectingHandshake(myID: String, targetID: String, completion: (Bool) -> Void)
        case sendingData(completion: (Bool) -> Void)
    }
    private var centralOperation: CentralOperation = .none

    // MARK: - Peripheral側（Bluetooth待受開始処理／データ受信処理）

    private var peripheralManager: CBPeripheralManager?
    private var mutableRequestCharacteristic: CBMutableCharacteristic?
    private var mutableResponseCharacteristic: CBMutableCharacteristic?
    private var peripheralAdvertiseRequested = false
    private var pendingResponsePayload: Payload?

    private enum PeripheralOperation {
        case none
        case listeningHandshake(myID: String, targetID: String, completion: (Bool) -> Void)
    }
    private var peripheralOperation: PeripheralOperation = .none

    private var isReceiving = false
    private var receiveMyID = ""
    private var receiveTargetID = ""

    // MARK: - タイムアウト（30秒）

    private var handshakeTimer: Timer?

    // MARK: - Public: Bluetooth通信開始処理（PS設計書 6.2, Central役）

    func startConnecting(myID: String, targetID: String, completion: @escaping (Bool) -> Void) {
        disconnect {
            self.role = .central
            StatusManager.shared.update(.connecting)
            self.centralOperation = .connectingHandshake(myID: myID, targetID: targetID, completion: completion)

            if self.centralManager == nil {
                self.centralManager = CBCentralManager(delegate: self, queue: nil)
            }
            self.centralScanRequested = true
            self.beginScanIfReady()
        }
    }

    // MARK: - Public: Bluetooth待受開始処理（PS設計書 6.3, Peripheral役）

    func startListening(myID: String, targetID: String, completion: @escaping (Bool) -> Void) {
        disconnect {
            self.role = .peripheral
            StatusManager.shared.update(.listening)
            self.receiveMyID = myID
            self.receiveTargetID = targetID
            self.peripheralOperation = .listeningHandshake(myID: myID, targetID: targetID, completion: completion)

            if self.peripheralManager == nil {
                self.peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
            }
            self.peripheralAdvertiseRequested = true
            self.beginAdvertisingIfReady()
        }
    }

    // MARK: - Public: Bluetooth通信切断処理（PS設計書 6.4）

    func disconnect(completion: (() -> Void)? = nil) {
        handshakeTimer?.invalidate()
        handshakeTimer = nil
        centralOperation = .none
        peripheralOperation = .none
        isReceiving = false
        centralScanRequested = false
        peripheralAdvertiseRequested = false
        pendingResponsePayload = nil

        if let remotePeripheral {
            centralManager?.cancelPeripheralConnection(remotePeripheral)
        }
        centralManager?.stopScan()
        remotePeripheral = nil
        requestCharacteristic = nil
        responseCharacteristic = nil

        if let peripheralManager, peripheralManager.isAdvertising {
            peripheralManager.stopAdvertising()
        }
        peripheralManager?.removeAllServices()
        mutableRequestCharacteristic = nil
        mutableResponseCharacteristic = nil

        role = .none
        StatusManager.shared.resetToIdle()
        completion?()
    }

    // MARK: - Public: データ送信処理（PS設計書 6.5, Central役）

    func sendData(myID: String, targetID: String, text: String, completion: @escaping (Bool) -> Void) {
        guard let remotePeripheral, let requestCharacteristic else {
            completion(false)
            return
        }

        StatusManager.shared.update(.sending)
        centralOperation = .sendingData(completion: completion)

        let payload = Payload(
            payloadType: .request,
            communicationType: .data,
            sourceID: myID,
            destinationID: targetID,
            inputData: PayloadCodec.paddedInputData(from: text)
        )
        remotePeripheral.writeValue(PayloadCodec.encode(payload), for: requestCharacteristic, type: .withResponse)
    }

    // MARK: - Public: データ受信処理（PS設計書 6.6, Peripheral役）

    /// データ受信処理を開始する（待受成功直後、または「受信再開」ボタン押下時）
    func startReceiving() {
        StatusManager.shared.update(.waitingToReceive)
        isReceiving = true
    }

    /// 「受信終了要求」を通知し、完了後に「受信終了完了」としてcompletionを呼び出す
    func stopReceiving(completion: @escaping () -> Void) {
        isReceiving = false
        StatusManager.shared.update(.receiveStopping)
        DispatchQueue.main.async {
            completion()
        }
    }

    // MARK: - Private: 共通

    private func matches(_ payload: Payload, type: PayloadType, communication: CommunicationType, sourceID: String, destinationID: String) -> Bool {
        payload.payloadType == type
            && payload.communicationType == communication
            && payload.sourceID == sourceID
            && payload.destinationID == destinationID
    }

    private func startHandshakeTimeoutTimer(onTimeout: @escaping () -> Void) {
        handshakeTimer?.invalidate()
        handshakeTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
            self?.handshakeTimer = nil
            onTimeout()
        }
    }

    /// 相手端末との接続が予期せず失われた場合の共通処理（PS設計書 7章）
    private func handleUnexpectedDisconnection() {
        switch centralOperation {
        case .connectingHandshake, .sendingData:
            failCentralOperation()
            return
        case .none:
            break
        }

        if case .listeningHandshake = peripheralOperation {
            failPeripheralHandshake()
            return
        }

        if isReceiving {
            disconnect()
            receiveDelegate?.bluetoothManagerDidDisconnectUnexpectedly(self)
        }
    }

    // MARK: - Private: Central 補助

    private func beginScanIfReady() {
        guard centralScanRequested, let centralManager, centralManager.state == .poweredOn else { return }
        centralScanRequested = false
        centralManager.scanForPeripherals(withServices: [BluetoothGATT.serviceUUID], options: nil)
    }

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

    private func beginAdvertisingIfReady() {
        guard peripheralAdvertiseRequested, let peripheralManager, peripheralManager.state == .poweredOn else { return }
        peripheralAdvertiseRequested = false

        let requestChar = CBMutableCharacteristic(
            type: BluetoothGATT.requestCharacteristicUUID,
            properties: [.write],
            value: nil,
            permissions: [.writeable]
        )
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

    private func failPeripheralHandshake() {
        let operation = peripheralOperation
        peripheralOperation = .none
        disconnect {
            if case .listeningHandshake(_, _, let completion) = operation {
                completion(false)
            }
        }
    }

    private func completeListeningHandshakeSuccess() {
        guard case .listeningHandshake(_, _, let completion) = peripheralOperation else { return }
        peripheralOperation = .none
        StatusManager.shared.update(.waitingToReceive)
        completion(true)
    }

    private func handleReceivedRequestPayload(_ payload: Payload) {
        if case .listeningHandshake(let myID, let targetID, _) = peripheralOperation {
            guard matches(payload, type: .request, communication: .connection, sourceID: targetID, destinationID: myID) else {
                return
            }
            handshakeTimer?.invalidate()
            handshakeTimer = nil

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

        guard isReceiving else { return }
        guard payload.communicationType == .data, payload.payloadType == .request,
              payload.sourceID == receiveTargetID, payload.destinationID == receiveMyID,
              payload.inputDataText == "YAMA" || payload.inputDataText == "KAWA" else {
            receiveDelegate?.bluetoothManagerDidFailToDetect(self)
            return
        }
        receiveDelegate?.bluetoothManager(self, didDetect: payload)
    }

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

// MARK: - CBCentralManagerDelegate（Central役）

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            beginScanIfReady()
        case .poweredOff, .unauthorized, .unsupported:
            if centralScanRequested || centralOperation.isActive {
                failCentralOperation()
            }
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        central.stopScan()
        remotePeripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([BluetoothGATT.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        failCentralOperation()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard role == .central else { return }
        handleUnexpectedDisconnection()
    }
}

// MARK: - CBPeripheralDelegate（Central役：相手端末に対する処理）

extension BluetoothManager: CBPeripheralDelegate {
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

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, characteristic.uuid == BluetoothGATT.responseCharacteristicUUID else {
            failCentralOperation()
            return
        }
        guard case .connectingHandshake(let myID, let targetID, _) = centralOperation,
              let requestCharacteristic else {
            return
        }

        // 送信サイズ確認（PS設計書 5.3）：18byte以上であることを確認してから1回で送信する
        guard peripheral.maximumWriteValueLength(for: .withResponse) >= Payload.totalLength else {
            failCentralOperation()
            return
        }

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
                disconnect {
                    completion(false)
                }
            } else {
                StatusManager.shared.update(.waitingToSend)
                completion(true)
            }
        case .none:
            break
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == BluetoothGATT.responseCharacteristicUUID, error == nil, let data = characteristic.value else { return }
        guard case .connectingHandshake(let myID, let targetID, let completion) = centralOperation else { return }
        guard let payload = PayloadCodec.decode(data) else { return }
        guard matches(payload, type: .response, communication: .connection, sourceID: targetID, destinationID: myID) else {
            return // 不一致のデータは無視し、タイムアウトまで待ち続ける
        }

        handshakeTimer?.invalidate()
        handshakeTimer = nil
        centralOperation = .none
        StatusManager.shared.update(.waitingToSend)
        completion(true)
    }
}

// MARK: - CBPeripheralManagerDelegate（Peripheral役）

extension BluetoothManager: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            beginAdvertisingIfReady()
        case .poweredOff, .unauthorized, .unsupported:
            if peripheralAdvertiseRequested || peripheralOperation.isActive || isReceiving {
                handleUnexpectedDisconnection()
            }
        default:
            break
        }
    }

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

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        guard role == .peripheral else { return }
        handleUnexpectedDisconnection()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            peripheral.respond(to: request, withResult: .success)
            guard let data = request.value, let payload = PayloadCodec.decode(data) else { continue }
            handleReceivedRequestPayload(payload)
        }
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        guard let pendingResponsePayload else { return }
        self.pendingResponsePayload = nil
        sendResponseOrQueue(pendingResponsePayload)
    }
}

// MARK: - 便宜プロパティ

private extension BluetoothManager.CentralOperation {
    var isActive: Bool {
        if case .none = self { return false }
        return true
    }
}

private extension BluetoothManager.PeripheralOperation {
    var isActive: Bool {
        if case .none = self { return false }
        return true
    }
}
