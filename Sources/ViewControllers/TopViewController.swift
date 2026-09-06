import UIKit

/// TOP画面（SS設計書 3章「TOP画面仕様」 / UI設計書 4章「TOP画面」）。
/// 要件定義書 11.1「TOP画面」：アイコンタップ時に最初に表示する起動画面。
final class TopViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setUpTitleLabel()
    }

    /// SS設計書 3章「遷移条件」：画面表示から5秒経過後、自動的にBluetooth接続画面へ遷移する。
    /// viewDidAppear（表示アニメーション完了後）を起点にタイマーを開始する。
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            self?.transitionToConnectionScreen()
        }
    }

    /// SS設計書 3章「表示内容」：画面中央に文字列「BlueCom」を表示する
    /// （要件定義書 11.1：「画面中央に『BlueCom』の文字を表示する」）。
    /// UI設計書 4.2「lblTitle」参照：黒文字・1行・通常書体（太字にしない）。
    private func setUpTitleLabel() {
        let label = UILabel()
        label.text = "BlueCom"
        label.font = UIFont.systemFont(ofSize: 40, weight: .regular)
        label.textColor = .label
        label.textAlignment = .center
        label.accessibilityLabel = "BlueCom"
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16)
        ])
    }

    /// Bluetooth接続画面へ遷移する。TOP画面へは戻らせない仕様のため、pushではなく
    /// スタックの置き換え（setViewControllers）で遷移する（UI設計書 1章「ナビゲーション」方針）。
    private func transitionToConnectionScreen() {
        navigationController?.setViewControllers([ConnectionViewController()], animated: true)
    }
}
