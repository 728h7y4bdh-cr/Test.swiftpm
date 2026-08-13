import Foundation

/// 通信状態（ステータス）の保持・遷移を管理するクラス（PS設計書 3章「ステータス（状態）仕様」）。
/// PS設計書 3.3「状態遷移図」の各状態遷移は、`BluetoothManager`の処理の中から
/// このクラスの`update(_:)`／`resetToIdle()`を呼び出すことで反映される。
/// アプリ全体で単一のステータスを共有するため、シングルトン（`shared`）として提供する。
final class StatusManager {
    static let shared = StatusManager()

    private init() {}

    /// 現在のステータス。PS設計書 3.1「状態一覧」のいずれかの値を保持する
    private(set) var status: AppStatus = .idle

    /// ステータスを更新する。PS設計書 3.2「状態遷移契機一覧」に記載の各契機で呼び出される
    /// （例：通信開始のデータ送信時に`.connecting`、送信完了時に`.waitingToSend`など）。
    func update(_ newStatus: AppStatus) {
        status = newStatus
    }

    /// ステータスをアイドルへ戻す。
    /// PS設計書 3.2 No.1「アプリ起動時」（6.1 初期化処理）と
    /// No.2「Bluetooth通信切断処理完了後」（6.4 通信切断処理）の2箇所から呼び出される。
    func resetToIdle() {
        status = .idle
    }
}
