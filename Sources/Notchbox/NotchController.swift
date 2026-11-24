import AppKit
import Combine
import SwiftUI

protocol NotchActions: AnyObject {
    func airDrop()
    func share()
    func saveZip()
}

final class NotchModel: ObservableObject {
    static let earWidth: CGFloat = 40

    @Published var isOpen = false
    @Published var pinned = false
    @Published var dropTargeted = false
    @Published var isZipping = false
    @Published var message: String?

    @Published var notchHeight: CGFloat = 24
    @Published var hardwareNotchWidth: CGFloat = 0 // 0 on Macs without a notch
    @Published var closedSize = CGSize(width: 150, height: 24)
    @Published var openSize = CGSize(width: 520, height: 330)

    let shareAnchor = AnchorHolder()
}

final class NotchWindow: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3) // above the menu bar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
    }

    override var canBecomeKey: Bool { true }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns the notch window: a small black notch with the logo when closed,
/// a larger box that grows out of it when opened.
final class NotchController: NSObject, NotchActions, NSSharingServicePickerDelegate {
    private let store: BayStore
    private let model = NotchModel()
    private let window = NotchWindow()
    private var cancellables = Set<AnyCancellable>()
    private var monitors: [Any] = []
    private var outsideMouseDown: NSPoint?
    private var screen: NSScreen?

    /// Room around the open box so its shadow isn't clipped.
    private let shadowMargin = NSSize(width: 30, height: 36)

    init(store: BayStore) {
        self.store = store
        super.init()

        let host = FirstMouseHostingView(rootView: NotchRootView(model: model, store: store, actions: self))
        host.sizingOptions = []
        window.contentView = host

        layout()
        window.orderFrontRegardless()

        model.$isOpen
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] open in self?.openChanged(open) }
            .store(in: &cancellables)

        // Dragging something over the notch opens it.
        model.$dropTargeted
            .filter { $0 }
            .sink { [weak self] _ in
                guard let self, !self.model.isOpen else { return }
                DispatchQueue.main.async { self.model.isOpen = true }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.layout() }
            .store(in: &cancellables)

        installMonitors()
    }

    // MARK: Geometry

    private func layout() {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first
        guard let screen else { return }
        self.screen = screen

        let hasNotch = screen.safeAreaInsets.top > 0
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        let height = hasNotch ? screen.safeAreaInsets.top : max(menuBarHeight, 24)

        var notchWidth: CGFloat = 0
        if hasNotch {
            let left = screen.auxiliaryTopLeftArea?.width ?? 0
            let right = screen.auxiliaryTopRightArea?.width ?? 0
            notchWidth = max(screen.frame.width - left - right, 0)
        }

        model.notchHeight = height
        model.hardwareNotchWidth = notchWidth
        // Closed: the notch plus an "ear" each side for the logo and the item count.
        model.closedSize = CGSize(width: notchWidth + NotchModel.earWidth * 2 + 12 + (hasNotch ? 0 : 50), height: height)
        model.openSize = CGSize(width: max(520, notchWidth + 320), height: height + 310)

        window.setFrame(model.isOpen ? openFrame : closedFrame, display: true)
    }

    private func frame(for size: CGSize, margin: NSSize) -> NSRect {
        guard let screen else { return .zero }
        let w = size.width + margin.width * 2
        let h = size.height + margin.height
        return NSRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - h, width: w, height: h)
    }

    private var closedFrame: NSRect { frame(for: model.closedSize, margin: .zero) }
    private var openFrame: NSRect { frame(for: model.openSize, margin: shadowMargin) }

    private func openChanged(_ open: Bool) {
        if open {
            model.message = nil
            window.setFrame(openFrame, display: true)
            window.makeKey()
        } else {
            // Let the shrink animation finish before the window gets small again.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                guard let self, !self.model.isOpen else { return }
                self.window.setFrame(self.closedFrame, display: true)
            }
        }
    }

    private func close() { model.isOpen = false }

    // MARK: Events

    private func installMonitors() {
        // Close on a plain click elsewhere, but not when the user is dragging
        // (e.g. picking up a file in Finder to bring into the box).
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.outsideMouseDown = NSEvent.mouseLocation
        }) { monitors.append(m) }

        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp], handler: { [weak self] _ in
            guard let self, let start = self.outsideMouseDown else { return }
            self.outsideMouseDown = nil
            let end = NSEvent.mouseLocation
            if hypot(end.x - start.x, end.y - start.y) < 6, self.model.isOpen, !self.model.pinned {
                self.close()
            }
        }) { monitors.append(m) }

        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self, self.model.isOpen, self.window.isKeyWindow else { return event }
            if event.keyCode == 53 { // Esc
                self.close()
                return nil
            }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "v" {
                self.store.importPasteboard(.general)
                return nil
            }
            return event
        }) { monitors.append(m) }
    }

    // MARK: Notchzip sending

    private func withZip(_ then: @escaping (URL) -> Void) {
        let urls = store.allURLs
        guard !urls.isEmpty, !model.isZipping else { return }
        model.isZipping = true
        model.message = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try Notchzip.make(from: urls) }
            DispatchQueue.main.async {
                self.model.isZipping = false
                switch result {
                case .success(let zip): then(zip)
                case .failure(let error): self.model.message = error.localizedDescription
                }
            }
        }
    }

    func airDrop() {
        withZip { zip in
            guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: [zip]) else {
                self.model.message = "AirDrop is off. Turn it on in Control Centre."
                return
            }
            self.close() // the AirDrop window would otherwise sit under the box
            NSApp.activate(ignoringOtherApps: true)
            service.perform(withItems: [zip])
        }
    }

    func share() {
        withZip { zip in
            guard let anchor = self.model.shareAnchor.view else { return }
            let picker = NSSharingServicePicker(items: [zip])
            picker.delegate = self
            picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        }
    }

    func saveZip() {
        withZip { zip in
            do {
                let saved = try Notchzip.saveToDownloads(zip)
                self.model.message = "Saved \(saved.lastPathComponent) to Downloads"
                NSWorkspace.shared.activateFileViewerSelecting([saved])
            } catch {
                self.model.message = "Couldn't save: \(error.localizedDescription)"
            }
        }
    }

    func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        guard service != nil else { return }
        close()
        NSApp.activate(ignoringOtherApps: true)
    }
}
