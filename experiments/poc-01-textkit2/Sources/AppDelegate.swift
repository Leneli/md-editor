import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var editor: EditorWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit PoC01", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        addMenu("PoC01", submenu: appMenu, to: menu)

        let fileMenu = NSMenu(title: "File")
        let open = fileMenu.addItem(withTitle: "Open…", action: #selector(openFile(_:)), keyEquivalent: "o")
        open.target = self
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        addMenu("File", submenu: fileMenu, to: menu)

        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", "undo:", "z"), ("Redo", "redo:", "Z"),
                                     ("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
                                     ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: NSSelectorFromString(action), keyEquivalent: key)
        }
        addMenu("Edit", submenu: editMenu, to: menu)
        NSApp.mainMenu = menu

        editor = EditorWindowController()
        editor?.showWindow(nil)
        editor?.window?.makeFirstResponder(editor?.textView)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func addMenu(_ title: String, submenu: NSMenu, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }

    @objc private func openFile(_ sender: Any?) { editor?.openFile(sender) }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
