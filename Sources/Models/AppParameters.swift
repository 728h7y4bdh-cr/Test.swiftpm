import Foundation

/// 内部パラメータ「自端末ID」「接続先ID」（PS設計書 2章）
final class AppParameters {
    static let shared = AppParameters()

    private init() {}

    private(set) var myID: String = "000"
    private(set) var targetID: String = "001"

    /// 初期化処理（PS設計書 6.1）：アプリ起動時に1度だけ呼び出す
    func resetToInitialValues() {
        myID = "000"
        targetID = "001"
    }

    /// Bluetooth接続画面のボタン押下時、不一致チェックがOKだった場合に呼び出す
    func update(myID: String, targetID: String) {
        self.myID = myID
        self.targetID = targetID
    }
}
