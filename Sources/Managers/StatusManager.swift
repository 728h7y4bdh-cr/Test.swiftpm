import Foundation

/// 通信状態の保持・遷移を管理する（PS設計書 3章）
final class StatusManager {
    static let shared = StatusManager()

    private init() {}

    private(set) var status: AppStatus = .idle

    func update(_ newStatus: AppStatus) {
        status = newStatus
    }

    /// 初期化処理（PS設計書 6.1）／通信切断処理完了後（PS設計書 6.4）に呼び出す
    func resetToIdle() {
        status = .idle
    }
}
