import Foundation

/// ペイロードのエンコード／デコード（PS設計書 4章）
enum PayloadCodec {

    /// Payload → 18byteのバイナリに変換する
    static func encode(_ payload: Payload) -> Data {
        var data = Data()
        data.append(payload.payloadType.rawValue)
        data.append(payload.communicationType.rawValue)
        data.append(asciiBytes(from: payload.sourceID, length: Payload.idLength))
        data.append(asciiBytes(from: payload.destinationID, length: Payload.idLength))
        data.append(fixedLength(payload.inputData, length: Payload.inputDataLength))
        return data
    }

    /// 18byteのバイナリ → Payload に変換する（フォーマット不正時はnil）
    static func decode(_ data: Data) -> Payload? {
        guard data.count == Payload.totalLength else { return nil }
        let bytes = [UInt8](data)

        guard let type = PayloadType(rawValue: bytes[0]) else { return nil }
        guard let commType = CommunicationType(rawValue: bytes[1]) else { return nil }

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

    /// 入力データ領域（10byte）：全て0x20で埋める（通信開始・待受用）
    static var blankInputData: Data {
        Data(repeating: 0x20, count: Payload.inputDataLength)
    }

    /// 入力データ領域（10byte）：文字列をASCII変換し、残りを0x20で埋める（データ送信用）
    static func paddedInputData(from text: String) -> Data {
        fixedLength(text.data(using: .ascii) ?? Data(), length: Payload.inputDataLength)
    }

    // MARK: - Private

    private static func asciiBytes(from id: String, length: Int) -> Data {
        fixedLength(id.data(using: .ascii) ?? Data(), length: length)
    }

    private static func asciiString(from bytes: [UInt8]) -> String {
        String(bytes: bytes, encoding: .ascii) ?? ""
    }

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
