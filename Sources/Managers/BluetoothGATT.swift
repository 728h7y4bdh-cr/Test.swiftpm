import CoreBluetooth

/// GATTプロファイル定義（PS設計書 5.2「GATTプロファイル定義」）。
/// Core Bluetoothで独自に定義するService／Characteristicの識別子（UUID）をまとめたもの。
/// UUIDはデバッグ時に見分けやすいよう末尾のみを変えた単純な値としている（PS設計書 5.2 表）。
enum BluetoothGATT {
    /// サービスUUID。Peripheral役（待受開始側）がこのサービスをアドバタイズし、
    /// Central役（接続開始側）はこのサービスUUIDを指定してスキャンする（PS設計書 6.2・6.3）。
    static let serviceUUID = CBUUID(string: "00000000-0000-0000-0000-000000000001")

    /// Request/Dataキャラクタリスティック（Central→Peripheral, Write）。
    /// PS設計書 0.1 No.4「GATT通信方向」：Bluetooth通信開始要求（6.2）とデータ送信（6.5）の
    /// 双方でCentralからPeripheralへの書き込みに使用する（Properties: Write）。
    static let requestCharacteristicUUID = CBUUID(string: "00000000-0000-0000-0000-000000000002")

    /// Responseキャラクタリスティック（Peripheral→Central, Notify）。
    /// PS設計書 0.1 No.4：Bluetooth通信開始応答（6.3の待受側からの応答）でのみ使用する
    /// （Properties: Notify）。データ受信処理（6.6）では応答送信を行わないため未使用。
    static let responseCharacteristicUUID = CBUUID(string: "00000000-0000-0000-0000-000000000003")
}
