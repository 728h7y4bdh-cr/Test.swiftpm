#if DEBUG
import Foundation

/// デバッグ機能：プレビュー確認用バイパス（`DebugSettings.isPreviewBypassEnabled`）の
/// 有効／無効状態を監視し、コンソールへ警告ログを出力する。
///
/// 正式仕様（要件定義書・SS設計書・UI設計書）には存在しない、開発時のみのデバッグ処理であり、
/// `#if DEBUG`で囲われているためRelease／配布（TestFlight含む）ビルドには一切含まれない
/// （PS設計書 付録A.1「プレビュー確認用バイパス」参照）。
enum PreviewBypassLogger {
    /// 直近にログ出力した際の状態（未出力ならnil）
    private static var lastLoggedState: Bool?
    /// 画面によらず状態変化を検知し続けるための監視タイマー
    private static var monitorTimer: Timer?

    /// Bluetooth接続画面への遷移直後に1度だけ呼び出す想定のエントリーポイント。
    /// 呼び出し時点の状態をまずログ出力し、以降は画面遷移に関わらず定期的に状態を確認して、
    /// 変化があればその都度ログを出力し続ける。
    static func startMonitoringIfNeeded() {
        guard monitorTimer == nil else { return } // 既に監視中なら何もしない（多重起動防止）
        logIfNeeded(force: true)
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            logIfNeeded(force: false)
        }
    }

    /// 現在の状態を確認し、初回（force）または前回ログ時から変化していた場合のみ出力する。
    private static func logIfNeeded(force: Bool) {
        let current = DebugSettings.isPreviewBypassEnabled
        guard force || current != lastLoggedState else { return }
        lastLoggedState = current

        if current {
            print("⚠️ プレビューバイパス有効：実際のBluetooth通信を行いません")
        } else {
            print("⚠️ プレビューバイパス無効：実際のBluetooth通信を行います")
        }
    }
}
#endif
