import AppKit
import Combine
import SwiftUI

enum PanelMetrics {
    static let size = NSSize(width: 380, height: 320)
    static let cornerRadius: CGFloat = 12
}

final class BayPanel: NSPanel {
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

/// Owns the menu bar icon and the drop-down panel.
final class StatusController: NSObject, NSWindowDelegate {
    private let store: BayStore
    private let state = PanelState()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel: BayPanel
    private var cancellables = Set<AnyCancellable>()
    private var monitors: [Any] = []
    private var outsideMouseDown: NSPoint?

    init(store: BayStore) {
        self.store = store
        panel = BayPanel(content: NSHostingView(rootView: BayView(store: store, state: state)))
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "tray", accessibilityDescription: "Holding Bay")
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePanel)

            // Dragging something onto the icon opens the bay; dropping on it adds the item.
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
                self?.statusItem.button?.image = NSImage(
                    systemSymbolName: items.isEmpty ? "tray" : "tray.full",
                    accessibilityDescription: "Holding Bay"
                )
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
        // something (e.g. picking up a file in Finder to bring into the bay).
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.outsideMouseDown = NSEvent.mouseLocation
        }) { monitors.append(m) }

        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp], handler: { [weak self] _ in
            guard let self, let start = self.outsideMouseDown else { return }
            self.outsideMouseDown = nil
            let end = NSEvent.mouseLocation
            let moved = hypot(end.x - start.x, end.y - start.y)
            if moved < 6, !self.state.pinned, !self.panel.frame.contains(end) {
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

    // MARK: Drops on the menu bar icon (forwarded by the status item's window)

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
