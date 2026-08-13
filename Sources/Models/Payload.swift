import Foundation

/// 送信種別（PS設計書 4.2「送信種別コード」）。
/// 要件定義書 3章「通信仕様」の「送信種別(1byte)：要求時に0x29、応答時に0x92」に対応する。
enum PayloadType: UInt8 {
    /// 要求（0x29固定）
    case request = 0x29
    /// 応答（0x92固定）
    case response = 0x92
}

/// 通信種別（PS設計書 4.3「通信種別コード」）。
/// 要件定義書 3章「通信仕様」の「通信種別(1byte)：通信開始・待受は0x01。データ送受信は0x02」に対応する。
enum CommunicationType: UInt8 {
    /// Bluetooth通信開始・待受（0x01固定）
    case connection = 0x01
    /// データ送受信（0x02固定）
    case data = 0x02
}

/// 通信ペイロード（PS設計書 4.1「ペイロード構成」全18byte固定長）。
/// 要件定義書 3章「通信仕様」で定義されたBluetooth通信フォーマットのSwift側モデル。
///
/// バイト構成（PS設計書 4.1）：
///   offset 0    : 送信種別   1byte
///   offset 1    : 通信種別   1byte
///   offset 2〜4 : 送信元ID   3byte
///   offset 5〜7 : 送信先ID   3byte
///   offset 8〜17: 入力データ 10byte
/// 実際のバイト列との相互変換は`PayloadCodec`が担当する。
struct Payload {
    /// ペイロード全体の長さ（PS設計書 4.1：全18byte固定長）
    static let totalLength = 18
    /// 送信元ID・送信先ID それぞれの長さ（PS設計書 4.1：各3byte）
    static let idLength = 3
    /// 入力データ領域の長さ（PS設計書 4.1：10byte）
    static let inputDataLength = 10

    /// 送信種別（要求0x29／応答0x92）
    let payloadType: PayloadType
    /// 通信種別（通信開始・待受0x01／データ送受信0x02）
    let communicationType: CommunicationType
    /// 送信元ID（3桁の数値文字列。PS設計書 4.4「ID変換仕様」でASCII変換される前の文字列表現）
    let sourceID: String
    /// 送信先ID（3桁の数値文字列。PS設計書 4.4「ID変換仕様」でASCII変換される前の文字列表現）
    let destinationID: String
    /// 入力データ（10byte）。用途別の内容はPS設計書 4.5「入力データ領域の用途別内容」を参照
    let inputData: Data

    /// 入力データ領域を、末尾の0x20（半角スペース）パディングを取り除いた文字列として取得する。
    /// データ受信処理（PS設計書 9章 / 6.6）で受信データが"YAMA"／"KAWA"かどうかを判定する際などに使用する。
    var inputDataText: String {
        let text = String(data: inputData, encoding: .ascii) ?? ""
        return text.trimmingCharacters(in: CharacterSet(charactersIn: " "))
    }
}
