import UIKit

/// ウィンドウとナビゲーションのルートを構築する。
/// SS設計書 2章「画面遷移図」の起点として、最初にTOP画面（TopViewController）を
/// UINavigationControllerのルートに設定する。
/// 以降の画面遷移（TOP→Bluetooth接続→データ送信/データ受信→戻る）は
/// 各ViewController側でこのUINavigationControllerを介して行う。
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        // SS設計書 3章「TOP画面仕様」：起動時に最初に表示する画面としてTopViewControllerを設定
        let navigationController = UINavigationController(rootViewController: TopViewController())
        window.rootViewController = navigationController
        self.window = window
        window.makeKeyAndVisible()
    }
}
