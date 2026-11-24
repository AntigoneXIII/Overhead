import AppKit

if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
    MainActor.assumeIsolated { Snapshot.run(into: URL(fileURLWithPath: CommandLine.arguments[i + 1])) }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // lives in the notch, no Dock icon
app.run()

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notch: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Notchzip.cleanUpOldZips()
        notch = NotchController(store: BayStore.shared)
    }
}
