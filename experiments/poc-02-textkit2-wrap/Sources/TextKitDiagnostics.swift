import AppKit
import OSLog

@MainActor
final class TextKitDiagnostics: NSObject {
    private static let logger = Logger(subsystem: "local.md-editor.PoC02", category: "TextKit")
    private weak var textView: NSTextView?
    // Only held during construction, before the identity of the tested view is known.
    private var earlyEvents: [(ObjectIdentifier, String)] = []
    private(set) var fallbackCount = 0
    private(set) var checkpointCount = 0
    var wrapMode: WordWrapMode = .on
    var isTextKit2: Bool { textView?.textLayoutManager != nil }

    override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(willSwitch(_:)),
                           name: NSTextView.willSwitchToNSLayoutManagerNotification, object: nil)
        center.addObserver(self, selector: #selector(didSwitch(_:)),
                           name: NSTextView.didSwitchToNSLayoutManagerNotification, object: nil)
    }

    func attach(to view: NSTextView) {
        textView = view
        for (identity, phase) in earlyEvents where identity == ObjectIdentifier(view) {
            logFallback(phase)
        }
        earlyEvents.removeAll()
        checkpoint("created")
    }

    @objc private func willSwitch(_ notification: Notification) { observe(notification, phase: "will-switch") }
    @objc private func didSwitch(_ notification: Notification) { observe(notification, phase: "did-switch") }

    private func observe(_ notification: Notification, phase: String) {
        guard let source = notification.object as? NSTextView else { return }
        guard let textView else {
            earlyEvents.append((ObjectIdentifier(source), phase))
            return
        }
        guard source === textView else { return }
        logFallback(phase)
        // Do not inspect layout objects in the middle of a transition.
    }

    private func logFallback(_ phase: String) {
        if phase == "did-switch" { fallbackCount += 1 }
        Self.logger.error("FALLBACK phase=\(phase, privacy: .public) wrap=\(self.wrapMode.rawValue, privacy: .public) uptime=\(ProcessInfo.processInfo.systemUptime) count=\(self.fallbackCount)")
    }

    func checkpoint(_ stage: String) {
        checkpointCount += 1
        let active = isTextKit2
        Self.logger.info("checkpoint=\(stage, privacy: .public) wrap=\(self.wrapMode.rawValue, privacy: .public) textKit2=\(active) fallbackCount=\(self.fallbackCount) uptime=\(ProcessInfo.processInfo.systemUptime)")
        if !active { Self.logger.error("TextKit 2 absent at checkpoint=\(stage, privacy: .public)") }
    }

    func logLoad(_ loaded: LoadedText, installMilliseconds: Double) {
        Self.logger.info("load bytes=\(loaded.byteCount) read_ms=\(loaded.readMilliseconds) decode_ms=\(loaded.decodeMilliseconds) install_ms=\(installMilliseconds); interactive readiness NOT measured")
    }

    func logGeometry(_ view: NSTextView, scroll: NSScrollView) {
        let description = "wrap=\(wrapMode.rawValue) viewport=\(scroll.contentView.bounds.size) view=\(view.frame.size) container=\(String(describing: view.textContainer?.size)) widthTracksView=\(view.textContainer?.widthTracksTextView == true) horizontalResizable=\(view.isHorizontallyResizable) horizontalScroller=\(scroll.hasHorizontalScroller) font=\(String(describing: view.font)) inset=\(view.textContainerInset) scale=\(view.window?.backingScaleFactor ?? 0)"
        Self.logger.info("geometry \(description, privacy: .public)")
    }

    func logPreparedCursor(_ offset: Int) {
        Self.logger.info("PREPARATION cursorUTF16=\(offset) wrap=\(self.wrapMode.rawValue, privacy: .public); excludes layout settling and is NOT an edit-latency measurement")
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}
