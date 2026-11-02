import Foundation

struct LoadedText {
    let text: String
    let byteCount: Int
    let readMilliseconds: Double
    let decodeMilliseconds: Double
}

enum FileLoader {
    enum LoadError: LocalizedError {
        case invalidUTF8
        var errorDescription: String? { "The selected file is not valid UTF-8. The current editor text was kept." }
    }

    static func load(_ url: URL) throws -> LoadedText {
        let start = DispatchTime.now().uptimeNanoseconds
        let data = try Data(contentsOf: url)
        let readEnd = DispatchTime.now().uptimeNanoseconds
        guard let text = String(data: data, encoding: .utf8) else { throw LoadError.invalidUTF8 }
        let decodeEnd = DispatchTime.now().uptimeNanoseconds
        return LoadedText(text: text, byteCount: data.count,
                          readMilliseconds: milliseconds(start, readEnd),
                          decodeMilliseconds: milliseconds(readEnd, decodeEnd))
    }

    static func milliseconds(_ start: UInt64, _ end: UInt64) -> Double {
        Double(end - start) / 1_000_000
    }
}
