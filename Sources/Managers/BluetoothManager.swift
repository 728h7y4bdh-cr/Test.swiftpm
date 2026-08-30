import Foundation

/// データ受信処理（PS設計書 6.6）の結果をUI層（ReceiveViewController）へ伝えるためのデリゲート
protocol BluetoothManagerReceiveDelegate: AnyObject {
    /// チェックOKのデータを検出した（受信検出あり）
    func bluetoothManager(_ manager: BluetoothManager, didDetect payload: Payload)
    /// チェックNGだった（受信検出なし）
    func bluetoothManagerDidFailToDetect(_ manager: BluetoothManager)
}

/// Bluetooth接続が予期せず切断されたことをUI層へ伝えるためのデリゲート（PS設計書 7章）。
/// Central役（データ送信画面）・Peripheral役（データ受信画面）のどちらでも起こりうるため、
/// 受信処理専用の`BluetoothManagerReceiveDelegate`とは分離し、両画面が共通で実装する
/// （SS設計書 5.6／6.6「予期しない切断時の仕様」）。
protocol BluetoothManagerConnectionDelegate: AnyObject {
    func bluetoothManagerDidDisconnectUnexpectedly(_ manager: BluetoothManager)
}

/// Bluetooth通信全体の調停役（Coordinator）。
///
/// 要件定義書で定義される各「処理」は、実際には独立した機能単位であるという考え方に基づき、
/// 通信開始処理（`ConnectionStartHandshake`）・待受開始処理（`ListenStartHandshake`）・
/// データ送信処理（`DataSender`）・データ受信処理（`DataReceiver`）・通信切断処理（`Disconnector`）を、
/// それぞれ専用の機能単位として分離してある。本クラスはアプリケーション独自の通信内容（バイトフォーマットやハンドシェイクの照合条件など）を
/// 一切持たず、「今どちらの役割（Central/Peripheral、PS設計書5.1）で、どの処理を動かすか」に応じて
/// それらを生成・接続・破棄するだけの調停役に徹する。
///
/// 画面（ViewController）に対しては、このクラスがこれまでと同じ公開APIを提供する。
/// 内部構成（クラス分割）を変更しても呼び出し側（ViewController）には影響しない＝
/// 役割・機能を分割したことで変更の影響範囲が閉じ込められていることの実例でもある。
final class BluetoothManager {
    static let shared = BluetoothManager()

    weak var receiveDelegate: BluetoothManagerReceiveDelegate?
    /// SS設計書 5.6／6.6「予期しない切断時の仕様」の通知先。データ送信画面・データ受信画面の両方が設定する。
    weak var connectionDelegate: BluetoothManagerConnectionDelegate?

    private init() {}

    private enum Role {
        case none
        case central
        case peripheral
    }
    private var role: Role = .none

    private var centralSession: BluetoothCentralSession?
    private var peripheralSession: BluetoothPeripheralSession?
    /// 待受開始成功後に受信処理を任せる先。生成は`startListening`時点で行うが、
    /// 実際に受信を開始するのは公開APIの`startReceiving()`が呼ばれた時点。
    private var dataReceiver: DataReceiver?
    /// 処理完了（成功／失敗いずれか）まで保持する。保持しないと、非同期のCore Bluetooth
    /// コールバック（`onReady`等）が発火する前にインスタンスが解放され、`[weak self]`経由の
    /// 後続処理（要求送信・タイムアウト時の異常終了通知）が一切実行されなくなる。
    private var connectionStartHandshake: ConnectionStartHandshake?
    private var listenStartHandshake: ListenStartHandshake?
    /// `connectionStartHandshake`等と同じ理由（R-01）で、処理完了まで保持する。
    /// `DataSender`が応答待ち（`session.onResponseReceived`・タイムアウトタイマー）を持つように
    /// なったため、保持しないと同じ問題が再発する。
    private var dataSender: DataSender?

    /// Central役の切断要求(`cancelPeripheralConnection`)を出したが、実際の切断完了が
    /// まだCore Bluetoothから通知されていない間、`true`になる（R-04対応）。
    /// この間に新しい通信を開始しようとすると、直前の切断が完全に片付く前に新しいセッションを
    /// 作ることになり、実機のBluetooth通信が不安定になる可能性があるため、ボタン操作側
    /// （`ConnectionViewController`）はこのフラグを見て操作を止める。
    ///
    /// 対象はCentral役の切断のみ。Peripheral役の切断（`stopAdvertising`／`removeAllServices`）には
    /// Core Bluetooth側に完了通知の仕組みが無く、確実に待つ手段が無いため対象外としている
    /// （「待受成功→戻る→待受開始」「待受成功→戻る→接続開始」のケースは、この保護の対象外。
    /// 前者は自分から能動的に接続しにいかないため実害は小さいと考えられるが、後者は理屈上のリスクが
    /// 残っており、実機のE2E試験（`docs/開発環境書.md` 4.7）で問題が無いか確認すること）。
    private(set) var isDisconnecting = false

    // MARK: - Public: Bluetooth通信開始処理（PS設計書 6.2, Central役）

    func startConnecting(myID: String, targetID: String, completion: @escaping (Bool) -> Void) {
        #if DEBUG
        // デバッグ機能：プレビュー確認用バイパス（有効/無効は`DebugSettings`に一元管理されている。PS設計書 付録A.1）
        if DebugSettings.isPreviewBypassEnabled {
            runPreviewBypass(
                role: .central,
                startEvent: .connectionStartRequestSent,
                successEvent: .connectionStartSucceeded,
                completion: completion
            )
            return
        }
        #endif

        // PS設計書 5.4／6.2：「現在、接続中の端末がある場合は切断後」に処理を開始する
        disconnect {
            self.role = .central
            let session = BluetoothCentralSession()
            self.centralSession = session

            let handshake = ConnectionStartHandshake(session: session)
            self.connectionStartHandshake = handshake
            handshake.start(myID: myID, targetID: targetID) { [weak self] success in
                guard let self else { return }
                self.connectionStartHandshake = nil
                if success {
                    // 通信開始処理の成功直後から、データ送信画面滞在中の予期しない切断を検知できるようにする
                    // （SS設計書 5.6「予期しない切断時の仕様」）
                    self.wireCentralFailureCallback()
                    completion(true)
                } else {
                    // PS設計書 6.2「60秒以内に検出しなかった場合はBluetooth通信を切断して、異常終了を通知する」
                    self.disconnect { completion(false) }
                }
            }
        }
    }

    // MARK: - Public: Bluetooth待受開始処理（PS設計書 6.3, Peripheral役）

    func startListening(myID: String, targetID: String, completion: @escaping (Bool) -> Void) {
        #if DEBUG
        // デバッグ機能：プレビュー確認用バイパス（PS設計書 付録A.1）
        if DebugSettings.isPreviewBypassEnabled {
            // dataReceiverを生成しないため、以降startReceiving()/stopReceiving()は何もしない
            // （データ受信処理は行わない。データ受信画面は「受信中」表示のまま＝画面遷移確認のみ）
            runPreviewBypass(
                role: .peripheral,
                startEvent: .listenStarted,
                successEvent: .listenSucceeded,
                completion: completion
            )
            return
        }
        #endif

        // PS設計書 6.3：「現在、接続中の端末がある場合は切断後」に60秒間の待受を開始する
        disconnect {
            self.role = .peripheral
            let session = BluetoothPeripheralSession()
            self.peripheralSession = session
            // 待受成功後にデータ受信処理へ引き継ぐため、ここで生成しておく（開始はstartReceiving()で行う）
            self.dataReceiver = DataReceiver(session: session, myID: myID, targetID: targetID)

            let handshake = ListenStartHandshake(session: session)
            self.listenStartHandshake = handshake
            handshake.start(myID: myID, targetID: targetID) { [weak self] success in
                guard let self else { return }
                self.listenStartHandshake = nil
                if success {
                    // ハンドシェイクからデータ受信処理へ、Writeの受信窓口を引き継ぐ
                    // （この時点からはDataReceiverのみがWriteを解釈し、ハンドシェイクのロジックとは混在しない）
                    self.wireDataReceiverCallbacks()
                    completion(true)
                } else {
                    // PS設計書 6.3「送信失敗の場合は…切断して、異常終了を通知する」
                    self.disconnect { completion(false) }
                }
            }
        }
    }

    // MARK: - Public: Bluetooth通信切断処理（PS設計書 6.4）

    func disconnect(completion: (() -> Void)? = nil) {
        let central = centralSession
        let peripheral = peripheralSession
        centralSession = nil
        peripheralSession = nil
        dataReceiver = nil
        // セッションのteardownによりハンドシェイク側のコールバックは呼ばれなくなるため、
        // 処理途中で切断された場合に備えてここでも明示的に解放する
        connectionStartHandshake = nil
        listenStartHandshake = nil
        dataSender = nil
        role = .none

        // Central役の接続中セッションがあった場合のみ、実際の切断完了を待つ対象とする
        if central != nil {
            isDisconnecting = true
        }
        Disconnector.disconnect(centralSession: central, peripheralSession: peripheral) { [weak self] in
            self?.isDisconnecting = false
        }

        // UI側の完了通知は切断完了を待たず、これまで通り即座に呼ぶ（画面が一瞬固まって見えるのを避けるため）
        completion?()
    }

    // MARK: - Public: データ送信処理（PS設計書 6.5, Central役）

    func sendData(myID: String, targetID: String, text: String, completion: @escaping (Bool) -> Void) {
        #if DEBUG
        // デバッグ機能：プレビュー確認用バイパス（PS設計書 付録A.1）
        if DebugSettings.isPreviewBypassEnabled {
            StatusManager.shared.apply(.dataSendStarted)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                StatusManager.shared.apply(.dataSendCompleted)
                completion(true)
            }
            return
        }
        #endif

        guard let session = centralSession else {
            completion(false)
            return
        }
        let sender = DataSender(session: session)
        self.dataSender = sender
        sender.send(myID: myID, targetID: targetID, text: text) { [weak self] success in
            guard let self else { return }
            self.dataSender = nil
            if success {
                completion(true)
            } else {
                // PS設計書 6.5「送信失敗の場合は…切断して、異常終了を通知する」
                self.disconnect { completion(false) }
            }
        }
    }

    // MARK: - Public: データ受信処理（PS設計書 6.6, Peripheral役）

    /// データ受信処理を開始する（待受成功直後、または「受信再開」ボタン押下時の2箇所から呼ばれる）
    func startReceiving() {
        dataReceiver?.start()
    }

    /// 「受信終了要求」を通知する。完了後に「受信終了完了」としてcompletionを呼び出す
    func stopReceiving(completion: @escaping () -> Void) {
        guard let dataReceiver else {
            completion()
            return
        }
        dataReceiver.stop(completion: completion)
    }

    #if DEBUG
    // MARK: - Private（プレビュー確認用バイパス）

    /// 通信開始処理／待受開始処理を、実際のCore Bluetooth通信なしで擬似的に成功させる。
    /// 「処理中」ダイアログが一瞬で消えて操作感が確認できなくなることを避けるため、
    /// 2秒の擬似的な待ち時間を挟んでから、対応する状態遷移イベントを適用してcompletionを呼ぶ。
    private func runPreviewBypass(
        role: Role,
        startEvent: AppStatusTransitionEvent,
        successEvent: AppStatusTransitionEvent,
        completion: @escaping (Bool) -> Void
    ) {
        disconnect {
            self.role = role
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                StatusManager.shared.apply(startEvent)
                StatusManager.shared.apply(successEvent)
                completion(true)
            }
        }
    }
    #endif

    // MARK: - Private

    /// 通信開始処理の成功直後、Centralセッションの予期しない切断を検知できるようにする。
    /// データ送信処理（DataSender）の知識は持たず、単に切断を検知したらcompletionへ通知するだけ
    /// （SS設計書 5.6「予期しない切断時の仕様」）。
    private func wireCentralFailureCallback() {
        centralSession?.onFailure = { [weak self] in
            guard let self else { return }
            self.disconnect {
                self.connectionDelegate?.bluetoothManagerDidDisconnectUnexpectedly(self)
            }
        }
    }

    /// 待受開始処理の成功直後、Peripheralセッションの受信窓口をハンドシェイク側から
    /// データ受信処理（DataReceiver）側へ配線する。あわせて、待受成功後にデータ受信画面へ
    /// 遷移している間ずっと、予期しない切断を検知できるようにする（SS設計書 6.6）。
    private func wireDataReceiverCallbacks() {
        dataReceiver?.onDetect = { [weak self] payload in
            guard let self else { return }
            self.receiveDelegate?.bluetoothManager(self, didDetect: payload)
        }
        dataReceiver?.onNotDetect = { [weak self] in
            guard let self else { return }
            self.receiveDelegate?.bluetoothManagerDidFailToDetect(self)
        }
        peripheralSession?.onFailure = { [weak self] in
            guard let self else { return }
            self.disconnect {
                self.connectionDelegate?.bluetoothManagerDidDisconnectUnexpectedly(self)
            }
        }
    }
}
