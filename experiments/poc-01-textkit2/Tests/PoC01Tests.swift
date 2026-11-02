import AppKit
import XCTest

final class PoC01Tests: XCTestCase {
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
