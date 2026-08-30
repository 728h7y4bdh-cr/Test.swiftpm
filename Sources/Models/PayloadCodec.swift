import Foundation

/// ペイロードのエンコード／デコード（PS設計書 4章「通信フォーマット仕様」）。
/// `Payload`構造体と、実際にBluetoothで送受信する18byteの`Data`とを相互変換する。
enum PayloadCodec {

    /// Payload → 18byteのバイナリに変換する（PS設計書 4.1「ペイロード構成」の並び順でバイト列を組み立てる）。
    /// オフセット 0:送信種別(1byte) / 1:通信種別(1byte) / 2〜4:送信元ID(3byte) / 5〜7:送信先ID(3byte) / 8〜17:入力データ(10byte)
    static func encode(_ payload: Payload) -> Data {
        var data = Data()
        data.append(payload.payloadType.rawValue)
        data.append(payload.communicationType.rawValue)
        // PS設計書 4.4「ID変換仕様」：3桁の数値文字列をASCII(0x30〜0x39)にエンコードし3byteにする
        data.append(asciiBytes(from: payload.sourceID, length: Payload.idLength))
        data.append(asciiBytes(from: payload.destinationID, length: Payload.idLength))
        // 入力データは呼び出し側で既に用途別（4.5節）に整形済みの10byteを渡す想定だが、
        // 念のためここでも10byteに揃える
        data.append(fixedLength(payload.inputData, length: Payload.inputDataLength))
        return data
    }

    /// 18byteのバイナリ → Payload に変換する（PS設計書 4.1のオフセット定義に基づき分解する）。
    /// 長さが18byteでない、または送信種別／通信種別が規定のコード（4.2・4.3節）にない場合はフォーマット不正としてnilを返す。
    static func decode(_ data: Data) -> Payload? {
        guard data.count == Payload.totalLength else { return nil }
        let bytes = [UInt8](data)

        // PS設計書 4.2「送信種別コード」：0x29(要求) / 0x92(応答) 以外は不正データ
        guard let type = PayloadType(rawValue: bytes[0]) else { return nil }
        // PS設計書 4.3「通信種別コード」：0x01(通信開始・待受) / 0x02(データ送受信) 以外は不正データ
        guard let commType = CommunicationType(rawValue: bytes[1]) else { return nil }

        // オフセット 2〜4:送信元ID(3byte)、5〜7:送信先ID(3byte)、8〜17:入力データ(10byte)（PS設計書 4.1）
        let sourceID = asciiString(from: Array(bytes[2..<5]))
        let destinationID = asciiString(from: Array(bytes[5..<8]))
        let inputData = Data(bytes[8..<18])

        return Payload(
            payloadType: type,
            communicationType: commType,
            sourceID: sourceID,
            destinationID: destinationID,
            inputData: inputData
        )
    }

    /// 入力データ領域（10byte）を全て0x20で埋めたデータ。
    /// PS設計書 4.5「入力データ領域の用途別内容」：通信開始要求／応答（通信種別0x01）で使用する
    /// （要件定義書 5章・6章：「入力データ（10byte）：0x20で埋める」に対応）。
    static var blankInputData: Data {
        Data(repeating: 0x20, count: Payload.inputDataLength)
    }

    /// 文字列をASCII変換し、10byteになるよう残りを0x20で埋めたデータ。
    /// PS設計書 4.5：データ送信（通信種別0x02）で、画面で選択された"YAMA"／"KAWA"を変換する際に使用する
    /// （要件定義書 8章「データ送信処理」：「空きバイトは0x20埋め」に対応）。
    static func paddedInputData(from text: String) -> Data {
        fixedLength(text.data(using: .ascii) ?? Data(), length: Payload.inputDataLength)
    }

    // MARK: - Private

    /// 自端末ID／接続先IDの3桁数値文字列をASCII変換し、指定byte数に揃える（PS設計書 4.4「ID変換仕様」）
    private static func asciiBytes(from id: String, length: Int) -> Data {
        fixedLength(id.data(using: .ascii) ?? Data(), length: length)
    }

    /// バイト列をASCII文字列に変換する（IDのデコード、PS設計書 4.4の逆変換）
    private static func asciiString(from bytes: [UInt8]) -> String {
        String(bytes: bytes, encoding: .ascii) ?? ""
    }

    /// 指定byte数に合わせて切り詰め／0x20パディングする共通処理。
    /// ID領域（3byte）・入力データ領域（10byte）双方の固定長化に使用する。
    private static func fixedLength(_ data: Data, length: Int) -> Data {
        var result = data
        if result.count > length {
            result = result.prefix(length)
        }
        while result.count < length {
            result.append(0x20)
        }
        return result
    }
}
