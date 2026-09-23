import CoreBluetooth

/// GATTプロファイル定義（PS設計書「GATTプロファイル定義」）。
/// Core Bluetoothで独自に定義するService／Characteristicの識別子（UUID）をまとめたもの。
/// UUIDはデバッグ時に見分けやすいよう末尾のみを変えた単純な値としている。
enum BluetoothGATT {
    /// サービスUUID。Peripheral役（待受開始側）がこのサービスをアドバタイズし、
    /// Central役（接続開始側）はこのサービスUUIDを指定してスキャンする
    /// （PS設計書「Bluetooth通信開始処理（Central側）」「Bluetooth待受開始処理（Peripheral側）」）。
    static let serviceUUID = CBUUID(string: "00000000-0000-0000-0000-000000000001")

    /// Request/Dataキャラクタリスティック（Central→Peripheral, Write）。
    /// 双方向で送信が発生するのはBluetooth通信開始処理・Bluetooth待受開始処理のハンドシェイクのみであり、
    /// データ受信処理側からの応答送信は不要なため、Write／Notifyの片方向2特性構成で全シナリオを表現できる。
    /// このキャラクタリスティックは、Bluetooth通信開始要求とデータ送信の両方でCentralからPeripheralへの
    /// 書き込みに使用する（Properties: Write）。仕様根拠：PS設計書「前提・設計上の補足事項」
    static let requestCharacteristicUUID = CBUUID(string: "00000000-0000-0000-0000-000000000002")

    /// Responseキャラクタリスティック（Peripheral→Central, Notify）。
    /// Bluetooth通信開始応答（待受側からの応答）でのみ使用する（Properties: Notify）。
    /// データ受信処理では応答送信を行わないため未使用。仕様根拠：PS設計書「前提・設計上の補足事項」
    static let responseCharacteristicUUID = CBUUID(string: "00000000-0000-0000-0000-000000000003")
}
