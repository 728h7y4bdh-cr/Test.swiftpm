import CoreBluetooth
import Foundation

/// Central役としてのBluetooth接続を担う「役割」レイヤー（PS設計書 5.1「Central/Peripheral役割」）。
///
/// このクラスはCore Bluetoothの接続確立・GATT探索・Write/Notifyの送受信という
/// 「通信の運び方」だけに責任を持つ。BLE自体の通信処理はCore Bluetoothライブラリが行うため、
/// このクラスはそのAPIを呼び出すだけであり、通信開始ハンドシェイク（PS設計書 6.2「Bluetooth通信開始処理」）や
/// データ送信（6.5「データ送信処理」）が「いつ・何を送るか」というアプリケーション独自の通信内容は一切知らない
/// （ペイロードのバイトフォーマットにも依存しない）。上位の`ConnectionStartHandshake`／`DataSender`が、
/// このセッションが提供するクロージャベースの窓口を介して実際のペイロードを送受信する。
///
/// 責務をこのレイヤーだけに閉じることで、GATT定義や接続手順そのものが変わっても、
/// 影響範囲はこのファイルだけに収まる（機能単位クラス側への影響はない）。
final class BluetoothCentralSession: NSObject {
    /// 接続・GATT探索・Notify購読が完了し、書き込み可能になった
    var onReady: (() -> Void)?
    /// Responseキャラクタリスティックの値が更新された（相手からの応答をNotifyで受信した）
    var onResponseReceived: ((Data) -> Void)?
    /// 準備完了前の失敗、または準備完了後の予期しない切断
    var onFailure: (() -> Void)?

    private var centralManager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var requestCharacteristic: CBCharacteristic?
    private var responseCharacteristic: CBCharacteristic?
    private var isScanRequested = false
    private var pendingWriteCompletion: ((Bool) -> Void)?
    /// `teardown(completion:)`で、実際のCore Bluetooth側の切断完了を待っている間の完了通知先
    private var pendingTeardownCompletion: (() -> Void)?

    /// PS設計書 6.2「相手端末を発見する」：BluetoothGATT.serviceUUIDをアドバタイズしている
    /// 端末（＝待受中の相手）をスキャンし、発見次第接続する。
    func start() {
        isScanRequested = true
        if centralManager == nil {
            // CBCentralManagerの生成が、必要に応じてOS標準のBluetooth使用許可ダイアログの契機にもなる
            centralManager = CBCentralManager(delegate: self, queue: nil)
        }
        beginScanIfReady()
    }

    /// 送信可能な最大バイト数（PS設計書 5.3「送信サイズ確認方針」の判定に使用）
    var maximumWriteLength: Int {
        peripheral?.maximumWriteValueLength(for: .withResponse) ?? 0
    }

    /// Request/Dataキャラクタリスティックへ1回書き込む
    func write(_ data: Data, completion: @escaping (Bool) -> Void) {
        guard let peripheral, let requestCharacteristic else {
            completion(false)
            return
        }
        pendingWriteCompletion = completion
        peripheral.writeValue(data, for: requestCharacteristic, type: .withResponse)
    }

    /// 接続の破棄・状態のクリア。PS設計書 6.4「Bluetooth通信切断処理」の実行時に、
    /// Coordinator（BluetoothManager）から呼ばれる。
    ///
    /// `cancelPeripheralConnection`はCore Bluetoothへの切断要求であり、呼んだ時点では
    /// 実際の切断が完了していない（完了は`didDisconnectPeripheral`／`didFailToConnect`で
    /// 後から非同期に通知される）。そのため`completion`は、接続中の相手が存在した場合のみ
    /// その通知を待ってから呼び、存在しない場合（そもそも接続確立前など）は即座に呼ぶ。
    func teardown(completion: @escaping () -> Void) {
        onReady = nil
        onResponseReceived = nil
        onFailure = nil
        isScanRequested = false
        pendingWriteCompletion = nil
        centralManager?.stopScan()
        if let peripheral {
            pendingTeardownCompletion = completion
            centralManager?.cancelPeripheralConnection(peripheral)
        } else {
            completion()
        }
        peripheral = nil
        requestCharacteristic = nil
        responseCharacteristic = nil
    }

    private func beginScanIfReady() {
        TempLogStore.append("beginScanIfReady: isScanRequested=\(isScanRequested), state=\(String(describing: centralManager?.state.rawValue))") // TEMP-LOG
        guard isScanRequested, let centralManager, centralManager.state == .poweredOn else { return }
        isScanRequested = false
        // BluetoothGATT.serviceUUIDをアドバタイズしている端末（＝待受中の相手）のみをスキャン対象にする
        centralManager.scanForPeripherals(withServices: [BluetoothGATT.serviceUUID], options: nil)
        TempLogStore.append("scanForPeripherals called") // TEMP-LOG
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothCentralSession: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        TempLogStore.append("centralManagerDidUpdateState: \(central.state.rawValue)") // TEMP-LOG
        switch central.state {
        case .poweredOn:
            beginScanIfReady()
        case .poweredOff, .unauthorized, .unsupported:
            if isScanRequested || peripheral != nil {
                onFailure?()
            }
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        TempLogStore.append("didDiscover peripheral: \(peripheral.identifier), rssi=\(RSSI)") // TEMP-LOG
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        TempLogStore.append("didConnect peripheral") // TEMP-LOG
        peripheral.discoverServices([BluetoothGATT.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        TempLogStore.append("didFailToConnect: \(String(describing: error)) -> onFailure") // TEMP-LOG
        onFailure?()
        completeTeardownIfNeeded()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        TempLogStore.append("didDisconnectPeripheral: \(String(describing: error)) -> onFailure") // TEMP-LOG
        self.peripheral = nil
        requestCharacteristic = nil
        responseCharacteristic = nil
        onFailure?()
        completeTeardownIfNeeded()
    }

    /// `teardown(completion:)`が切断完了を待っていれば、その完了通知を呼ぶ
    private func completeTeardownIfNeeded() {
        let completion = pendingTeardownCompletion
        pendingTeardownCompletion = nil
        completion?()
    }
}

// MARK: - CBPeripheralDelegate（相手端末＝Peripheral役の端末に対する処理）

extension BluetoothCentralSession: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        TempLogStore.append("didDiscoverServices: error=\(String(describing: error)), services=\(String(describing: peripheral.services))") // TEMP-LOG
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == BluetoothGATT.serviceUUID }) else {
            onFailure?()
            return
        }
        peripheral.discoverCharacteristics(
            [BluetoothGATT.requestCharacteristicUUID, BluetoothGATT.responseCharacteristicUUID],
            for: service
        )
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        TempLogStore.append("didDiscoverCharacteristicsFor: error=\(String(describing: error)), characteristics=\(String(describing: service.characteristics))") // TEMP-LOG
        guard error == nil, let characteristics = service.characteristics else {
            onFailure?()
            return
        }
        for characteristic in characteristics {
            if characteristic.uuid == BluetoothGATT.requestCharacteristicUUID {
                requestCharacteristic = characteristic
            } else if characteristic.uuid == BluetoothGATT.responseCharacteristicUUID {
                responseCharacteristic = characteristic
            }
        }
        guard let responseCharacteristic else {
            onFailure?()
            return
        }
        peripheral.setNotifyValue(true, for: responseCharacteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        TempLogStore.append("didUpdateNotificationStateFor: error=\(String(describing: error)), isNotifying=\(characteristic.isNotifying)") // TEMP-LOG
        guard error == nil, characteristic.uuid == BluetoothGATT.responseCharacteristicUUID else {
            onFailure?()
            return
        }
        onReady?()
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        TempLogStore.append("didWriteValueFor: error=\(String(describing: error))") // TEMP-LOG
        let completion = pendingWriteCompletion
        pendingWriteCompletion = nil
        completion?(error == nil)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        TempLogStore.append("didUpdateValueFor: error=\(String(describing: error)), hasData=\(characteristic.value != nil)") // TEMP-LOG
        guard characteristic.uuid == BluetoothGATT.responseCharacteristicUUID, error == nil, let data = characteristic.value else { return }
        onResponseReceived?(data)
    }
}
