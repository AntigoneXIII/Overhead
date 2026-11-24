import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
app.run()

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var status: StatusController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        status = StatusController(store: BayStore.shared)
    }
}
