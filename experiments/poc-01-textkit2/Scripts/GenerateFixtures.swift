import Foundation
import CryptoKit

// Usage: xcrun swift Scripts/GenerateFixtures.swift OUTPUT_DIRECTORY [REFERENCE_MANIFEST]
// No randomness, clock values, locale-dependent formatting or external packages.
struct Entry: Codable, Equatable {
    let name: String
    let bytes: Int
    let lines: Int // LF separators + 1 for a nonempty unterminated final line. CRLF counts once.
    let lineEndings: String
    let sha256: String
}
struct Manifest: Codable, Equatable {
    let generatorVersion: Int
    let sizeConvention: String
    let lineConvention: String
    let files: [Entry]
}

func document(size: Int, ending: String) -> Data {
    let lines = ["# TextKit 2 baseline", "", "Кириллица и Latin; emoji 👩🏽‍💻 🐈; decomposed e\u{301}.",
                 "\"straight quotes\" 'single' -- --- ... `code` **bold** [link](https://example.test)",
                 "Short paragraph.", "", String(repeating: "Long Кириллица 👩🏽‍💻 e\u{301} ", count: 80), ""]
    let block = Data((lines.joined(separator: ending) + ending).utf8)
    var result = Data(capacity: size)
    while result.count + block.count <= size { result.append(block) }
    let tailBytes = size - result.count
    if tailBytes >= ending.utf8.count {
        result.append(Data(repeating: 0x78, count: tailBytes - ending.utf8.count))
        result.append(Data(ending.utf8))
    } else {
        result.append(Data(repeating: 0x78, count: tailBytes))
    }
    return result
}

do {
    guard (2...3).contains(CommandLine.arguments.count) else {
        throw NSError(domain: "GenerateFixtures", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Usage: xcrun swift Scripts/GenerateFixtures.swift OUTPUT_DIRECTORY [REFERENCE_MANIFEST]"])
    }
    let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var entries: [Entry] = []
    func write(_ name: String, data: Data, endings: String) throws {
        guard String(data: data, encoding: .utf8) != nil else { fatalError("Generator produced invalid UTF-8") }
        let url = directory.appendingPathComponent(name)
        // Never overwrite existing, possibly manually modified files.
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw NSError(domain: "GenerateFixtures", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Output already exists: \(url.path). Choose a fresh directory."])
        }
        try data.write(to: url, options: .withoutOverwriting)
        let separators = data.reduce(0) { $0 + ($1 == 0x0A ? 1 : 0) }
        let count = separators + ((!data.isEmpty && data.last != 0x0A) ? 1 : 0)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        entries.append(Entry(name: name, bytes: data.count, lines: count, lineEndings: endings, sha256: hash))
    }
    for size in [100_000, 1_000_000, 5_000_000] {
        for (label, ending) in [("lf", "\n"), ("crlf", "\r\n")] {
            try write("baseline-\(size)-\(label).md", data: document(size: size, ending: ending), endings: label.uppercased())
        }
    }
    let prefix = Data("Long line Кириллица 👩🏽‍💻 e\u{301} ".utf8)
    var stress = prefix
    stress.append(Data(repeating: 0x78, count: 1_000_000 - stress.count))
    try write("stress-1000000-no-newline.txt", data: stress, endings: "none")
    let manifest = Manifest(generatorVersion: 1, sizeConvention: "decimal UTF-8 bytes",
                            lineConvention: "LF count plus one for a nonempty unterminated final line; CRLF counts once",
                            files: entries)
    if CommandLine.arguments.count == 3 {
        let reference = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
        guard manifest == reference else {
            throw NSError(domain: "GenerateFixtures", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Generated data does not match the reference manifest"])
        }
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    var json = try encoder.encode(manifest)
    json.append(0x0A)
    try json.write(to: directory.appendingPathComponent("manifest.json"), options: .withoutOverwriting)
    print("Generated \(entries.count) fixtures; manifest: \(directory.appendingPathComponent("manifest.json").path)")
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
