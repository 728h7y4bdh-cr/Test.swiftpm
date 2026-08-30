import Foundation

/// データ受信処理（PS設計書 6.6、要件定義書 9章）。Peripheral役。
///
/// 既に確立済みのセッション（Bluetooth待受開始処理で接続済みの`BluetoothPeripheralSession`）を
/// 通じて届くWriteを監視し、"YAMA"/"KAWA"データの検出可否を判定するだけに責任を持つ。
/// 待受開始ハンドシェイク（`ListenStartHandshake`）の知識は一切持たない
/// （ハンドシェイクと受信処理を混在させない）。
final class DataReceiver {
    private let session: BluetoothPeripheralSession
    private let myID: String
    private let targetID: String

    /// チェックOKのデータを検出した（PS設計書 6.6「チェックOK時：コール元に『受信検出あり』を通知」）
    var onDetect: ((Payload) -> Void)?
    /// チェックNGだった（PS設計書 6.6「チェックNG時：コール元に『受信検出なし』を通知」）
    var onNotDetect: (() -> Void)?

    /// PS設計書 6.6のデータ受信処理が実行中かどうか（「受信終了要求」検出後はfalseになる）
    private(set) var isReceiving = false

    init(session: BluetoothPeripheralSession, myID: String, targetID: String) {
        self.session = session
        self.myID = myID
        self.targetID = targetID
    }

    /// データ受信処理を開始する（待受成功直後、または「受信再開」ボタン押下時の両方から呼ばれる）。
    /// 呼び出し以降、セッションに届くWriteの解釈はこのクラスのみが行う
    /// （待受開始ハンドシェイクからの受信窓口の引き継ぎはCoordinatorが行う）。
    func start() {
        // PS設計書 3.2 No.8：「再開」ボタンタップ時（および待受成功直後の初回開始時）にwaitingToReceiveへ遷移
        StatusManager.shared.apply(.receivingStarted)
        isReceiving = true
        session.onWriteReceived = { [weak self] data in
            self?.handleWrite(data)
        }
    }

    /// 「受信終了要求」の通知を受け、データ受信処理を終了する。
    /// 完了後（ステータスをreceiveStoppingに遷移させた後）に「受信終了完了」としてcompletionを呼び出す。
    /// Bluetooth接続自体は切断しない（切断は別処理＝PS設計書6.4。呼び出し元が必要に応じて別途行う）。
    func stop(completion: @escaping () -> Void) {
        isReceiving = false
        session.onWriteReceived = nil
        // PS設計書 3.2 No.9：「受信終了要求」検出→「受信終了完了」通知時にreceiveStoppingへ遷移
        StatusManager.shared.apply(.receiveStopRequested)
        DispatchQueue.main.async {
            completion()
        }
    }

    /// PS設計書 9章／6.6「データチェック内容」の判定処理
    private func handleWrite(_ data: Data) {
        guard isReceiving else { return } // 受信終了要求後（受信停止中）に届いたWriteは無視する
        guard let payload = PayloadCodec.decode(data) else { return }

        // 送信種別0x29・通信種別0x02、送信元ID＝接続先ID、送信先ID＝自端末ID、
        // 入力データ＝ASCII"YAMA"または"KAWA"（10byte固定・0x20埋め）であることを確認する。
        // 文字列化してtrimする方式だと、先頭にスペースが入った不正な電文
        // （例: " YAMA     "）まで正常データとして誤判定してしまうため、
        // 10byteのバイト列同士をそのまま比較する
        guard payload.communicationType == .data, payload.payloadType == .request,
              payload.sourceID == targetID, payload.destinationID == myID,
              payload.inputData == PayloadCodec.paddedInputData(from: "YAMA")
              || payload.inputData == PayloadCodec.paddedInputData(from: "KAWA") else {
            onNotDetect?()
            return
        }
        onDetect?(payload)
    }
}
