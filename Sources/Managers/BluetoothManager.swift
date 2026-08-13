import Foundation

/// データ受信処理（PS設計書 6.6）の結果をUI層（ReceiveViewController）へ伝えるためのデリゲート
protocol BluetoothManagerReceiveDelegate: AnyObject {
    /// チェックOKのデータを検出した（受信検出あり）
    func bluetoothManager(_ manager: BluetoothManager, didDetect payload: Payload)
    /// チェックNGだった（受信検出なし）
    func bluetoothManagerDidFailToDetect(_ manager: BluetoothManager)
    /// 受信中に相手端末との接続が予期せず切断された（PS設計書 7章）
    func bluetoothManagerDidDisconnectUnexpectedly(_ manager: BluetoothManager)
}

/// Bluetooth通信全体の調停役（Coordinator）。
///
/// 要件定義書で定義される各「処理」は、実際には独立した機能単位であるという考え方に基づき、
/// 通信開始処理（`ConnectionStartHandshake`）・待受開始処理（`ListenStartHandshake`）・
/// データ送信処理（`DataSender`）・データ受信処理（`DataReceiver`）を、それぞれ専用クラスとして
/// 分離してある。本クラスはプロトコルの中身（バイトフォーマットやハンドシェイクの照合条件など）を
/// 一切持たず、「今どちらの役割（Central/Peripheral、PS設計書5.1）で、どの処理を動かすか」に応じて
/// それらを生成・接続・破棄するだけの調停役に徹する。
///
/// 画面（ViewController）に対しては、このクラスがこれまでと同じ公開APIを提供する。
/// 内部構成（クラス分割）を変更しても呼び出し側（ViewController）には影響しない＝
/// 役割・機能を分割したことで変更の影響範囲が閉じ込められていることの実例でもある。
final class BluetoothManager {
    static let shared = BluetoothManager()

    weak var receiveDelegate: BluetoothManagerReceiveDelegate?

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

    // MARK: - Public: Bluetooth通信開始処理（PS設計書 6.2, Central役）

    func startConnecting(myID: String, targetID: String, completion: @escaping (Bool) -> Void) {
        // PS設計書 5.4／6.2：「現在、接続中の端末がある場合は切断後」に処理を開始する
        disconnect {
            self.role = .central
            let session = BluetoothCentralSession()
            self.centralSession = session

            ConnectionStartHandshake(session: session).start(myID: myID, targetID: targetID) { [weak self] success in
                guard let self else { return }
                if success {
                    completion(true)
                } else {
                    // PS設計書 6.2「30秒以内に検出しなかった場合はBluetooth通信を切断して、異常終了を通知する」
                    self.disconnect { completion(false) }
                }
            }
        }
    }

    // MARK: - Public: Bluetooth待受開始処理（PS設計書 6.3, Peripheral役）

    func startListening(myID: String, targetID: String, completion: @escaping (Bool) -> Void) {
        // PS設計書 6.3：「現在、接続中の端末がある場合は切断後」に30秒間の待受を開始する
        disconnect {
            self.role = .peripheral
            let session = BluetoothPeripheralSession()
            self.peripheralSession = session
            // 待受成功後にデータ受信処理へ引き継ぐため、ここで生成しておく（開始はstartReceiving()で行う）
            self.dataReceiver = DataReceiver(session: session, myID: myID, targetID: targetID)

            ListenStartHandshake(session: session).start(myID: myID, targetID: targetID) { [weak self] success in
                guard let self else { return }
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
        centralSession?.teardown()
        centralSession = nil
        peripheralSession?.teardown()
        peripheralSession = nil
        dataReceiver = nil
        role = .none
        // PS設計書 3.2 No.2：切断処理完了後にアイドルへ遷移
        StatusManager.shared.apply(.disconnectCompleted)
        completion?()
    }

    // MARK: - Public: データ送信処理（PS設計書 6.5, Central役）

    func sendData(myID: String, targetID: String, text: String, completion: @escaping (Bool) -> Void) {
        guard let session = centralSession else {
            completion(false)
            return
        }
        DataSender(session: session).send(myID: myID, targetID: targetID, text: text) { [weak self] success in
            guard let self else { return }
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

    // MARK: - Private

    /// 待受開始処理の成功直後、Peripheralセッションの受信窓口をハンドシェイク側から
    /// データ受信処理（DataReceiver）側へ配線する。あわせて、受信中の予期しない切断
    /// （PS設計書 7章）をここで検知できるようにする。
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
            // PS設計書 7章：データ受信処理が実行中（isReceiving）の場合のみ、想定外切断として画面へ通知する
            let wasReceiving = self.dataReceiver?.isReceiving == true
            self.disconnect {
                if wasReceiving {
                    self.receiveDelegate?.bluetoothManagerDidDisconnectUnexpectedly(self)
                }
            }
        }
    }
}
