import UIKit

/// Bluetooth通信に関わる画面（Bluetooth接続画面／データ送信画面／データ受信画面）が
/// 共通で継承する基底クラス（要件定義書12.2「予期しない切断」）。
///
/// 各画面で重複しがちな次の2つの共通処理をここに集約し、画面が増えるたびに
/// 同じロジックがコピーされていくことを防ぐ。
///   1. OKボタン付きの単純なメッセージダイアログ表示（`presentAlert(message:)`）
///   2. Bluetooth接続が予期せず切断された際の共通フロー
///      （表示中ダイアログを閉じる→「Bluetooth通信が切断されました。再接続してください」を表示→
///        OKタップで前の画面へ戻る。SS設計書5.6／6.6「予期しない切断時の仕様」）
///
/// 画面固有の追加の中断処理（例：データ送信画面が送信中フラグを解除する等）が必要な場合は、
/// `willHandleUnexpectedDisconnect()`をオーバーライドする。
/// 「戻る」ボタン等、予期しない切断の処理と同時に走ってほしくない画面固有の処理がある場合は、
/// `beginHandlingCommunicationEnd()`を使って同じ排他制御に参加できる。
class CommunicationBaseViewController: UIViewController, BluetoothManagerConnectionDelegate {
    /// 予期しない切断の処理・「戻る」ボタン処理など、通信終了に関わる処理が二重に走らないようにする排他フラグ。
    private var isHandlingCommunicationEnd = false

    /// OKボタン付きの単純なメッセージダイアログを表示する共通ヘルパー。
    func presentAlert(message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    /// 通信終了に関わる処理（予期しない切断検知、または「戻る」ボタン等の画面固有の処理）を
    /// これから開始してよいかを判定する。開始してよい場合は排他フラグを立ててtrueを返す。
    /// 既に処理中の場合はfalseを返すので、呼び出し元はそれ以上何もしないこと。
    @discardableResult
    func beginHandlingCommunicationEnd() -> Bool {
        guard !isHandlingCommunicationEnd else { return false }
        isHandlingCommunicationEnd = true
        return true
    }

    /// 予期しない切断検知時、画面固有の中断処理が必要な場合はサブクラスでオーバーライドする。
    /// 既定では何もしない。
    func willHandleUnexpectedDisconnect() {}

    func bluetoothManagerDidDisconnectUnexpectedly(_ manager: BluetoothManager) {
        guard beginHandlingCommunicationEnd() else { return }
        willHandleUnexpectedDisconnect()

        let showAlert: () -> Void = { [weak self] in
            guard let self else { return }
            let alert = UIAlertController(
                title: nil, message: "Bluetooth通信が切断されました。再接続してください", preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                self?.navigationController?.popViewController(animated: true)
            })
            self.present(alert, animated: true)
        }

        if let presented = presentedViewController {
            presented.dismiss(animated: true, completion: showAlert)
        } else {
            showAlert()
        }
    }
}
