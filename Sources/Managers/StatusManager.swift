import Foundation

/// 状態遷移の契機（PS設計書 3.2「状態遷移契機一覧」の10行に1:1で対応するイベント）。
///
/// 状態遷移を必ずこのイベント経由で行うことで、「どの契機でどの状態になるか」という
/// ルールをStatusManager 1箇所に集約する（状態遷移の一元管理）。呼び出し元（各処理クラス）は
/// 遷移先の`AppStatus`を直接指定せず、PS設計書3.2の行に対応するイベント名を渡すだけでよい。
enum AppStatusTransitionEvent {
    /// No.1：アプリ起動時
    case appLaunched
    /// No.2：Bluetooth通信切断処理完了後
    case disconnectCompleted
    /// No.3：Bluetooth通信開始処理にて、通信開始のデータ送信時
    case connectionStartRequestSent
    /// No.4：Bluetooth通信開始処理にて、コール元に正常終了を通知する時
    case connectionStartSucceeded
    /// No.5：データ送信処理にて、データ送信完了時
    case dataSendCompleted
    /// No.6：Bluetooth通信待受処理にて、60秒間のデータ待受開始時
    case listenStarted
    /// No.7：Bluetooth通信待受処理にて、コール元に正常終了を通知する時
    case listenSucceeded
    /// No.8：データ受信画面にて、「再開」ボタンをタップしてデータ受信処理を開始した時
    /// （待受成功直後にデータ受信処理を開始する初回のタイミングも、同じ遷移先のためこのイベントを用いる）
    case receivingStarted
    /// No.9：データ受信処理が「受信終了要求」を検出して、コール元に「受信終了完了」を通知する時
    case receiveStopRequested
    /// No.10：データ送信処理にて、データ送信開始時
    case dataSendStarted
}

/// 通信状態（ステータス）の保持・遷移を一元管理するクラス（PS設計書 3章「ステータス（状態）仕様」）。
///
/// 状態遷移のルールはPS設計書 3.2「状態遷移契機一覧」の対応表をそのまま`transitionTable`として
/// 保持し、遷移は必ず`apply(_:)`を経由して行う。`status`への書き込みはこのクラスの外からは
/// できない（`private(set)`）ため、状態遷移ロジックを変更する必要がある場合、変更箇所は
/// 常にこのファイルの`transitionTable`1箇所で完結する。
final class StatusManager {
    static let shared = StatusManager()

    private init() {}

    /// 現在のステータス
    private(set) var status: AppStatus = .idle

    /// PS設計書 3.2「状態遷移契機一覧」の対応表そのもの。
    /// 表の行が増減した場合は、このtransitionTableと`AppStatusTransitionEvent`の
    /// 追加・削除だけで追随できる。
    private static let transitionTable: [AppStatusTransitionEvent: AppStatus] = [
        .appLaunched: .idle,
        .disconnectCompleted: .idle,
        .connectionStartRequestSent: .connecting,
        .connectionStartSucceeded: .waitingToSend,
        .dataSendCompleted: .waitingToSend,
        .listenStarted: .listening,
        .listenSucceeded: .waitingToReceive,
        .receivingStarted: .waitingToReceive,
        .receiveStopRequested: .receiveStopping,
        .dataSendStarted: .sending
    ]

    /// 指定イベントに基づき状態を遷移させる。遷移後の状態を返す。
    @discardableResult
    func apply(_ event: AppStatusTransitionEvent) -> AppStatus {
        guard let newStatus = Self.transitionTable[event] else {
            // transitionTableにイベントの追加漏れがある場合のみ到達する
            CommonUtility.assert(false, "未定義の状態遷移イベント: \(event)")
            return status
        }
        status = newStatus
        return status
    }
}
