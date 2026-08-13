import CoreBluetooth

/// Bluetooth使用許可確認（SS設計書 4.1）
///
/// `CBCentralManager.authorization` はOSが記憶している許可状態をそのまま返すため、
/// 一度「許可」が確定した後の起動では、このクラスは新たなシステムダイアログを
/// 表示させることなく即座に許可済みと判定できる。
final class BluetoothAuthorizationChecker: NSObject, CBCentralManagerDelegate {
    private var manager: CBCentralManager?
    private var completion: ((Bool) -> Void)?

    /// 許可状態を確認する。未確定の場合はCBCentralManagerを生成し、
    /// OS標準の許可確認ダイアログ（許可／不許可の2択）を表示させる。
    func check(completion: @escaping (Bool) -> Void) {
        switch CBCentralManager.authorization {
        case .allowedAlways:
            completion(true)
        case .denied, .restricted:
            completion(false)
        case .notDetermined:
            self.completion = completion
            manager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: false])
        @unknown default:
            completion(false)
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard let completion else { return }

        switch central.state {
        case .unauthorized:
            self.completion = nil
            manager = nil
            completion(false)
        case .poweredOn, .poweredOff, .resetting, .unsupported:
            // 状態が確定 = 許可ダイアログへの回答が確定したタイミング
            self.completion = nil
            let granted = CBCentralManager.authorization == .allowedAlways
            manager = nil
            completion(granted)
        case .unknown:
            break
        @unknown default:
            break
        }
    }
}
