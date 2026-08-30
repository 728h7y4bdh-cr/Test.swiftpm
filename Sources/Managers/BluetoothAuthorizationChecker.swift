import CoreBluetooth

/// Bluetooth使用許可確認（SS設計書 4.1「Bluetooth使用許可確認」）。
///
/// SS設計書 4.1 No.1「画面遷移時、選択肢は「許可」「不許可」の2つのみのダイアログを表示する」は、
/// OS標準の許可確認ダイアログ（CBCentralManagerを生成すると`.notDetermined`の場合にiOSが自動表示する）
/// を利用しており、本クラス自身がダイアログを描画するわけではない。
///
/// `CBCentralManager.authorization` はOSが記憶している許可状態をそのまま返すため、
/// 一度「許可」が確定した後の起動では、新たなシステムダイアログを表示させることなく
/// 即座に許可済みと判定できる（SS設計書 4.1 No.4「2回目以降の起動時は再表示しない」に対応）。
final class BluetoothAuthorizationChecker: NSObject, CBCentralManagerDelegate {
    private var manager: CBCentralManager?
    private var completion: ((Bool) -> Void)?

    /// 許可状態を確認する。呼び出し元（ConnectionViewController）は
    /// completionの引数がtrueなら入力項目・ボタンを表示し（SS設計書 4.1 No.2「許可」時の処理）、
    /// falseなら固定メッセージのダイアログを表示する（SS設計書 4.1 No.3「不許可」時の処理）。
    func check(completion: @escaping (Bool) -> Void) {
        switch CBCentralManager.authorization {
        case .allowedAlways:
            // 過去に許可済み：SS設計書 4.1 No.4 のとおり、ダイアログを出さず即座にtrueを返す
            completion(true)
        case .denied, .restricted:
            completion(false)
        case .notDetermined:
            // まだ未確定：CBCentralManagerを生成することで、OS標準の許可確認ダイアログ
            // （選択肢は「許可」「不許可」の2つのみ、SS設計書 4.1 No.1）が表示される。
            // 電源OFF時のシステムアラートは許可確認とは無関係のため抑止する（ShowPowerAlertKey: false）。
            self.completion = completion
            manager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: false])
        @unknown default:
            completion(false)
        }
    }

    /// ダイアログへの回答結果（状態確定）を検知するデリゲートメソッド。
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard let completion else { return }

        switch central.state {
        case .unauthorized:
            // 「不許可」が選択された
            self.completion = nil
            manager = nil
            completion(false)
        case .poweredOn, .poweredOff, .resetting, .unsupported:
            // 状態が確定 = 許可ダイアログへの回答が確定したタイミング。
            // 「許可」が選択されていれば`.allowedAlways`になっているはずなのでそれを最終判定とする。
            self.completion = nil
            let granted = CBCentralManager.authorization == .allowedAlways
            manager = nil
            completion(granted)
        case .unknown:
            // まだ状態確定前（ダイアログ表示中など）：何もせず回答を待つ
            break
        @unknown default:
            break
        }
    }
}
