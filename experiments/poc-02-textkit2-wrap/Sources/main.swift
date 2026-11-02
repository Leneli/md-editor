import AppKit

// A macOS executable enters on the main thread; keep the AppKit entry point actor-isolated.
MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    // NSApplication's delegate is weak; retain it for the entire event loop in Release too.
    withExtendedLifetime(delegate) { application.run() }
}
