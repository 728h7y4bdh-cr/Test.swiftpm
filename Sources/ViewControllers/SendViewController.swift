import UIKit

/// データ送信画面（SS設計書 5章「データ送信画面仕様」 / UI設計書 6章「データ送信画面」）。
/// 要件定義書 11.3「データ送信画面」に対応する画面。Bluetooth接続画面の「接続開始」成功後（Central役）に遷移してくる。
final class SendViewController: CommunicationBaseViewController {
    // UI設計書 6.2「部品一覧」：接続先ID表示、送信データ選択用ピッカー、送信ボタン
    private let targetIdValueLabel = UILabel()
    private let picker = UIPickerView()
    private let sendButton = UIButton(configuration: .filled())

    /// SS設計書 5.2「入力項目」：送信データの選択肢は"YAMA"／"KAWA"の2つ
    private let options = ["YAMA", "KAWA"]
    private var selectedText = "YAMA"
    /// データ送信処理中かどうか。「戻る」ボタン制御（SS設計書 5.3）で参照する
    private var isSending = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "データ送信"
        view.backgroundColor = .systemBackground
        navigationItem.hidesBackButton = true
        // UI設計書 6.2：「戻る」はナビゲーションバー左のUIBarButtonItemとして配置する
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "戻る", style: .plain, target: self, action: #selector(didTapBack)
        )
        setUpUI()
        // Bluetooth接続の予期しない切断通知を受け取る（SS設計書 5.6「予期しない切断時の仕様」）
        BluetoothManager.shared.connectionDelegate = self
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // SS設計書 5.1「表示項目：内部パラメータ『接続先ID』の値を表示する」
        targetIdValueLabel.text = AppParameters.shared.targetID
        // 送信処理中に誤ってスワイプで戻れないようにする（SS設計書 5.3節：送信中は画面遷移不可）
        navigationController?.interactivePopGestureRecognizer?.isEnabled = false
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }

    // MARK: - UI構築（UI設計書 6.1「ワイヤーフレーム」・6.2「部品一覧」）

    private func setUpUI() {
        let targetTitleLabel = UILabel()
        targetTitleLabel.text = "接続先ID"
        let targetRow = UIStackView(arrangedSubviews: [targetTitleLabel, targetIdValueLabel])
        targetRow.axis = .horizontal
        targetRow.spacing = 12

        let sendDataTitleLabel = UILabel()
        sendDataTitleLabel.text = "送信データ"

        // SS設計書 5.2「入力項目：送信データをプルダウン（UIPickerView）で選択」
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

    // MARK: - 「戻る」ボタン（SS設計書 5.3「『戻る』ボタン仕様」）

    @objc private func didTapBack() {
        // SS設計書 5.3「データ送信処理中の場合：『データ送信中は画面の切り替えができません』を表示し、画面遷移は行わない」
        guard !isSending else {
            presentAlert(message: "データ送信中は画面の切り替えができません")
            return
        }
        // SS設計書 5.3「処理中でない場合：Bluetooth通信切断処理（PS設計書 6.4）を実行完了後、1つ前の画面へ遷移する」
        BluetoothManager.shared.disconnect { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
    }

    // MARK: - 「送信」ボタン（SS設計書 5.4「『送信』ボタン仕様」）

    @objc private func didTapSend() {
        guard !isSending else { return }
        isSending = true

        // SS設計書 5.4「処理中は『データ送信中』をダイアログで表示する（OKボタンなし）」
        let sendingAlert = UIAlertController(title: nil, message: "データ送信中", preferredStyle: .alert)
        present(sendingAlert, animated: true)

        // データ送信処理（PS設計書 6.5）を実行する
        BluetoothManager.shared.sendData(
            myID: AppParameters.shared.myID,
            targetID: AppParameters.shared.targetID,
            text: selectedText
        ) { [weak self] success in
            guard let self else { return }
            self.isSending = false
            sendingAlert.dismiss(animated: true) {
                // SS設計書 5.4「正常終了：『データ送信完了』／異常終了：『データ送信失敗』を表示。
                // いずれも画面遷移はせず、次のデータを送信可能な状態に戻る」
                self.presentAlert(message: success ? "データ送信完了" : "データ送信失敗")
            }
        }
    }
}

// MARK: - CommunicationBaseViewController（SS設計書 5.6「予期しない切断時の仕様」）

extension SendViewController {
    /// 予期しない切断検知時、送信処理が進行中であれば中断する（「データ送信中」表示を残さない）。
    /// ダイアログ表示〜画面遷移までの共通フローは`CommunicationBaseViewController`側が行う。
    override func willHandleUnexpectedDisconnect() {
        isSending = false
    }
}

// MARK: - UIPickerViewDataSource / UIPickerViewDelegate（SS設計書 5.2「送信データ」選択用）

extension SendViewController: UIPickerViewDataSource, UIPickerViewDelegate {
    func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        options.count
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        options[row]
    }

    /// 選択された値（"YAMA"／"KAWA"）を保持する。この値がデータ送信処理（PS設計書 6.5）の
    /// 入力データとしてASCII変換・0x20パディングされ送信される（PS設計書 4.5参照）。
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        selectedText = options[row]
    }
}
