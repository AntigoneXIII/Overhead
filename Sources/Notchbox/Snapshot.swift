import AppKit
import SwiftUI

/// Debug aid: `Notchbox --snapshot <dir>` renders the closed and open notch
/// to PNGs and exits. Used to check layout without screen recording access.
enum Snapshot {
    final class NoActions: NotchActions {
        func airDrop() {}
        func share() {}
        func saveZip() {}
    }

    @MainActor
    static func run(into dir: URL) {
        let model = NotchModel()
        model.notchHeight = 32
        model.hardwareNotchWidth = CommandLine.arguments.contains("--notch") ? 185 : 0
        model.closedSize = CGSize(width: model.hardwareNotchWidth + NotchModel.earWidth * 2 + 12 + (model.hardwareNotchWidth > 0 ? 0 : 50), height: 32)
        model.openSize = CGSize(width: max(520, model.hardwareNotchWidth + 320), height: 32 + 310)
        let actions = NoActions()

        for open in [false, true] {
            model.isOpen = open
            let size = open ? model.openSize : model.closedSize
            let view = ZStack(alignment: .top) {
                Color(white: 0.55) // stand-in for a wallpaper
                NotchRootView(model: model, store: BayStore.shared, actions: actions)
            }
            .frame(width: size.width + 80, height: size.height + 40)

            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let image = renderer.nsImage,
               let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent(open ? "open.png" : "closed.png"))
            }
        }
    }
}
