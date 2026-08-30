import Foundation

/// データ送信処理（PS設計書 6.5、要件定義書 8章）。Central役。
///
/// 既に確立済みのセッション（Bluetooth通信開始処理で接続済みの`BluetoothCentralSession`）を
/// 通じて、テストデータを1回送信し、相手からの応答（PS設計書6.6「検出時送信データ」）を
/// 10秒以内に検出できるかまでを見届けるのに責任を持つ。通信開始ハンドシェイク
/// （`ConnectionStartHandshake`）の知識は一切持たない（別の処理単位として完全に独立させる）。
final class DataSender {
    /// PS設計書 6.5：送信の瞬間から応答検出までに許容する時間
    private static let timeoutInterval: TimeInterval = 10.0

    private let session: BluetoothCentralSession
    private var timeoutTimer: Timer?
    private var completion: ((Bool) -> Void)?

    init(session: BluetoothCentralSession) {
        self.session = session
    }

    /// 処理を実行する。結果（true=正常終了／false=異常終了）はcompletionで通知する。
    func send(myID: String, targetID: String, text: String, completion: @escaping (Bool) -> Void) {
        // PS設計書 3.2 No.10：データ送信開始時にsendingへ遷移
        StatusManager.shared.apply(.dataSendStarted)
        self.completion = completion

        session.onResponseReceived = { [weak self] data in
            self?.handleResponse(data, myID: myID, targetID: targetID)
        }

        // PS設計書 6.5：送信の瞬間から10秒のタイムアウトを設定する
        timeoutTimer?.invalidate()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: Self.timeoutInterval, repeats: false) { [weak self] _ in
            self?.finish(success: false)
        }

        // PS設計書 6.5「送信データ」：送信種別0x29固定・通信種別0x02、
        // 入力データは選択されたテストデータをASCII変換し0x20埋め（PayloadCodec.paddedInputData）
        let payload = Payload(
            payloadType: .request,
            communicationType: .data,
            sourceID: myID,
            destinationID: targetID,
            inputData: PayloadCodec.paddedInputData(from: text)
        )

        session.write(PayloadCodec.encode(payload)) { [weak self] success in
            if !success {
                self?.finish(success: false)
            }
            // 成功時はここでは何もせず、相手からの応答（Notify）を待つ
        }
    }

    /// PS設計書 6.5「待受内容」の判定処理
    private func handleResponse(_ data: Data, myID: String, targetID: String) {
        guard let payload = PayloadCodec.decode(data) else { return }
        // PS設計書 6.5「待受内容」：送信種別0x92固定・通信種別0x02、
        // 送信元ID＝送信時の送信先ID、送信先ID＝送信時の送信元ID、入力データ＝0x20埋め
        guard payload.payloadType == .response, payload.communicationType == .data,
              payload.sourceID == targetID, payload.destinationID == myID,
              payload.inputData == PayloadCodec.blankInputData else {
            return // 不一致のデータは無視し、タイムアウトまで待ち続ける
        }
        finish(success: true)
    }

    private func finish(success: Bool) {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        session.onResponseReceived = nil

        let completion = self.completion
        self.completion = nil

        if success {
            // PS設計書 3.2 No.5：データ送信完了時にwaitingToSendへ遷移
            StatusManager.shared.apply(.dataSendCompleted)
        }
        completion?(success)
    }
}
