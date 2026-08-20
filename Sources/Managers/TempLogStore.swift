import Foundation

// TEMP-LOG: 「接続中」スタック問題の調査用コード。Mac/Xcodeが無い環境でも、
// iPad・iPhone実機の画面上で直接ログを確認できるようにするための一時的な仕組み。
// 原因判明後、このファイルごと削除すること（呼び出し元も含め `grep -rn "TEMP-LOG"` で洗い出す）。
enum TempLogStore { // TEMP-LOG
    private static let startTime = Date() // TEMP-LOG
    private static var lines: [String] = [] // TEMP-LOG

    /// 行が追加されるたびに呼ばれる。画面側（ConnectionViewController）が表示更新に使う。
    static var onAppend: (() -> Void)? // TEMP-LOG

    static func append(_ message: String) { // TEMP-LOG
        let elapsed = Date().timeIntervalSince(startTime) // TEMP-LOG
        lines.append(String(format: "[%.1fs] %@", elapsed, message)) // TEMP-LOG
        onAppend?() // TEMP-LOG
    }

    static var text: String { lines.joined(separator: "\n") } // TEMP-LOG
}
