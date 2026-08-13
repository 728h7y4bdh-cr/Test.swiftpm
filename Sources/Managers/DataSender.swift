import Foundation

/// データ送信処理（PS設計書 6.5、要件定義書 8章）。Central役。
///
/// 既に確立済みのセッション（Bluetooth通信開始処理で接続済みの`BluetoothCentralSession`）を
/// 通じて、テストデータを1回送信するだけに責任を持つ。通信開始ハンドシェイク
/// （`ConnectionStartHandshake`）の知識は一切持たない（別の処理単位として完全に独立させる）。
final class DataSender {
    private let session: BluetoothCentralSession

    init(session: BluetoothCentralSession) {
        self.session = session
    }

    /// 処理を実行する。結果（true=正常終了／false=異常終了）はcompletionで通知する。
    func send(myID: String, targetID: String, text: String, completion: @escaping (Bool) -> Void) {
        // PS設計書 3.2 No.10：データ送信開始時にsendingへ遷移
        StatusManager.shared.apply(.dataSendStarted)

        // PS設計書 6.5「送信データ」：送信種別0x29固定・通信種別0x02、
        // 入力データは選択されたテストデータをASCII変換し0x20埋め（PayloadCodec.paddedInputData）
        let payload = Payload(
            payloadType: .request,
            communicationType: .data,
            sourceID: myID,
            destinationID: targetID,
            inputData: PayloadCodec.paddedInputData(from: text)
        )

        session.write(PayloadCodec.encode(payload)) { success in
            if success {
                // PS設計書 3.2 No.5：データ送信完了時にwaitingToSendへ遷移
                StatusManager.shared.apply(.dataSendCompleted)
            }
            completion(success)
        }
    }
}
