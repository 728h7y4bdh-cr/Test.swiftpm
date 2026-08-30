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

    /// アプリ起動時に一度だけ呼ばれる。初期化処理（PS設計書 6.1、要件定義書 10章）を実行する。
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        AppInitializer.initialize()
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
