import UIKit

/// データ送信画面（SS設計書 5章 / UI設計書 6章）
final class SendViewController: UIViewController {
    private let targetIdValueLabel = UILabel()
    private let picker = UIPickerView()
    private let sendButton = UIButton(configuration: .filled())

    private let options = ["YAMA", "KAWA"]
    private var selectedText = "YAMA"
    private var isSending = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "データ送信"
        view.backgroundColor = .systemBackground
        navigationItem.hidesBackButton = true
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "戻る", style: .plain, target: self, action: #selector(didTapBack)
        )
        setUpUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        targetIdValueLabel.text = AppParameters.shared.targetID
        // 送信処理中に誤ってスワイプで戻れないようにする（5.3節: 送信中は画面遷移不可）
        navigationController?.interactivePopGestureRecognizer?.isEnabled = false
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }

    // MARK: - UI構築

    private func setUpUI() {
        let targetTitleLabel = UILabel()
        targetTitleLabel.text = "接続先ID"
        let targetRow = UIStackView(arrangedSubviews: [targetTitleLabel, targetIdValueLabel])
        targetRow.axis = .horizontal
        targetRow.spacing = 12

        let sendDataTitleLabel = UILabel()
        sendDataTitleLabel.text = "送信データ"

        picker.dataSource = self
        picker.delegate = self
        picker.translatesAutoresizingMaskIntoConstraints = false

        let sendDataRow = UIStackView(arrangedSubviews: [sendDataTitleLabel, picker])
        sendDataRow.axis = .horizontal
        sendDataRow.spacing = 12

        sendButton.setTitle("送信", for: .normal)
        sendButton.addTarget(self, action: #selector(didTapSend), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [targetRow, sendDataRow, sendButton])
        stack.axis = .vertical
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            picker.heightAnchor.constraint(equalToConstant: 100)
        ])
    }

    // MARK: - 「戻る」ボタン（SS設計書 5.3）

    @objc private func didTapBack() {
        guard !isSending else {
            presentAlert(message: "データ送信中は画面の切り替えができません")
            return
        }
        BluetoothManager.shared.disconnect { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
    }

    // MARK: - 「送信」ボタン（SS設計書 5.4）

    @objc private func didTapSend() {
        guard !isSending else { return }
        isSending = true

        let sendingAlert = UIAlertController(title: nil, message: "データ送信中", preferredStyle: .alert)
        present(sendingAlert, animated: true)

        BluetoothManager.shared.sendData(
            myID: AppParameters.shared.myID,
            targetID: AppParameters.shared.targetID,
            text: selectedText
        ) { [weak self] success in
            guard let self else { return }
            self.isSending = false
            sendingAlert.dismiss(animated: true) {
                self.presentAlert(message: success ? "データ送信完了" : "データ送信失敗")
            }
        }
    }

    private func presentAlert(message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UIPickerViewDataSource / UIPickerViewDelegate

extension SendViewController: UIPickerViewDataSource, UIPickerViewDelegate {
    func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        options.count
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        options[row]
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        selectedText = options[row]
    }
}
