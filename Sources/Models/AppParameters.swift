import Foundation

/// 内部パラメータ「自端末ID」「接続先ID」を保持するクラス（PS設計書 2章「内部パラメータ」）。
/// アプリ全体で単一のインスタンスを共有するため、シングルトン（`shared`）として提供する。
final class AppParameters {
    static let shared = AppParameters()

    private init() {}

    /// 自端末ID（3桁の数値文字列 "000"〜"999"）。初期値は"000"（PS設計書 2章）
    private(set) var myID: String = "000"
    /// 接続先ID（3桁の数値文字列 "000"〜"999"）。初期値は"001"（PS設計書 2章）
    private(set) var targetID: String = "001"

    /// 初期化処理（PS設計書 6.1「初期化処理」）：アプリ起動時に1度だけ呼び出す。
    /// 自端末IDに"000"、接続先IDに"001"をセットする
    /// （要件定義書 10章「初期化処理」：「自端末ID」に000、「接続先ID」に001をセットする、に対応）。
    func resetToInitialValues() {
        myID = "000"
        targetID = "001"
    }

    /// Bluetooth接続画面の「接続開始」／「待受開始」ボタン押下時、自端末IDと接続先IDの
    /// 不一致チェックがOK（不一致）だった場合に、入力値を内部パラメータへ保存する処理。
    /// SS設計書 4.3.1「共通処理（不一致チェック）」の「不一致」時の処理に対応する。
    func update(myID: String, targetID: String) {
        self.myID = myID
        self.targetID = targetID
    }
}
