import AppKit
import XCTest
import CryptoKit

final class PoC02Tests: XCTestCase {
    @MainActor
    private func editor() -> EditorWindowController {
        _ = NSApplication.shared
        return EditorWindowController()
    }

    @MainActor
    func testTextKit2AndRepeatedDiagnostics() {
        let controller = editor()
        defer { controller.close() }
        XCTAssertTrue(controller.diagnostics.isTextKit2)
        for _ in 0..<100 { controller.diagnostics.checkpoint("test") }
        XCTAssertTrue(controller.diagnostics.isTextKit2)
        XCTAssertEqual(controller.diagnostics.fallbackCount, 0)
    }

    @MainActor
    func testLiteralMarkdownInputAndDisabledSubstitutions() {
        let controller = editor()
        defer { controller.close() }
        let view = controller.textView
        XCTAssertFalse(view.isAutomaticQuoteSubstitutionEnabled)
        XCTAssertFalse(view.isAutomaticDashSubstitutionEnabled)
        XCTAssertFalse(view.isAutomaticSpellingCorrectionEnabled)
        XCTAssertFalse(view.isAutomaticTextReplacementEnabled)
        XCTAssertFalse(view.isAutomaticTextCompletionEnabled)
        XCTAssertFalse(view.isAutomaticLinkDetectionEnabled)
        XCTAssertFalse(view.isAutomaticDataDetectionEnabled)
        XCTAssertFalse(view.smartInsertDeleteEnabled)
        let literal = "\"double\" 'single' -- --- ... (c) teh -> <- != <= >= `code` **bold** _em_ ~~s~~ # []() ![x](url)\nПривет 👩🏽‍💻 e\u{301}\n"
        for character in literal {
            view.insertText(String(character), replacementRange: view.selectedRange())
        }
        XCTAssertEqual(view.string, literal)
        // Pump the run loop to include deferred edit diagnostics; this is not a timing benchmark.
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        XCTAssertGreaterThan(controller.diagnostics.checkpointCount, 2)
        XCTAssertTrue(controller.diagnostics.isTextKit2)
        XCTAssertEqual(controller.diagnostics.fallbackCount, 0)
    }

    @MainActor
    func testUndoRedoSelectionDeletionAndPrivatePasteboard() throws {
        let controller = editor()
        defer { controller.close() }
        let view = controller.textView
        let undo = try XCTUnwrap(view.undoManager)
        undo.groupsByEvent = false
        func insert(_ text: String) {
            undo.beginUndoGrouping()
            view.insertText(text, replacementRange: view.selectedRange())
            view.breakUndoCoalescing()
            undo.endUndoGrouping()
        }
        insert("Привет 👩🏽‍💻 e\u{301}")
        let first = view.string
        insert(" -- `Markdown`")
        let second = view.string
        let checkpoints = controller.diagnostics.checkpointCount
        undo.undo()
        XCTAssertEqual(view.string, first)
        XCTAssertTrue(controller.diagnostics.isTextKit2)
        undo.redo()
        XCTAssertEqual(view.string, second)
        XCTAssertGreaterThanOrEqual(controller.diagnostics.checkpointCount, checkpoints + 2)

        view.setSelectedRange(NSRange(location: 0, length: (view.string as NSString).length))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertEqual(view.selectedRange().length, (second as NSString).length)
        XCTAssertTrue(view.writeSelection(to: pasteboard, types: view.writablePasteboardTypes),
                      "Advertised writable types: \(view.writablePasteboardTypes)")
        XCTAssertEqual(pasteboard.string(forType: .string), second)
        undo.beginUndoGrouping()
        view.delete(nil)
        view.breakUndoCoalescing()
        undo.endUndoGrouping()
        XCTAssertEqual(view.string, "")
        undo.beginUndoGrouping()
        XCTAssertTrue(view.readSelection(from: pasteboard))
        view.breakUndoCoalescing()
        undo.endUndoGrouping()
        XCTAssertEqual(view.string, second)
        XCTAssertTrue(controller.diagnostics.isTextKit2)
        XCTAssertEqual(controller.diagnostics.fallbackCount, 0)
    }

    @MainActor
    func testLoadingErrorsUndoResetAndSourceIntegrity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("unicode.md")
        let original = Data("# Привет\r\n\"quote\" -- 👩🏽‍💻 e\u{301}\r\n".utf8)
        try original.write(to: url)
        let controller = editor()
        defer { controller.close() }
        controller.textView.insertText("old edits", replacementRange: NSRange(location: 0, length: 0))
        try controller.load(url)
        XCTAssertEqual(controller.textView.string, String(data: original, encoding: .utf8))
        XCTAssertFalse(try XCTUnwrap(controller.textView.undoManager).canUndo)
        XCTAssertTrue(controller.diagnostics.isTextKit2)
        controller.textView.insertText("new edits", replacementRange: NSRange(location: 0, length: 0))
        let edited = controller.textView.string
        XCTAssertEqual(try Data(contentsOf: url), original)

        let invalid = directory.appendingPathComponent("invalid.txt")
        try Data([0xFF, 0xFE, 0x80]).write(to: invalid)
        XCTAssertThrowsError(try controller.load(invalid))
        XCTAssertEqual(controller.textView.string, edited)
        XCTAssertThrowsError(try controller.load(directory.appendingPathComponent("missing.md")))
        XCTAssertEqual(controller.textView.string, edited)
        try controller.load(url)
        XCTAssertFalse(try XCTUnwrap(controller.textView.undoManager).canUndo)
        XCTAssertEqual(controller.diagnostics.fallbackCount, 0)
        controller.close()
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
}

extension PoC02Tests {
    @MainActor
    func testInitialONMatchesPoC01Configuration() throws {
        let controller = editor()
        defer { controller.close() }
        let view = controller.textView
        let container = try XCTUnwrap(view.textContainer)
        XCTAssertEqual(controller.wrapMode, .on)
        XCTAssertEqual(controller.scrollView.frame.size, NSSize(width: 900, height: 650))
        XCTAssertEqual(view.font, .monospacedSystemFont(ofSize: 14, weight: .regular))
        XCTAssertEqual(view.textContainerInset, NSSize(width: 12, height: 12))
        XCTAssertTrue(container.widthTracksTextView)
        XCTAssertEqual(container.size.width, controller.scrollView.contentSize.width)
        XCTAssertEqual(container.size.height, CGFloat.greatestFiniteMagnitude)
        XCTAssertFalse(view.isHorizontallyResizable)
        XCTAssertTrue(view.isVerticallyResizable)
        XCTAssertEqual(view.autoresizingMask, [.width])
        XCTAssertTrue(controller.scrollView.hasVerticalScroller)
        XCTAssertFalse(controller.scrollView.hasHorizontalScroller)
        XCTAssertTrue(controller.scrollView.autohidesScrollers)
        XCTAssertTrue(controller.diagnostics.isTextKit2)
    }

    @MainActor
    private func smallDocumentLines(_ controller: EditorWindowController) throws -> [NSTextLineFragment] {
        // Intentionally prohibited for the 1 MB fixture: full layout is only for this tiny test.
        guard (controller.textView.string as NSString).length <= 4096 else {
            XCTFail("Full layout test is limited to <= 4096 UTF-16 units")
            return []
        }
        let manager = try XCTUnwrap(controller.textView.textLayoutManager)
        let content = try XCTUnwrap(manager.textContentManager)
        manager.ensureLayout(for: content.documentRange)
        var lines: [NSTextLineFragment] = []
        manager.enumerateTextLayoutFragments(from: content.documentRange.location, options: []) { fragment in
            lines.append(contentsOf: fragment.textLineFragments)
            return true
        }
        return lines
    }

    @MainActor
    func testActualSmallLineLayoutAndHorizontalReachability() throws {
        let controller = editor()
        defer { controller.close() }
        let view = controller.textView
        let text = String(repeating: "x", count: 1000)
        view.string = text
        XCTAssertGreaterThan(try smallDocumentLines(controller).count, 1)
        controller.setWrapMode(.off)
        let lines = try smallDocumentLines(controller)
        XCTAssertEqual(lines.count, 1, "OFF must actually lay out one line")
        let line = try XCTUnwrap(lines.first)
        XCTAssertEqual(line.characterRange.length, 1000, "No clipping/truncation of the test line")
        // Extrapolate the fixed ASCII tail with generous allowance for the short Unicode prefix.
        // This is a width-budget check, not full layout of the megabyte fixture.
        XCTAssertLessThan(line.typographicBounds.width * 1000 + 4096, WordWrapMode.unwrappedContainerWidth)
        XCTAssertGreaterThan(line.typographicBounds.width, controller.scrollView.contentSize.width)
        for offset in [0, 500, 1000] {
            let range = NSRange(location: offset, length: 0)
            view.setSelectedRange(range)
            view.scrollRangeToVisible(range)
            let screenRect = view.firstRect(forCharacterRange: range, actualRange: nil)
            let windowRect = try XCTUnwrap(controller.window).convertFromScreen(screenRect)
            let caretRect = view.convert(windowRect, from: nil)
            XCTAssertTrue(view.visibleRect.insetBy(dx: -2, dy: -2).intersects(caretRect.insetBy(dx: -1, dy: -1)),
                          "Caret at \(offset) is outside viewport: \(caretRect), visible: \(view.visibleRect)")
            view.insertText("Q", replacementRange: range)
            view.setSelectedRange(NSRange(location: offset, length: 1))
            view.delete(nil)
            XCTAssertEqual(view.string, text)
        }
        // TextKit 2 grows the document view lazily as the viewport visits the line.
        XCTAssertGreaterThanOrEqual(view.frame.width, line.typographicBounds.maxX)
        XCTAssertLessThan(view.frame.width, WordWrapMode.unwrappedContainerWidth)
        controller.setWrapMode(.on)
        XCTAssertGreaterThan(try smallDocumentLines(controller).count, 1)
        controller.window?.setContentSize(NSSize(width: 500, height: 650))
        let narrow = try smallDocumentLines(controller).count
        controller.window?.setContentSize(NSSize(width: 900, height: 650))
        XCTAssertGreaterThan(narrow, try smallDocumentLines(controller).count)
        view.string = "First\nSecond\nThird"
        controller.setWrapMode(.off)
        XCTAssertEqual(try smallDocumentLines(controller).count, 3, "OFF must preserve explicit line breaks")
        XCTAssertTrue(controller.diagnostics.isTextKit2)
        XCTAssertEqual(controller.diagnostics.fallbackCount, 0)
    }

    @MainActor
    func testSwitchAndPreparationPreserveTextSelectionAndUndo() throws {
        let controller = editor()
        defer { controller.close() }
        let view = controller.textView
        let undo = try XCTUnwrap(view.undoManager)
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        view.insertText("Привет 👩🏽‍💻 e\u{301} Markdown", replacementRange: NSRange(location: 0, length: 0))
        view.breakUndoCoalescing()
        undo.endUndoGrouping()
        let text = view.string
        view.setSelectedRange(NSRange(location: 1, length: 2))
        let selection = view.selectedRange()
        for mode in [WordWrapMode.off, .on, .off] {
            controller.setWrapMode(mode)
            XCTAssertEqual(view.string, text)
            XCTAssertEqual(view.selectedRange(), selection)
            XCTAssertTrue(undo.canUndo)
            XCTAssertTrue(controller.diagnostics.isTextKit2)
        }
        let offset = controller.prepareMidpoint()
        XCTAssertEqual(offset, view.selectedRange().location)
        XCTAssertEqual(controller.preparedOffset, offset)
        XCTAssertTrue(controller.window?.title.contains("UTF-16 offset: \(offset)") == true)
        XCTAssertEqual(view.string, text)
        undo.undo()
        XCTAssertEqual(view.string, "")
        undo.redo()
        XCTAssertEqual(view.string, text)
        XCTAssertTrue(controller.diagnostics.isTextKit2)
        XCTAssertEqual(controller.diagnostics.fallbackCount, 0)
    }

    func testMidpointUsesExtendedUnicodeBoundary() {
        for text in ["", "a", "👩🏽‍💻", "ae\u{301}b", "🇩🇪", "a\r\nb", "abc👨‍👩‍👧‍👦def"] {
            let offset = WordWrapMode.midpointUTF16(in: text)
            let validOffsets = Set(text.indices.map { $0.utf16Offset(in: text) } + [text.utf16.count])
            XCTAssertTrue(validOffsets.contains(offset), "Not a Character boundary: \(text), \(offset)")
            XCTAssertLessThanOrEqual(offset, text.utf16.count / 2)
        }
    }

    func testExistingOneMegabyteFixtures() throws {
        // Read-only checks; no NSTextView/full layout and no generation here.
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("poc-01-textkit2/TestData/generated")
        let names = ["stress-1000000-no-newline.txt", "baseline-1000000-lf.md"]
        let hashes = ["9d015a4e07935c0b72e50de855be5d9e8bb650a41ff2d2855f248eb61cf3e5ec",
                      "c92a871e2be0de511887ff0e9de46b7e5e10dc55b9e1a0d016b7586359cb7b39"]
        for (name, expected) in zip(names, hashes) {
            let url = directory.appendingPathComponent(name)
            let bytes = try Data(contentsOf: url)
            XCTAssertEqual(bytes.count, 1_000_000)
            let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(hash, expected)
            let loaded = try FileLoader.load(url)
            XCTAssertEqual(Data(loaded.text.utf8), bytes)
            if name.hasPrefix("stress") { XCTAssertFalse(loaded.text.contains("\n")) }
            else { XCTAssertTrue(loaded.text.contains("\n")) }
        }
    }
}
