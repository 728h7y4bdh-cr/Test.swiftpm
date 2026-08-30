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

    /// SS設計書 3章「表示内容」：画面中央に文字列「Sample App for BlueCom」を表示する
    /// （要件定義書 11.1：「画面中央に『Sample App for BlueCom』の文字を表示する」）。
    /// 見た目のアクセントとして、メインタイトルとサブタイトルで書体・サイズ・色に強弱をつける
    /// （UI設計書 4.2「lblTitle」参照。表示する文字列自体は1本のラベルにまとめている）。
    private func setUpTitleLabel() {
        let label = UILabel()
        label.attributedText = makeTitleAttributedString()
        label.numberOfLines = 0
        label.textAlignment = .center
        label.accessibilityLabel = "Sample App for BlueCom"
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16)
        ])
    }

    private func makeTitleAttributedString() -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineSpacing = 8

        let result = NSMutableAttributedString(
            string: "Sample App\n",
            attributes: [
                .font: UIFont.systemFont(ofSize: 40, weight: .heavy),
                .foregroundColor: UIColor.systemBlue,
                .paragraphStyle: paragraphStyle
            ]
        )
        result.append(NSAttributedString(
            string: "FOR BLUECOM",
            attributes: [
                .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: UIColor.secondaryLabel,
                .kern: 2.5,
                .paragraphStyle: paragraphStyle
            ]
        ))
        return result
    }

    /// Bluetooth接続画面へ遷移する。TOP画面へは戻らせない仕様のため、pushではなく
    /// スタックの置き換え（setViewControllers）で遷移する（UI設計書 1章「ナビゲーション」方針）。
    private func transitionToConnectionScreen() {
        navigationController?.setViewControllers([ConnectionViewController()], animated: true)
    }
}
