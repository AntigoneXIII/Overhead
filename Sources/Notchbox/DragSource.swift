import AppKit
import SwiftUI

/// An AppKit view that starts a real file drag, which Finder, Mail, Slack,
/// browsers and most other apps accept. Also handles double-click and the
/// right-click menu for the tile it sits on.
final class DragSourceNSView: NSView, NSDraggingSource {
    var urls: () -> [URL] = { [] }
    var preview: () -> NSImage? = { nil }
    var onDoubleClick: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?
    /// Leaves the top-right corner to SwiftUI so the remove button stays clickable.
    var passThroughCorner = false

    private var mouseDownEvent: NSEvent?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        if passThroughCorner {
            let local = convert(point, from: superview)
            let cornerSize: CGFloat = 24
            let inCorner = local.x > bounds.maxX - cornerSize &&
                (isFlipped ? local.y < cornerSize : local.y > bounds.maxY - cornerSize)
            if inCorner { return nil }
        }
        return hit
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
            mouseDownEvent = nil
        } else {
            mouseDownEvent = event
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent else { return }
        let dx = event.locationInWindow.x - down.locationInWindow.x
        let dy = event.locationInWindow.y - down.locationInWindow.y
        guard hypot(dx, dy) > 3 else { return }
        mouseDownEvent = nil

        let list = urls()
        guard !list.isEmpty else { return }
        let point = convert(event.locationInWindow, from: nil)
        let side: CGFloat = 64

        let items: [NSDraggingItem] = list.enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let image = (index == 0 ? preview() : nil) ?? NSWorkspace.shared.icon(forFile: url.path)
            let offset = CGFloat(min(index, 4)) * 5
            item.setDraggingFrame(
                NSRect(x: point.x - side / 2 + offset, y: point.y - side / 2 - offset, width: side, height: side),
                contents: image
            )
            return item
        }
        let session = beginDraggingSession(with: items, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    override func mouseUp(with event: NSEvent) { mouseDownEvent = nil }

    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() }

    // Copy only, and never back into our own panel or icon.
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }
}

struct DragSource: NSViewRepresentable {
    var urls: () -> [URL]
    var preview: () -> NSImage? = { nil }
    var onDoubleClick: (() -> Void)? = nil
    var menu: (() -> NSMenu?)? = nil
    var passThroughCorner = false

    func makeNSView(context: Context) -> DragSourceNSView { DragSourceNSView() }

    func updateNSView(_ view: DragSourceNSView, context: Context) {
        view.urls = urls
        view.preview = preview
        view.onDoubleClick = onDoubleClick
        view.menuProvider = menu
        view.passThroughCorner = passThroughCorner
    }
}

/// NSMenuItem that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { handler() }
}
