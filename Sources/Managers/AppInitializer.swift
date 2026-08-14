import Foundation

/// 初期化処理（PS設計書 6.1、要件定義書 10章）。アプリ起動時に1度だけ実行する。
///
/// 現時点の内容はパラメータの初期化のみだが、それ自体の実処理は行わず、
/// パラメータ管理の機能（`AppParameters`）が持つAPIを呼び出すだけにとどめる
/// （癒着防止：初期化処理はパラメータの中身を知らない）。
/// 将来的に初期化処理が増えた場合は、このenumの中に呼び出しを追加していく
/// （呼び出し元のAppDelegateは変更不要）。
enum AppInitializer {
    static func initialize() {
        // PS設計書 3.2 No.1：アプリ起動時にステータスをアイドルへセット
        StatusManager.shared.apply(.appLaunched)
        // PS設計書 6.1：自端末IDに"000"、接続先IDに"001"をセット（実処理はAppParameters側）
        AppParameters.shared.resetToInitialValues()
    }
}
