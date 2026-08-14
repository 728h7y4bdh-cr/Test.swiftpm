import Foundation

/// Bluetooth通信開始処理（PS設計書 6.2、要件定義書 5章）。Central役。
///
/// 処理開始（`start`呼び出し＝「接続開始」ボタン押下）の瞬間から60秒以内に、
/// 相手の発見・接続・要求送信・応答（Notify）検出までを完了できるかどうかに責任を持つ。
/// データ送信処理（`DataSender`）やデータ受信チェック（`DataReceiver`）の知識は一切持たない
/// （要件定義書の「処理」単位＝このクラス単位で完結させ、他の処理との癒着を防ぐ）。
/// CoreBluetooth自体の型には依存せず、`BluetoothCentralSession`が提供する
/// クロージャベースの窓口（Data の送受信）のみを介して動作する。
final class ConnectionStartHandshake {
    /// PS設計書 6.2：処理開始から本処理全体（相手の発見〜応答検出）に許容する時間
    private static let timeoutInterval: TimeInterval = 60.0

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

        // PS設計書 6.2：処理開始（ボタン押下）の瞬間から60秒のタイムアウトを設定する。
        // 相手の発見（スキャン）にはCore Bluetooth側の時間制限がないため、
        // ここで発見〜応答検出までの全体を60秒に収める。
        timeoutTimer?.invalidate()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: Self.timeoutInterval, repeats: false) { [weak self] _ in
            self?.finish(success: false)
        }

        session.start()
    }

    /// PS設計書 6.2「送信データ」を1回送信する（応答待ちタイマーは`start`で開始済み）。
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

        session.write(PayloadCodec.encode(payload)) { [weak self] success in
            if !success {
                self?.finish(success: false)
            }
            // 成功時はここでは何もせず、相手からのNotify応答（handleResponse）を待つ
        }
    }

    /// PS設計書 6.2「60秒以内に待ち受けしたデータを検出した場合」の判定処理
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
