import UIKit

// UIKit標準のAppDelegate/SceneDelegateによるアプリ起動方式。
// 本アプリはSwiftUIの`App`プロトコルを使わず、UIKitのみで構成する
// （要件定義書「開発言語のフレームワーク」：UIKit）。
@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    // Storyboard/Info.plistを使わない構成のため、@UIApplicationMainの代わりに
    // @main + 明示的なstatic func main()でUIApplicationMainを呼び出してアプリを起動する。
    static func main() {
        UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(AppDelegate.self))
    }

    var window: UIWindow?

    /// アプリ起動時に一度だけ呼ばれる。
    /// PS設計書 6.1「初期化処理」の内容をそのまま実行する：
    ///   1. ステータスにアイドルをセット（PS設計書 3.2 No.1「アプリ起動時」に対応するイベントで遷移）
    ///   2. 自端末IDに"000"をセット、接続先IDに"001"をセット（AppParameters.resetToInitialValues）
    /// （要件定義書 10章「初期化処理」にも対応する内容）
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        StatusManager.shared.apply(.appLaunched)
        AppParameters.shared.resetToInitialValues()
        return true
    }

    /// アプリ起動時にUISceneSessionへ紐づけるSceneDelegateを指定する（UIKitのマルチシーン対応の定型処理）。
    /// 画面（UIWindow・ナビゲーションのルート設定）自体はSceneDelegate側で構築する。
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}
