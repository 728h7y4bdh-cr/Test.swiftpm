import Foundation

/// 通信状態のステータス（PS設計書 3.1 状態一覧）
enum AppStatus {
    case idle
    case connecting
    case waitingToSend
    case listening
    case waitingToReceive
    case receiveStopping
    case sending
}
