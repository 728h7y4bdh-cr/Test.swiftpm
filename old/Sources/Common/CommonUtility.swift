import Foundation

/// アプリ全体のどこからでも呼び出せる、汎用的な補助機能（アサート・比較等）をまとめる場所。
///
/// Bluetooth通信に特化した共通処理は`CommunicationBaseViewController`（画面が継承する基底クラス）が
/// 担当するのに対し、こちらは画面（ViewController）に限らずアプリ内のどのクラスからでも使える
/// 汎用ヘルパーを置く場所とする。Swiftはクラスの多重継承をサポートしないため（あるクラスが
/// 同時に2つの基底クラスを持つことはできない）、`UIViewController`を継承する画面クラスも、
/// それ以外のクラス（`Manager`等）も区別なく使えるようにするため、継承（基底クラス）ではなく、
/// インスタンス化不要な`enum`＋`static func`の形を採用している（`PayloadCodec`と同じ形）。
///
/// 今後、比較関数など新しい種類の汎用ヘルパーが必要になった場合も、このenumに`static func`を
/// 追加していくだけでよく、既存の呼び出し元・継承関係には一切影響しない。
enum CommonUtility {
    /// 満たされているべき条件を確認する。falseの場合、Debugビルドでのみ`assertionFailure`で検知する
    /// （Releaseビルドでは無視され、クラッシュしない）。
    /// 各所で個別に`assertionFailure`を呼ぶ代わりにここを経由することで、
    /// アサートのメッセージ体裁を揃え、将来的な検知方法の変更（ログ送信の追加等）を1箇所に閉じ込める。
    ///
    /// `condition`・`message`ともに`@autoclosure`にしているのは、Swift標準の`assert`と同様、
    /// Releaseビルドでは呼び出し元の式が一切評価されないようにするため（重い判定処理を渡しても、
    /// 本番では評価コストがかからない）。
    static func assert(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String) {
        guard !condition() else { return }
        assertionFailure(message())
    }
}
