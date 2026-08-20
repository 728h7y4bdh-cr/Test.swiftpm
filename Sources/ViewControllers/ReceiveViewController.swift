import UIKit

/// データ受信画面（SS設計書 6章「データ受信画面仕様」 / UI設計書 7章「データ受信画面」）。
/// 要件定義書 11.4「データ受信画面」に対応する画面。Bluetooth接続画面の「待受開始」成功後（Peripheral役）に遷移してくる。
final class ReceiveViewController: CommunicationBaseViewController {
    // UI設計書 7.2「部品一覧」：受信データの小項目3つ（送信元ID／送信先ID／データ）と「受信再開」ボタン
    private let sourceIdValueLabel = UILabel()
    private let destIdValueLabel = UILabel()
    private let dataValueLabel = UILabel()
    private let resumeButton = UIButton(configuration: .filled())

    /// SS設計書 6.5 No.3「OKボタンが操作されないまま5秒経過した場合、ダイアログの表示を『受信中』に戻す」用のタイマー
    private var invalidDataRevertTimer: Timer?
    /// 上記タイマー発火時、表示中のダイアログが「まだこの不正データダイアログのままか」を確認するための弱参照。
    /// 「受信検出あり」等の別イベントで既にダイアログが切り替わっていた場合に誤って割り込まないためのガード。
    private weak var currentInvalidDataAlert: UIAlertController?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "データ受信"
        view.backgroundColor = .systemBackground
        navigationItem.hidesBackButton = true
        // UI設計書 7.2：「戻る」はナビゲーションバー左のUIBarButtonItemとして配置する
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "戻る", style: .plain, target: self, action: #selector(didTapBack)
        )
        setUpUI()
        // データ受信処理（PS設計書 6.6）の結果通知（受信検出あり／なし）を本画面で受け取る
        BluetoothManager.shared.receiveDelegate = self
        // Bluetooth接続の予期しない切断通知を受け取る（SS設計書 6.6「予期しない切断時の仕様」）
        BluetoothManager.shared.connectionDelegate = self
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = false
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }

    /// SS設計書 6.2「画面遷移直後の処理フロー」の起点：部品表示後、受信処理を開始する。
    /// `presentedViewController == nil`のガードは、バックグラウンド復帰等でviewDidAppearが
    /// 再度呼ばれた際に受信処理・ダイアログ表示を二重開始しないための保険。
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard presentedViewController == nil else { return }
        beginReceiving()
    }

    // MARK: - UI構築（UI設計書 7.1「ワイヤーフレーム」・7.2「部品一覧」）

    private func setUpUI() {
        // SS設計書 6.1「大項目『受信データ』」
        let receiveDataTitleLabel = UILabel()
        receiveDataTitleLabel.text = "受信データ"
        receiveDataTitleLabel.font = UIFont.preferredFont(forTextStyle: .headline)

        // SS設計書 6.1「小項目『送信元ID』『送信先ID』『データ』：画面遷移時は全て空欄表示」
        let sourceRow = makeValueRow(titleText: "送信元ID", valueLabel: sourceIdValueLabel)
        let destRow = makeValueRow(titleText: "送信先ID", valueLabel: destIdValueLabel)
        let dataRow = makeValueRow(titleText: "データ", valueLabel: dataValueLabel)

        resumeButton.setTitle("受信再開", for: .normal)
        resumeButton.addTarget(self, action: #selector(didTapResume), for: .touchUpInside)
        // 「受信再開」ボタンは受信検出あり（SS設計書 6.2 No.2）が起きるまで非表示
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

    // MARK: - 受信処理の開始（SS設計書 6.2「画面遷移直後の処理フロー」）

    /// SS設計書 6.2「『受信中』ダイアログを表示後、データ受信処理を開始する」。
    /// 画面遷移直後（viewDidAppear）と、「受信再開」ボタン押下時（didTapResume）の
    /// 2箇所から呼ばれる共通処理。
    private func beginReceiving() {
        presentReceivingAlert()
        BluetoothManager.shared.startReceiving() // PS設計書 6.6「データ受信処理」開始
    }

    /// SS設計書 6.5 No.1「受信中：ダイアログを表示する（OKボタンなし・表示固定）」を表示する。
    /// 呼び出し前に、不正データ用の再表示タイマー・ダイアログ参照をクリアしておく
    /// （不正データダイアログの5秒タイマーが後から誤発火しないようにするため）。
    private func presentReceivingAlert() {
        invalidDataRevertTimer?.invalidate()
        invalidDataRevertTimer = nil
        currentInvalidDataAlert = nil
        let alert = UIAlertController(title: nil, message: "受信中", preferredStyle: .alert)
        present(alert, animated: true)
    }

    /// SS設計書 6.3「『受信再開』ボタン仕様：タップするとデータ受信処理を再度開始する」
    @objc private func didTapResume() {
        resumeButton.isHidden = true
        beginReceiving()
    }

    // MARK: - 「戻る」ボタン（SS設計書 6.4「『戻る』ボタン仕様」）

    /// SS設計書 6.4の3ステップをそのまま実行する：
    ///   1. データ受信処理に「受信終了要求」を通知し、「受信終了完了」の通知を受けるまで待機する
    ///   2. Bluetooth通信切断処理（PS設計書 6.4）を実行する
    ///   3. 1つ前の画面（Bluetooth接続画面）へ遷移する
    @objc private func didTapBack() {
        // 予期しない切断の処理と同時に走らないよう、CommunicationBaseViewController共通の排他制御に参加する
        guard beginHandlingCommunicationEnd() else { return }
        invalidDataRevertTimer?.invalidate()
        invalidDataRevertTimer = nil
        currentInvalidDataAlert = nil

        let finishAndPop: () -> Void = { [weak self] in
            guard let self else { return }
            // Step 2: Bluetooth通信切断処理（PS設計書 6.4）
            BluetoothManager.shared.disconnect {
                // Step 3: 1つ前の画面へ遷移
                self.navigationController?.popViewController(animated: true)
            }
        }

        // 表示中のダイアログ（受信中／データ受信完了／不正データ等）があれば先に閉じてから、
        // Step 1: 受信終了要求の通知〜受信終了完了の待機 を行う
        if let presented = presentedViewController {
            presented.dismiss(animated: true) {
                BluetoothManager.shared.stopReceiving(completion: finishAndPop)
            }
        } else {
            BluetoothManager.shared.stopReceiving(completion: finishAndPop)
        }
    }

    /// 現在表示中のダイアログを（あれば）閉じてから、新しいメッセージダイアログを表示する共通ヘルパー。
    /// 「データ受信完了」ダイアログ（SS設計書 6.5 No.2、OKボタンあり）の表示に使用する。
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

// MARK: - BluetoothManagerReceiveDelegate（PS設計書 6.6「データ受信処理」の結果通知）

extension ReceiveViewController: BluetoothManagerReceiveDelegate {
    /// 受信検出あり（PS設計書 6.6「チェックOK時：コール元に『受信検出あり』を通知」）。
    /// SS設計書 6.2 No.2の一連の流れを実行する：
    ///   データ受信処理に「受信終了要求」を通知→「受信終了完了」を受けた後、
    ///   小項目（送信元ID／送信先ID／データ）に受信データを表示し「受信再開」ボタンを表示、
    ///   その状態のまま「データ受信完了」をダイアログ表示する（OKボタンあり。SS設計書 6.5 No.2）。
    func bluetoothManager(_ manager: BluetoothManager, didDetect payload: Payload) {
        invalidDataRevertTimer?.invalidate()
        invalidDataRevertTimer = nil
        currentInvalidDataAlert = nil

        // 「受信終了要求」通知〜「受信終了完了」待機（PS設計書 6.6）
        BluetoothManager.shared.stopReceiving { [weak self] in
            guard let self else { return }
            // 背面の表示を先に更新してから、SS設計書 6.5 No.2の「表示された時点で背面は
            // データ表示・『受信再開』ボタン表示済みの状態」を満たした上でダイアログを表示する
            self.sourceIdValueLabel.text = payload.sourceID
            self.destIdValueLabel.text = payload.destinationID
            self.dataValueLabel.text = payload.inputDataText
            self.resumeButton.isHidden = false

            self.presentDetectionAlert(message: "データ受信完了", okHandler: {})
        }
    }

    /// 受信検出なし（PS設計書 6.6「チェックNG時：コール元に『受信検出なし』を通知」）。
    /// SS設計書 6.2 No.3／6.5 No.3に対応：
    ///   「データを受信しましたが、不正データでした。」をOKボタン付きで表示する。
    ///   OKタップ、または5秒間無操作のいずれでも「受信中」表示に戻す
    ///   （データ受信処理自体はOK操作の有無に関わらずバックグラウンドで継続している）。
    func bluetoothManagerDidFailToDetect(_ manager: BluetoothManager) {
        let showInvalidDataAlert: () -> Void = { [weak self] in
            guard let self else { return }
            let alert = UIAlertController(
                title: nil, message: "データを受信しましたが、不正データでした。", preferredStyle: .alert
            )
            // OKタップ時：SS設計書 6.5 No.3「OKボタン操作時は受信中表示に戻す」
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                self?.invalidDataRevertTimer?.invalidate()
                self?.invalidDataRevertTimer = nil
                self?.presentReceivingAlert()
            })
            self.currentInvalidDataAlert = alert
            self.present(alert, animated: true)

            // SS設計書 6.5 No.3「OKボタンが操作されないまま5秒経過した場合、受信中表示に戻す」
            self.invalidDataRevertTimer?.invalidate()
            self.invalidDataRevertTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self, weak alert] _ in
                // 5秒待つ間に別の受信結果（受信検出ありなど）で表示済みダイアログが
                // 切り替わっていないかを確認してから戻す（表示中の内容が別イベントで
                // 既に切り替わっていた場合は何もしない）
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
}

// MARK: - CommunicationBaseViewController（SS設計書 6.6「予期しない切断時の仕様」）

extension ReceiveViewController {
    /// 予期しない切断検知時、表示中のダイアログ用タイマー・参照をクリアする
    /// （不正データダイアログの5秒タイマーが後から誤発火しないようにするため）。
    /// ダイアログ表示〜画面遷移までの共通フローは`CommunicationBaseViewController`側が行う。
    override func willHandleUnexpectedDisconnect() {
        invalidDataRevertTimer?.invalidate()
        invalidDataRevertTimer = nil
        currentInvalidDataAlert = nil
    }
}
