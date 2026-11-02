import Foundation

enum WordWrapMode: String {
    case on = "ON"
    case off = "OFF"

    // A finite experiment bound, not the document-view frame width. The fixed stress fixture
    // is almost entirely ASCII x: ~8.7 million points at the unchanged 14 pt monospaced font.
    // 2^24 points leaves substantial headroom. Actual layout/end accessibility still require W-02.
    static let unwrappedContainerWidth: CGFloat = 16_777_216

    static func midpointUTF16(in text: String) -> Int {
        let target = text.utf16.count / 2
        var offset = 0
        // Swift Character boundaries include CRLF, combining sequences, flags and ZWJ emoji.
        // A linear scan is preparation only, never part of the per-keystroke path.
        for character in text {
            let next = offset + String(character).utf16.count
            if next > target { break }
            offset = next
        }
        return offset
    }
}
