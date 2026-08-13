import CoreBluetooth

/// GATTプロファイル定義（PS設計書 5.2）
enum BluetoothGATT {
    /// サービスUUID
    static let serviceUUID = CBUUID(string: "00000000-0000-0000-0000-000000000001")
    /// Request/Dataキャラクタリスティック（Central→Peripheral, Write）
    static let requestCharacteristicUUID = CBUUID(string: "00000000-0000-0000-0000-000000000002")
    /// Responseキャラクタリスティック（Peripheral→Central, Notify）
    static let responseCharacteristicUUID = CBUUID(string: "00000000-0000-0000-0000-000000000003")
}
