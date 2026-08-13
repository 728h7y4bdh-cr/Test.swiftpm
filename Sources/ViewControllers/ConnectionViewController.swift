import UIKit

/// Bluetooth接続画面（SS設計書 4章 / UI設計書 5章）
final class ConnectionViewController: UIViewController {
    private let myIdTextField = UITextField()
    private let targetIdTextField = UITextField()
    private let connectButton = UIButton(configuration: .filled())
    private let listenButton = UIButton(configuration: .filled())
    private let inputContainer = UIStackView()

    private let authorizationChecker = BluetoothAuthorizationChecker()
    private var isPermissionDeniedAlertPresented = false
    private var isProcessing = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Bluetooth接続"
        view.backgroundColor = .systemBackground
        navigationItem.hidesBackButton = true
        setUpInputUI()
        inputContainer.isHidden = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        myIdTextField.text = AppParameters.shared.myID
        targetIdTextField.text = AppParameters.shared.targetID
        checkBluetoothAuthorization()
    }

    // MARK: - UI構築

    private func setUpInputUI() {
        let myIdRow = makeIdRow(titleText: "自端末ID", textField: myIdTextField)
        let targetIdRow = makeIdRow(titleText: "接続先ID", textField: targetIdTextField)

        connectButton.setTitle("接続開始", for: .normal)
        connectButton.addTarget(self, action: #selector(didTapConnect), for: .touchUpInside)
        listenButton.setTitle("待受開始", for: .normal)
        listenButton.addTarget(self, action: #selector(didTapListen), for: .touchUpInside)

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

    // MARK: - Bluetooth使用許可確認（SS設計書 4.1）

    private func checkBluetoothAuthorization() {
        authorizationChecker.check { [weak self] granted in
            guard let self else { return }
            self.inputContainer.isHidden = !granted
            if granted {
                self.isPermissionDeniedAlertPresented = false
            } else {
                self.presentPermissionDeniedAlertIfNeeded()
            }
        }
    }

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

    // MARK: - ボタン処理（SS設計書 4.3）

    @objc private func didTapConnect() {
        beginHandshake { myID, targetID, completion in
            BluetoothManager.shared.startConnecting(myID: myID, targetID: targetID, completion: completion)
        } onSuccess: {
            self.navigationController?.pushViewController(SendViewController(), animated: true)
        }
    }

    @objc private func didTapListen() {
        beginHandshake { myID, targetID, completion in
            BluetoothManager.shared.startListening(myID: myID, targetID: targetID, completion: completion)
        } onSuccess: {
            self.navigationController?.pushViewController(ReceiveViewController(), animated: true)
        }
    }

    private func beginHandshake(
        _ startOperation: @escaping (String, String, @escaping (Bool) -> Void) -> Void,
        onSuccess: @escaping () -> Void
    ) {
        guard !isProcessing else { return }

        let myID = normalizedID(from: myIdTextField.text)
        let targetID = normalizedID(from: targetIdTextField.text)

        guard myID != targetID else {
            presentAlert(message: "「自端末IDと接続先ID」が一致しています」")
            return
        }

        AppParameters.shared.update(myID: myID, targetID: targetID)
        myIdTextField.text = myID
        targetIdTextField.text = targetID

        isProcessing = true
        let processingAlert = UIAlertController(title: nil, message: "接続中", preferredStyle: .alert)
        present(processingAlert, animated: true)

        startOperation(myID, targetID) { [weak self] success in
            guard let self else { return }
            self.isProcessing = false
            processingAlert.dismiss(animated: true) {
                if success {
                    onSuccess()
                } else {
                    self.presentAlert(message: "該当する端末がありませんでした")
                }
            }
        }
    }

    private func normalizedID(from text: String?) -> String {
        let digits = (text ?? "").filter(\.isNumber)
        let trimmed = String(digits.suffix(3))
        return String(repeating: "0", count: max(0, 3 - trimmed.count)) + trimmed
    }

    private func presentAlert(message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITextFieldDelegate

extension ConnectionViewController: UITextFieldDelegate {
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard let currentText = textField.text, let stringRange = Range(range, in: currentText) else { return true }
        let updatedText = currentText.replacingCharacters(in: stringRange, with: string)

        if !string.isEmpty && string.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) != nil {
            return false
        }
        return updatedText.count <= 3
    }
}
