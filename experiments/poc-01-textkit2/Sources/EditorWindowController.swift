import AppKit
import UniformTypeIdentifiers

@MainActor
final class EditorWindowController: NSWindowController, NSTextViewDelegate {
    let diagnostics: TextKitDiagnostics
    let textView: NSTextView
    private var editCheckpoint: Timer?

    init() {
        diagnostics = TextKitDiagnostics() // Observe transitions before constructing the view.
        textView = NSTextView(usingTextLayoutManager: true)
        super.init(window: nil)
        diagnostics.attach(to: textView)
        configureEditor()

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 900, height: 650))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = textView
        textView.frame = scroll.contentView.bounds
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scroll.contentSize.width,
                                                       height: CGFloat.greatestFiniteMagnitude)
        let window = NSWindow(contentRect: scroll.frame,
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "PoC-01 — Memory only (no saving)"
        window.contentView = scroll
        window.center()
        self.window = window
        textView.delegate = self
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(didUndo(_:)), name: .NSUndoManagerDidUndoChange, object: nil)
        center.addObserver(self, selector: #selector(didRedo(_:)), name: .NSUndoManagerDidRedoChange, object: nil)
        diagnostics.checkpoint("configured")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func configureEditor() {
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
    }

    @objc func openFile(_ sender: Any?) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "txt")!, UTType(filenameExtension: "md")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Read UTF-8 into memory. Current edits will be discarded; source files are never saved."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                try self.load(url)
            } catch {
                // File access/decoding failures are separate from TextKit observations.
                let alert = NSAlert()
                alert.messageText = "File loading failed (not a TextKit result)"
                alert.informativeText = error.localizedDescription
                alert.beginSheetModal(for: window)
            }
        }
    }

    func load(_ url: URL) throws {
        let loaded = try FileLoader.load(url) // Do not replace editor contents until decoding succeeds.
        editCheckpoint?.invalidate()
        textView.breakUndoCoalescing()
        let start = DispatchTime.now().uptimeNanoseconds
        textView.string = loaded.text
        let end = DispatchTime.now().uptimeNanoseconds
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollToBeginningOfDocument(nil)
        textView.undoManager?.removeAllActions()
        diagnostics.checkpoint("loaded")
        diagnostics.logLoad(loaded, installMilliseconds: FileLoader.milliseconds(start, end))
    }

    func textDidChange(_ notification: Notification) {
        // At most one checkpoint per 0.5 seconds of continuous editing, including a final trailing check.
        guard editCheckpoint == nil || editCheckpoint?.isValid == false else { return }
        editCheckpoint = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            // Scheduled on the main run loop by this main-actor delegate.
            MainActor.assumeIsolated { self?.diagnostics.checkpoint("edited") }
        }
    }

    @objc private func didUndo(_ notification: Notification) { checkUndo(notification, stage: "undo") }
    @objc private func didRedo(_ notification: Notification) { checkUndo(notification, stage: "redo") }
    private func checkUndo(_ notification: Notification, stage: String) {
        guard let manager = notification.object as? UndoManager, manager === textView.undoManager else { return }
        diagnostics.checkpoint(stage)
    }

    deinit {
        editCheckpoint?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}
