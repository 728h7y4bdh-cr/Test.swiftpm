import Foundation

/// 通信状態のステータス（PS設計書 3.1「状態一覧」に対応する7状態）。
/// 各状態への遷移契機はPS設計書 3.2「状態遷移契機一覧」、
/// 遷移の全体像はPS設計書 3.3「状態遷移図」を参照。
enum AppStatus {
    /// アイドル（PS設計書 3.1 No.1）：アプリ起動時、および通信切断処理完了後の状態
    case idle
    /// Bluetooth通信開始処理中（PS設計書 3.1 No.2）：通信開始のデータ送信〜応答待ちの間の状態
    case connecting
    /// データ送信待ち中（PS設計書 3.1 No.3）：通信開始処理の正常終了後、またはデータ送信完了後の状態
    case waitingToSend
    /// Bluetooth通信待受処理中（PS設計書 3.1 No.4）：30秒間のデータ待受を行っている間の状態
    case listening
    /// データ受信待ち中（PS設計書 3.1 No.5）：待受処理の正常終了後、または「受信再開」タップ後の状態
    case waitingToReceive
    /// データ受信停止中（PS設計書 3.1 No.6）：受信終了要求を検出し、受信終了完了を通知するタイミングの状態
    case receiveStopping
    /// データ送信処理中（PS設計書 3.1 No.7）：データ送信処理の実行中（送信ボタン押下〜送信完了/失敗まで）の状態
    case sending
}
