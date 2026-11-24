import AppKit
import SwiftUI

/// Debug aid: `Notchbox --snapshot <dir>` renders the menu bar logo and the
/// panel to PNGs and exits. Used to check visuals without screen recording access.
enum Snapshot {
    final class NoActions: BoxActions {
        func airDrop() {}
        func share() {}
        func saveZip() {}
    }

    @MainActor
    static func run(into dir: URL) {
        // Menu bar logo at its real size, at 1x, 2x and 3x.
        let logo = Brand.logo(size: 17)
        for scale in [1, 2, 3] {
            let px = 17 * scale
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
            rep.size = NSSize(width: 17, height: 17)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: 17, height: 17).fill()
            logo.draw(in: NSRect(x: 0, y: 0, width: 17, height: 17))
            NSGraphicsContext.restoreGraphicsState()
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("logo@\(scale)x.png"))
        }

        let view = PanelView(store: BayStore.shared, state: PanelState(), actions: NoActions())
            .background(Color(nsColor: .windowBackgroundColor))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        if let tiff = renderer.nsImage?.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: dir.appendingPathComponent("panel.png"))
        }
    }
}
