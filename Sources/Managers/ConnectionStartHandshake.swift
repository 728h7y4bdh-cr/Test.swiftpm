import Foundation

/// Bluetooth通信開始処理（PS設計書 6.2、要件定義書 5章）。Central役。
///
/// 通信開始要求（送信種別0x29・通信種別0x01）を1回送信し、30秒以内に応答（Notify）を
/// 検出できるかどうかだけに責任を持つ。データ送信処理（`DataSender`）や
/// データ受信チェック（`DataReceiver`）の知識は一切持たない（要件定義書の「処理」単位＝
/// このクラス単位で完結させ、他の処理との癒着を防ぐ）。
/// CoreBluetooth自体の型には依存せず、`BluetoothCentralSession`が提供する
/// クロージャベースの窓口（Data の送受信）のみを介して動作する。
final class ConnectionStartHandshake {
    private let session: BluetoothCentralSession
    private var timeoutTimer: Timer?
    private var completion: ((Bool) -> Void)?

    init(session: BluetoothCentralSession) {
        self.session = session
    }

    /// 処理を開始する。結果（true=正常終了／false=異常終了）はcompletionで通知する。
    func start(myID: String, targetID: String, completion: @escaping (Bool) -> Void) {
        self.completion = completion

        session.onFailure = { [weak self] in self?.finish(success: false) }
        session.onReady = { [weak self] in
            self?.sendRequest(myID: myID, targetID: targetID)
        }
        session.onResponseReceived = { [weak self] data in
            self?.handleResponse(data, myID: myID, targetID: targetID)
        }
        session.start()
    }

    /// PS設計書 6.2「送信データ」を1回送信し、30秒間の応答待ちタイマーを開始する。
    private func sendRequest(myID: String, targetID: String) {
        // 送信サイズ確認（PS設計書 0.1 No.5／5.3）：18byte以上であることを確認してから1回で送信する
        guard session.maximumWriteLength >= Payload.totalLength else {
            finish(success: false)
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

        // PS設計書 3.2 No.3：通信開始のデータ送信時にconnectingへ遷移
        StatusManager.shared.apply(.connectionStartRequestSent)

        // PS設計書 6.2「送信後30秒間、以下のデータを待受する」
        timeoutTimer?.invalidate()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
            self?.finish(success: false)
        }

        session.write(PayloadCodec.encode(payload)) { [weak self] success in
            if !success {
                self?.finish(success: false)
            }
            // 成功時はここでは何もせず、相手からのNotify応答（handleResponse）を待つ
        }
    }

    /// PS設計書 6.2「30秒以内に待ち受けしたデータを検出した場合」の判定処理
    private func handleResponse(_ data: Data, myID: String, targetID: String) {
        guard let payload = PayloadCodec.decode(data) else { return }
        // PS設計書 6.2「待受内容」：送信種別0x92固定・通信種別0x01、
        // 送信元ID＝送信時の送信先ID、送信先ID＝送信時の送信元ID、入力データ＝0x20埋め
        guard payload.payloadType == .response, payload.communicationType == .connection,
              payload.sourceID == targetID, payload.destinationID == myID else {
            return // 不一致のデータは無視し、タイムアウトまで待ち続ける
        }
        finish(success: true)
    }

    private func finish(success: Bool) {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        session.onReady = nil
        session.onResponseReceived = nil
        session.onFailure = nil

        let completion = self.completion
        self.completion = nil

        if success {
            // PS設計書 3.2 No.4：通信開始処理の正常終了通知時にwaitingToSendへ遷移
            StatusManager.shared.apply(.connectionStartSucceeded)
        }
        completion?(success)
    }
}
