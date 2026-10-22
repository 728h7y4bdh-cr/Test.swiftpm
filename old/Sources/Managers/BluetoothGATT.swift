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
    /// Central側からPeripheral側へデータを送るためのキャラクタリスティックであり、以下の2つの送信に使用する。
    ///   - Bluetooth接続時の通信開始要求
    ///   - データ送信画面から送信するデータ
    /// Central→Peripheralへの送信はこの1特性に集約されるため、方向ごとに1特性ずつの
    /// 片方向2特性構成で全シナリオを表現できる。仕様根拠：PS設計書「前提・設計上の補足事項」
    static let requestCharacteristicUUID = CBUUID(string: "00000000-0000-0000-0000-000000000002")

    /// Responseキャラクタリスティック（Peripheral→Central, Notify）。
    /// Peripheral側からCentral側へ応答を返すためのキャラクタリスティックであり、以下の2つの応答に使用する。
    ///   - Bluetooth接続時の通信開始要求に対する応答
    ///   - データ受信時に送信元へ返す応答
    /// 仕様根拠：PS設計書「前提・設計上の補足事項」
    static let responseCharacteristicUUID = CBUUID(string: "00000000-0000-0000-0000-000000000003")
}
