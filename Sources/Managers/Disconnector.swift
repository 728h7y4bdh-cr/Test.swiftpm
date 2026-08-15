import Foundation

/// Bluetooth通信切断処理（PS設計書 6.4、要件定義書 7章）。
///
/// 役割レイヤーのセッション（`BluetoothCentralSession`／`BluetoothPeripheralSession`）の破棄と、
/// 状態遷移（アイドルへの復帰）のみに責任を持つ。通信開始処理（`ConnectionStartHandshake`）・
/// 待受開始処理（`ListenStartHandshake`）と同様、要件定義書上の1つの「処理」に対応する
/// 専用の機能単位として切り出してある（癒着防止：どのセッションを保持しているかの判断や、
/// 呼び出し元が持つ参照自体のクリアは、調停役＝`BluetoothManager`側の責務とする）。
enum Disconnector {
    /// 渡されたセッションのうちnilでない方をteardownし、アイドル状態へ遷移する。
    static func disconnect(
        centralSession: BluetoothCentralSession?,
        peripheralSession: BluetoothPeripheralSession?
    ) {
        centralSession?.teardown()
        peripheralSession?.teardown()
        // PS設計書 3.2 No.2：切断処理完了後にアイドルへ遷移
        StatusManager.shared.apply(.disconnectCompleted)
    }
}
