import CoreBluetooth
import Foundation

/// Peripheral役としてのBluetooth接続を担う「役割」レイヤー（PS設計書 5.1「Central/Peripheral役割」）。
///
/// アドバタイズ・GATTサーバーの提供・Write受信・Notify送信という「通信の運び方」だけに
/// 責任を持つ。待受開始ハンドシェイク（PS設計書 6.3「Bluetooth待受開始処理」）やデータ受信チェック
/// （6.6「データ受信処理」）が「受信した内容に何を期待するか」というプロトコル上の意味は一切知らない。
/// 上位の`ListenStartHandshake`／`DataReceiver`が、このセッションが提供するクロージャベースの
/// 窓口を介して実際のペイロードを送受信する。
final class BluetoothPeripheralSession: NSObject {
    /// アドバタイズ開始（GATTサービス公開）が完了した
    var onReady: (() -> Void)?
    /// Central側からRequest/Dataキャラクタリスティックへの書き込みを受信した
    var onWriteReceived: ((Data) -> Void)?
    /// アドバタイズ開始前の失敗、または接続確立後の予期しない切断（購読解除）
    var onFailure: (() -> Void)?

    private var peripheralManager: CBPeripheralManager?
    private var requestCharacteristic: CBMutableCharacteristic?
    private var responseCharacteristic: CBMutableCharacteristic?
    private var advertiseRequested = false
    private var pendingNotifyData: Data?
    private var pendingNotifyCompletion: ((Bool) -> Void)?

    /// PS設計書 5.2「GATTプロファイル定義」の2キャラクタリスティックを公開し、アドバタイズを開始する
    func start() {
        advertiseRequested = true
        if peripheralManager == nil {
            peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        }
        beginAdvertisingIfReady()
    }

    /// Responseキャラクタリスティックへ1回Notify送信する。送信キューが詰まっている場合は
    /// 内部で保持しておき、`peripheralManagerIsReady(toUpdateSubscribers:)`で自動的に再送する
    /// （PS設計書 6.3「送信失敗の場合は…異常終了を通知する」に対する再試行の実装上の補足）。
    func notify(_ data: Data, completion: @escaping (Bool) -> Void) {
        guard let peripheralManager, let responseCharacteristic else {
            completion(false)
            return
        }
        if peripheralManager.updateValue(data, for: responseCharacteristic, onSubscribedCentrals: nil) {
            completion(true)
        } else {
            pendingNotifyData = data
            pendingNotifyCompletion = completion
        }
    }

    /// アドバタイズ停止・GATTサービス取り下げ。PS設計書 6.4「Bluetooth通信切断処理」の実行時に、
    /// Coordinator（BluetoothManager）から呼ばれる。
    func teardown() {
        onReady = nil
        onWriteReceived = nil
        onFailure = nil
        advertiseRequested = false
        pendingNotifyData = nil
        pendingNotifyCompletion = nil
        if let peripheralManager, peripheralManager.isAdvertising {
            peripheralManager.stopAdvertising()
        }
        peripheralManager?.removeAllServices()
        requestCharacteristic = nil
        responseCharacteristic = nil
    }

    private func beginAdvertisingIfReady() {
        guard advertiseRequested, let peripheralManager, peripheralManager.state == .poweredOn else { return }
        advertiseRequested = false

        // Request/Dataキャラクタリスティック：Central→Peripheralへの書き込み専用（PS設計書 5.2）
        let requestChar = CBMutableCharacteristic(
            type: BluetoothGATT.requestCharacteristicUUID,
            properties: [.write],
            value: nil,
            permissions: [.writeable]
        )
        // Responseキャラクタリスティック：Peripheral→Centralへの通知専用（PS設計書 5.2）
        let responseChar = CBMutableCharacteristic(
            type: BluetoothGATT.responseCharacteristicUUID,
            properties: [.notify],
            value: nil,
            permissions: [.readable]
        )
        requestCharacteristic = requestChar
        responseCharacteristic = responseChar

        let service = CBMutableService(type: BluetoothGATT.serviceUUID, primary: true)
        service.characteristics = [requestChar, responseChar]
        peripheralManager.add(service)
    }
}

// MARK: - CBPeripheralManagerDelegate

extension BluetoothPeripheralSession: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            beginAdvertisingIfReady()
        case .poweredOff, .unauthorized, .unsupported:
            if advertiseRequested || requestCharacteristic != nil {
                onFailure?()
            }
        default:
            break
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard error == nil else {
            onFailure?()
            return
        }
        peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [BluetoothGATT.serviceUUID]])
        onReady?()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        onFailure?()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            // 受信したことのACKは内容の正当性に関わらず常に返し、内容の解釈は上位（onWriteReceived）に委ねる
            peripheral.respond(to: request, withResult: .success)
            if let data = request.value {
                onWriteReceived?(data)
            }
        }
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        guard let data = pendingNotifyData, let completion = pendingNotifyCompletion else { return }
        pendingNotifyData = nil
        pendingNotifyCompletion = nil
        notify(data, completion: completion)
    }
}
