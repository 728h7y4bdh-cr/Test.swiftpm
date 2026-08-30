import Foundation

/// Bluetooth通信切断処理（PS設計書 6.4、要件定義書 7章）。
///
/// 役割レイヤーのセッション（`BluetoothCentralSession`／`BluetoothPeripheralSession`）の破棄と、
/// 状態遷移（アイドルへの復帰）のみに責任を持つ。通信開始処理（`ConnectionStartHandshake`）・
/// 待受開始処理（`ListenStartHandshake`）と同様、要件定義書上の1つの「処理」に対応する
/// 専用の機能単位として切り出してある（癒着防止：どのセッションを保持しているかの判断や、
/// 呼び出し元が持つ参照自体のクリアは、調停役＝`BluetoothManager`側の責務とする）。
enum Disconnector {
    /// Central役の切断完了（`centralSession.teardown(completion:)`）を待つ際の安全用タイムアウト。
    /// Core Bluetoothから切断完了の通知が万一届かなかった場合に、待ち続けないようにする。
    private static let centralTeardownTimeoutInterval: TimeInterval = 5.0

    /// 渡されたセッションのうちnilでない方をteardownし、アイドル状態へ遷移する。
    ///
    /// Peripheral役の切断（`stopAdvertising`／`removeAllServices`）には、Core Bluetooth側に
    /// 完了を通知するAPIが無いため、これまで通り同期的に行い即座に完了したものとして扱う。
    /// Central役の切断（`cancelPeripheralConnection`）は非同期の要求でしかないため、
    /// 接続中の相手がいた場合は実際の切断完了通知（またはタイムアウト）を待ってから`completion`を呼ぶ。
    /// `completion`は`BluetoothManager.isDisconnecting`の解除にのみ使う内部的な完了通知であり、
    /// 画面遷移等のUI側の完了とは別（呼び出し元は待たずに進める）。
    static func disconnect(
        centralSession: BluetoothCentralSession?,
        peripheralSession: BluetoothPeripheralSession?,
        completion: @escaping () -> Void
    ) {
        peripheralSession?.teardown()
        // PS設計書 3.2 No.2：切断処理完了後にアイドルへ遷移
        StatusManager.shared.apply(.disconnectCompleted)

        guard let centralSession else {
            completion()
            return
        }

        var didComplete = false
        let completeOnce = {
            guard !didComplete else { return }
            didComplete = true
            completion()
        }

        let timeoutTimer = Timer.scheduledTimer(withTimeInterval: centralTeardownTimeoutInterval, repeats: false) { _ in
            completeOnce()
        }
        centralSession.teardown {
            timeoutTimer.invalidate()
            completeOnce()
        }
    }
}
