import UIKit

/// データ受信画面（SS設計書 6章 / UI設計書 7章）
final class ReceiveViewController: UIViewController {
    private let sourceIdValueLabel = UILabel()
    private let destIdValueLabel = UILabel()
    private let dataValueLabel = UILabel()
    private let resumeButton = UIButton(configuration: .filled())

    private var invalidDataRevertTimer: Timer?
    private weak var currentInvalidDataAlert: UIAlertController?
    private var isStopping = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "データ受信"
        view.backgroundColor = .systemBackground
        navigationItem.hidesBackButton = true
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "戻る", style: .plain, target: self, action: #selector(didTapBack)
        )
        setUpUI()
        BluetoothManager.shared.receiveDelegate = self
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = false
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard presentedViewController == nil else { return }
        beginReceiving()
    }

    // MARK: - UI構築

    private func setUpUI() {
        let receiveDataTitleLabel = UILabel()
        receiveDataTitleLabel.text = "受信データ"
        receiveDataTitleLabel.font = UIFont.preferredFont(forTextStyle: .headline)

        let sourceRow = makeValueRow(titleText: "送信元ID", valueLabel: sourceIdValueLabel)
        let destRow = makeValueRow(titleText: "送信先ID", valueLabel: destIdValueLabel)
        let dataRow = makeValueRow(titleText: "データ", valueLabel: dataValueLabel)

        resumeButton.setTitle("受信再開", for: .normal)
        resumeButton.addTarget(self, action: #selector(didTapResume), for: .touchUpInside)
        resumeButton.isHidden = true

        let stack = UIStackView(arrangedSubviews: [receiveDataTitleLabel, sourceRow, destRow, dataRow, resumeButton])
        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32)
        ])
    }

    private func makeValueRow(titleText: String, valueLabel: UILabel) -> UIStackView {
        let titleLabel = UILabel()
        titleLabel.text = titleText
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.text = ""
        let row = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        row.axis = .horizontal
        row.spacing = 12
        return row
    }

    // MARK: - 受信処理の開始（SS設計書 6.2）

    private func beginReceiving() {
        presentReceivingAlert()
        BluetoothManager.shared.startReceiving()
    }

    private func presentReceivingAlert() {
        invalidDataRevertTimer?.invalidate()
        invalidDataRevertTimer = nil
        currentInvalidDataAlert = nil
        let alert = UIAlertController(title: nil, message: "受信中", preferredStyle: .alert)
        present(alert, animated: true)
    }

    @objc private func didTapResume() {
        resumeButton.isHidden = true
        beginReceiving()
    }

    // MARK: - 「戻る」ボタン（SS設計書 6.4）

    @objc private func didTapBack() {
        guard !isStopping else { return }
        isStopping = true
        invalidDataRevertTimer?.invalidate()
        invalidDataRevertTimer = nil
        currentInvalidDataAlert = nil

        let finishAndPop: () -> Void = { [weak self] in
            guard let self else { return }
            BluetoothManager.shared.disconnect {
                self.navigationController?.popViewController(animated: true)
            }
        }

        if let presented = presentedViewController {
            presented.dismiss(animated: true) {
                BluetoothManager.shared.stopReceiving(completion: finishAndPop)
            }
        } else {
            BluetoothManager.shared.stopReceiving(completion: finishAndPop)
        }
    }

    private func presentDetectionAlert(message: String, okHandler: (() -> Void)?) {
        let showAlert: () -> Void = { [weak self] in
            guard let self else { return }
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            if let okHandler {
                alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in okHandler() })
            }
            self.present(alert, animated: true)
        }
        if let presented = presentedViewController {
            presented.dismiss(animated: true, completion: showAlert)
        } else {
            showAlert()
        }
    }
}

// MARK: - BluetoothManagerReceiveDelegate（PS設計書 6.6 データ受信処理の結果通知）

extension ReceiveViewController: BluetoothManagerReceiveDelegate {
    /// 受信検出あり
    func bluetoothManager(_ manager: BluetoothManager, didDetect payload: Payload) {
        invalidDataRevertTimer?.invalidate()
        invalidDataRevertTimer = nil
        currentInvalidDataAlert = nil

        BluetoothManager.shared.stopReceiving { [weak self] in
            guard let self else { return }
            self.sourceIdValueLabel.text = payload.sourceID
            self.destIdValueLabel.text = payload.destinationID
            self.dataValueLabel.text = payload.inputDataText
            self.resumeButton.isHidden = false

            self.presentDetectionAlert(message: "データ受信完了", okHandler: {})
        }
    }

    /// 受信検出なし
    func bluetoothManagerDidFailToDetect(_ manager: BluetoothManager) {
        let showInvalidDataAlert: () -> Void = { [weak self] in
            guard let self else { return }
            let alert = UIAlertController(
                title: nil, message: "データを受信しましたが、不正データでした。", preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                self?.invalidDataRevertTimer?.invalidate()
                self?.invalidDataRevertTimer = nil
                self?.presentReceivingAlert()
            })
            self.currentInvalidDataAlert = alert
            self.present(alert, animated: true)

            self.invalidDataRevertTimer?.invalidate()
            self.invalidDataRevertTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self, weak alert] _ in
                // 表示中の内容が別のイベントで既に切り替わっていた場合は何もしない
                guard let self, let alert, self.currentInvalidDataAlert === alert,
                      self.presentedViewController === alert else { return }
                alert.dismiss(animated: true) {
                    self.presentReceivingAlert()
                }
            }
        }

        if let presented = presentedViewController {
            presented.dismiss(animated: true, completion: showInvalidDataAlert)
        } else {
            showInvalidDataAlert()
        }
    }

    /// 受信中に相手端末との接続が予期せず切断された
    func bluetoothManagerDidDisconnectUnexpectedly(_ manager: BluetoothManager) {
        guard !isStopping else { return }
        isStopping = true
        invalidDataRevertTimer?.invalidate()
        invalidDataRevertTimer = nil
        currentInvalidDataAlert = nil

        let popBack: () -> Void = { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
        if let presented = presentedViewController {
            presented.dismiss(animated: true, completion: popBack)
        } else {
            popBack()
        }
    }
}
