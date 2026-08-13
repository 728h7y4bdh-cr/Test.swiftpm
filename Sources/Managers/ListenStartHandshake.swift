import Foundation

/// Bluetooth待受開始処理（PS設計書 6.3、要件定義書 6章）。Peripheral役。
///
/// 30秒間、通信開始要求（送信種別0x29・通信種別0x01）を待受し、検出できれば応答を1回送信する。
/// データ受信処理（`DataReceiver`）とは完全に別のクラスであり、待受成功後の「受信データの中身を
/// 判定する」ロジックは一切持たない（ハンドシェイクと受信処理の混在を避ける）。
/// CoreBluetooth自体の型には依存せず、`BluetoothPeripheralSession`が提供する
/// クロージャベースの窓口（Data の送受信）のみを介して動作する。
final class ListenStartHandshake {
    private let session: BluetoothPeripheralSession
    private var timeoutTimer: Timer?
    private var completion: ((Bool) -> Void)?
    private var myID = ""
    private var targetID = ""

    init(session: BluetoothPeripheralSession) {
        self.session = session
    }

    /// 処理を開始する。結果（true=正常終了／false=異常終了）はcompletionで通知する。
    func start(myID: String, targetID: String, completion: @escaping (Bool) -> Void) {
        self.myID = myID
        self.targetID = targetID
        self.completion = completion

        session.onFailure = { [weak self] in self?.finish(success: false) }
        session.onReady = { [weak self] in
            self?.beginWaiting()
        }
        session.onWriteReceived = { [weak self] data in
            self?.handleWrite(data)
        }
        session.start()
    }

    /// アドバタイズ開始（＝待受開始）に伴い、PS設計書 6.3「30秒間のデータ待受」タイマーを開始する。
    private func beginWaiting() {
        // PS設計書 3.2 No.6：30秒間のデータ待受開始時にlisteningへ遷移
        StatusManager.shared.apply(.listenStarted)

        timeoutTimer?.invalidate()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
            self?.finish(success: false)
        }
    }

    /// PS設計書 6.3「30秒以内に検出した場合」の判定処理と応答送信
    private func handleWrite(_ data: Data) {
        guard let payload = PayloadCodec.decode(data) else { return }
        // PS設計書 6.3「待受内容」：送信種別0x29固定・通信種別0x01、
        // 送信元ID＝接続先ID、送信先ID＝自端末ID、入力データ＝0x20埋め
        guard payload.payloadType == .request, payload.communicationType == .connection,
              payload.sourceID == targetID, payload.destinationID == myID else {
            return // 一致しない場合は無視し、タイムアウトまで待ち続ける
        }

        timeoutTimer?.invalidate()
        timeoutTimer = nil

        // PS設計書 6.3「検出時送信データ」：送信種別0x92固定・通信種別0x01、
        // 送信元ID＝自端末ID、送信先ID＝接続先ID、入力データ＝0x20埋め、を1回送信する
        let responsePayload = Payload(
            payloadType: .response,
            communicationType: .connection,
            sourceID: myID,
            destinationID: targetID,
            inputData: PayloadCodec.blankInputData
        )
        session.notify(PayloadCodec.encode(responsePayload)) { [weak self] success in
            self?.finish(success: success)
        }
    }

    private func finish(success: Bool) {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        session.onReady = nil
        session.onWriteReceived = nil
        session.onFailure = nil

        let completion = self.completion
        self.completion = nil

        if success {
            // PS設計書 3.2 No.7：待受処理の正常終了通知時にwaitingToReceiveへ遷移
            StatusManager.shared.apply(.listenSucceeded)
        }
        completion?(success)
    }
}
