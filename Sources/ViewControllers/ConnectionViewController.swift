import UIKit

/// Bluetooth接続画面（SS設計書 4章「Bluetooth接続画面仕様」 / UI設計書 5章「Bluetooth接続画面」）。
/// 要件定義書 11.2「Bluetooth接続画面」に対応する画面。
final class ConnectionViewController: UIViewController {
    // UI設計書 5.2「部品一覧」：自端末ID／接続先IDの入力欄、接続開始／待受開始ボタン
    private let myIdTextField = UITextField()
    private let targetIdTextField = UITextField()
    private let connectButton = UIButton(configuration: .filled())
    private let listenButton = UIButton(configuration: .filled())
    /// 入力欄・ボタンをまとめたコンテナ。Bluetooth使用許可が下りるまで非表示にする（SS設計書 4.1）
    private let inputContainer = UIStackView()

    private let authorizationChecker = BluetoothAuthorizationChecker()
    /// SS設計書 4.1「不許可」ダイアログを二重に表示しないための状態フラグ
    private var isPermissionDeniedAlertPresented = false
    /// 「接続中」処理中に、ボタン連打で二重に処理が走らないようにするフラグ
    private var isProcessing = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Bluetooth接続"
        view.backgroundColor = .systemBackground
        navigationItem.hidesBackButton = true
        setUpInputUI()
        // 許可確認が完了するまでは入力項目・ボタンを隠しておく（SS設計書 4.1 No.2「許可」時に表示する）
        inputContainer.isHidden = true
    }

    /// 画面表示のたびに、内部パラメータの値を入力欄へ反映し、Bluetooth使用許可を確認する。
    /// SS設計書 4.2「画面遷移時、内部パラメータ『自端末ID』『接続先ID』の値をそれぞれの入力項目に表示する」
    /// に対応（データ送信／データ受信画面から「戻る」で本画面へ再表示された場合も同様に反映する）。
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        myIdTextField.text = AppParameters.shared.myID
        targetIdTextField.text = AppParameters.shared.targetID
        checkBluetoothAuthorization()
    }

    // MARK: - UI構築（UI設計書 5.1「ワイヤーフレーム」・5.2「部品一覧」）

    private func setUpInputUI() {
        let myIdRow = makeIdRow(titleText: "自端末ID", textField: myIdTextField)
        let targetIdRow = makeIdRow(titleText: "接続先ID", textField: targetIdTextField)

        connectButton.setTitle("接続開始", for: .normal)
        connectButton.addTarget(self, action: #selector(didTapConnect), for: .touchUpInside)
        listenButton.setTitle("待受開始", for: .normal)
        listenButton.addTarget(self, action: #selector(didTapListen), for: .touchUpInside)

        // SS設計書 4.3「接続開始ボタンと待受開始ボタンは横並びで表示」
        let buttonRow = UIStackView(arrangedSubviews: [connectButton, listenButton])
        buttonRow.axis = .horizontal
        buttonRow.spacing = 16
        buttonRow.distribution = .fillEqually

        inputContainer.axis = .vertical
        inputContainer.spacing = 24
        inputContainer.addArrangedSubview(myIdRow)
        inputContainer.addArrangedSubview(targetIdRow)
        inputContainer.addArrangedSubview(buttonRow)
        inputContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(inputContainer)

        NSLayoutConstraint.activate([
            inputContainer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            inputContainer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            inputContainer.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor)
        ])
    }

    /// 自端末ID／接続先ID共通の「タイトルラベル＋入力欄」の行を構築する。
    /// SS設計書 4.2「入力可能文字は半角数値のみ」に合わせ、数値専用キーボードを指定する
    /// （実際の桁数・文字種の制限はUITextFieldDelegateで行う）。
    private func makeIdRow(titleText: String, textField: UITextField) -> UIStackView {
        let label = UILabel()
        label.text = titleText
        label.font = UIFont.preferredFont(forTextStyle: .body)
        label.setContentHuggingPriority(.required, for: .horizontal)

        textField.borderStyle = .roundedRect
        textField.keyboardType = .numberPad
        textField.textAlignment = .center
        textField.delegate = self
        textField.accessibilityLabel = "\(titleText)入力"

        let row = UIStackView(arrangedSubviews: [label, textField])
        row.axis = .horizontal
        row.spacing = 12
        return row
    }

    // MARK: - Bluetooth使用許可確認（SS設計書 4.1「Bluetooth使用許可確認」）

    /// SS設計書 4.1 No.1〜No.4の一連の流れを実行する。
    /// 実際のOS標準ダイアログ表示・許可状態の判定は`BluetoothAuthorizationChecker`が担う。
    private func checkBluetoothAuthorization() {
        authorizationChecker.check { [weak self] granted in
            guard let self else { return }
            // SS設計書 4.1 No.2「『許可』を選択した場合：ダイアログの表示を消し、入力項目・ボタンを表示する」
            self.inputContainer.isHidden = !granted
            if granted {
                self.isPermissionDeniedAlertPresented = false
            } else {
                // SS設計書 4.1 No.3「『不許可』を選択した場合：固定文言のダイアログを表示する」
                self.presentPermissionDeniedAlertIfNeeded()
            }
        }
    }

    /// SS設計書 4.1 No.3／4.4 No.2「設定からBluetoothの使用を許可してアプリを再起動してください。」
    /// を固定表示するダイアログ。ボタンを持たず、アプリ再起動まで表示し続ける想定のため、
    /// 一度表示したら`isPermissionDeniedAlertPresented`で多重表示を防ぐ。
    private func presentPermissionDeniedAlertIfNeeded() {
        guard !isPermissionDeniedAlertPresented else { return }
        isPermissionDeniedAlertPresented = true
        let alert = UIAlertController(
            title: nil,
            message: "設定からBluetoothの使用を許可してアプリを再起動してください。",
            preferredStyle: .alert
        )
        present(alert, animated: true)
    }

    // MARK: - ボタン処理（SS設計書 4.3「ボタン仕様」）

    /// 「接続開始」ボタン（SS設計書 4.3.2）：不一致チェック→Bluetooth通信開始処理（PS設計書 6.2）を実行し、
    /// 正常終了ならデータ送信画面へ遷移する。
    @objc private func didTapConnect() {
        beginHandshake { myID, targetID, completion in
            BluetoothManager.shared.startConnecting(myID: myID, targetID: targetID, completion: completion)
        } onSuccess: {
            self.navigationController?.pushViewController(SendViewController(), animated: true)
        }
    }

    /// 「待受開始」ボタン（SS設計書 4.3.3）：不一致チェック→Bluetooth待受開始処理（PS設計書 6.3）を実行し、
    /// 正常終了ならデータ受信画面へ遷移する。
    @objc private func didTapListen() {
        beginHandshake { myID, targetID, completion in
            BluetoothManager.shared.startListening(myID: myID, targetID: targetID, completion: completion)
        } onSuccess: {
            self.navigationController?.pushViewController(ReceiveViewController(), animated: true)
        }
    }

    /// 「接続開始」「待受開始」共通の処理フロー。
    /// SS設計書 4.3.1「共通処理（不一致チェック）」〜 4.3.2／4.3.3の「処理中ダイアログ表示→結果分岐」までを
    /// 1つの関数にまとめ、呼び出し元（startOperation）と成功時遷移先（onSuccess）だけを差し替える。
    private func beginHandshake(
        _ startOperation: @escaping (String, String, @escaping (Bool) -> Void) -> Void,
        onSuccess: @escaping () -> Void
    ) {
        guard !isProcessing else { return }

        let myID = normalizedID(from: myIdTextField.text)
        let targetID = normalizedID(from: targetIdTextField.text)

        // SS設計書 4.3.1「一致（自端末ID = 接続先ID）：ダイアログを表示し、処理を開始せず画面遷移も行わない」
        guard myID != targetID else {
            presentAlert(message: "「自端末IDと接続先ID」が一致しています」")
            return
        }

        // SS設計書 4.3.1「不一致：入力値をそれぞれ内部パラメータへ保存したうえで、後続の処理を開始する」
        AppParameters.shared.update(myID: myID, targetID: targetID)
        myIdTextField.text = myID
        targetIdTextField.text = targetID

        isProcessing = true
        // SS設計書 4.3.2／4.3.3「処理中は『接続中』を表示する」
        let processingAlert = UIAlertController(title: nil, message: "接続中", preferredStyle: .alert)
        present(processingAlert, animated: true)

        startOperation(myID, targetID) { [weak self] success in
            guard let self else { return }
            self.isProcessing = false
            processingAlert.dismiss(animated: true) {
                if success {
                    // SS設計書 4.3.2／4.3.3「正常終了の場合、ダイアログを閉じ、対応する画面へ遷移する」
                    onSuccess()
                } else {
                    // SS設計書 4.3.2／4.3.3「異常終了の場合、『該当する端末がありませんでした』を表示し、画面遷移は行わない」
                    self.presentAlert(message: "該当する端末がありませんでした")
                }
            }
        }
    }

    /// テキストフィールドの入力値を3桁の数値文字列に正規化する（先頭0埋め）。
    /// PS設計書 4.4「ID変換仕様」が3桁固定のIDを前提としているため、
    /// ユーザーが1〜2桁しか入力しなかった場合でも先頭を0で埋めて3桁に揃える。
    private func normalizedID(from text: String?) -> String {
        let digits = (text ?? "").filter(\.isNumber)
        let trimmed = String(digits.suffix(3))
        return String(repeating: "0", count: max(0, 3 - trimmed.count)) + trimmed
    }

    /// OKボタン付きの単純なメッセージダイアログを表示する共通ヘルパー
    /// （SS設計書 4.4「ダイアログ文言一覧」に記載の各文言表示に使用）。
    private func presentAlert(message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITextFieldDelegate（SS設計書 4.2「入力項目」のバリデーション）

extension ConnectionViewController: UITextFieldDelegate {
    /// SS設計書 4.2「入力可能文字は半角数値のみ」「入力桁数は最大3桁までとする」を満たすよう、
    /// 数値以外の入力を拒否し、入力後の文字数が3桁を超える変更も拒否する。
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard let currentText = textField.text, let stringRange = Range(range, in: currentText) else { return true }
        let updatedText = currentText.replacingCharacters(in: stringRange, with: string)

        if !string.isEmpty && string.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) != nil {
            return false
        }
        return updatedText.count <= 3
    }
}
