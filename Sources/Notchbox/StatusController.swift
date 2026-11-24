import AppKit
import Combine
import SwiftUI

enum PanelMetrics {
    static let size = NSSize(width: 400, height: 360)
    static let cornerRadius: CGFloat = 12
}

final class BoxPanel: NSPanel {
    init(content: NSView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: PanelMetrics.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: PanelMetrics.size))
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = Self.roundedMask(radius: PanelMetrics.cornerRadius)

        content.frame = background.bounds
        content.autoresizingMask = [.width, .height]
        background.addSubview(content)
        contentView = background
    }

    override var canBecomeKey: Bool { true }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// Owns the menu bar logo and the panel that drops down from it.
final class StatusController: NSObject, NSWindowDelegate, BoxActions, NSSharingServicePickerDelegate {
    private let store: BayStore
    private let state = PanelState()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var panel: BoxPanel!
    private var cancellables = Set<AnyCancellable>()
    private var monitors: [Any] = []
    private var outsideMouseDown: NSPoint?

    init(store: BayStore) {
        self.store = store
        super.init()
        panel = BoxPanel(content: NSHostingView(rootView: PanelView(store: store, state: state, actions: self)))

        if let button = statusItem.button {
            button.image = Brand.logo(size: 17)
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePanel)
            button.toolTip = "Notchbox"

            // Dragging something onto the logo opens the box; dropping on it adds the item.
            button.window?.registerForDraggedTypes(
                [.fileURL, .URL, .png, .tiff, .string] +
                NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
            )
            button.window?.delegate = self
        }

        store.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                self?.statusItem.button?.title = items.isEmpty ? "" : " \(items.count)"
            }
            .store(in: &cancellables)

        installMonitors()
    }

    // MARK: Panel

    @objc private func togglePanel() {
        panel.isVisible ? hidePanel() : showPanel()
    }

    private func showPanel() {
        guard !panel.isVisible,
              let button = statusItem.button,
              let buttonWindow = button.window else { return }

        state.message = nil
        let iconRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let size = panel.frame.size
        var x = iconRect.midX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: iconRect.minY - size.height - 6))

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }
        button.highlight(true)
    }

    private func hidePanel() {
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
            self?.statusItem.button?.highlight(false)
        })
    }

    private func installMonitors() {
        // Close on a plain click elsewhere, but not when the user is dragging
        // something (e.g. picking up a file in Finder to bring into the box).
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.outsideMouseDown = NSEvent.mouseLocation
        }) { monitors.append(m) }

        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp], handler: { [weak self] _ in
            guard let self, let start = self.outsideMouseDown else { return }
            self.outsideMouseDown = nil
            let end = NSEvent.mouseLocation
            if hypot(end.x - start.x, end.y - start.y) < 6, !self.state.pinned, !self.panel.frame.contains(end) {
                self.hidePanel()
            }
        }) { monitors.append(m) }

        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            if event.keyCode == 53 { // Esc
                self.hidePanel()
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
        guard !urls.isEmpty, !state.isZipping else { return }
        state.isZipping = true
        state.message = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try Notchzip.make(from: urls) }
            DispatchQueue.main.async {
                self.state.isZipping = false
                switch result {
                case .success(let zip): then(zip)
                case .failure(let error): self.state.message = error.localizedDescription
                }
            }
        }
    }

    func airDrop() {
        withZip { zip in
            guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: [zip]) else {
                self.state.message = "AirDrop is off. Turn it on in Control Centre."
                return
            }
            self.hidePanel() // the AirDrop window would otherwise sit under the panel
            NSApp.activate(ignoringOtherApps: true)
            service.perform(withItems: [zip])
        }
    }

    func share() {
        withZip { zip in
            guard let anchor = self.state.shareAnchor.view else { return }
            let picker = NSSharingServicePicker(items: [zip])
            picker.delegate = self
            picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        }
    }

    func saveZip() {
        withZip { zip in
            do {
                let saved = try Notchzip.saveToDownloads(zip)
                self.state.message = "Saved \(saved.lastPathComponent) to Downloads"
                NSWorkspace.shared.activateFileViewerSelecting([saved])
            } catch {
                self.state.message = "Couldn't save: \(error.localizedDescription)"
            }
        }
    }

    func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        guard service != nil else { return }
        hidePanel()
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Drops on the menu bar logo (forwarded by the status item's window)

    @objc func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingSource is DragSourceNSView { return [] }
        showPanel()
        return .copy
    }

    @objc func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingSource is DragSourceNSView ? [] : .copy
    }

    @objc func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        store.importPasteboard(sender.draggingPasteboard)
        return true
    }
}
