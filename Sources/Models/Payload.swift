import Foundation

/// 送信種別（PS設計書 4.2）
enum PayloadType: UInt8 {
    case request = 0x29
    case response = 0x92
}

/// 通信種別（PS設計書 4.3）
enum CommunicationType: UInt8 {
    case connection = 0x01
    case data = 0x02
}

/// 通信ペイロード（PS設計書 4.1 全18byte固定長）
struct Payload {
    static let totalLength = 18
    static let idLength = 3
    static let inputDataLength = 10

    let payloadType: PayloadType
    let communicationType: CommunicationType
    let sourceID: String
    let destinationID: String
    let inputData: Data

    /// 入力データを末尾の0x20(半角スペース)を除いた文字列として取得する
    var inputDataText: String {
        let text = String(data: inputData, encoding: .ascii) ?? ""
        return text.trimmingCharacters(in: CharacterSet(charactersIn: " "))
    }
}
