import AppKit
import QuickLookThumbnailing
import ServiceManagement
import SwiftUI

protocol BoxActions: AnyObject {
    func airDrop()
    func share()
    func saveZip()
}

final class PanelState: ObservableObject {
    @Published var pinned = false
    @Published var isZipping = false
    @Published var message: String?
    let shareAnchor = AnchorHolder()
}

// MARK: - Logo

enum Brand {
    /// The logo drawn from vector outlines (see LogoPath.swift), so it is
    /// sharp at every size and on every display. Template image: macOS tints
    /// it to match the menu bar.
    static func logo(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            NSColor.black.setFill()
            for polygon in LogoPath.polygons {
                guard let first = polygon.first else { continue }
                let path = NSBezierPath()
                path.move(to: point(first, in: rect))
                for p in polygon.dropFirst() { path.line(to: point(p, in: rect)) }
                path.close()
                path.fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Notchbox"
        return image
    }

    private static func point(_ p: CGPoint, in rect: NSRect) -> NSPoint {
        NSPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height)
    }
}

struct LogoMark: View {
    var size: CGFloat
    var body: some View {
        Image(nsImage: Brand.logo(size: size))
            .renderingMode(.template)
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
    }
}

// MARK: - Panel

struct PanelView: View {
    @ObservedObject var store: BayStore
    @ObservedObject var state: PanelState
    let actions: BoxActions

    @State private var dropTargeted = false
    private let columns = [GridItem(.adaptive(minimum: 92, maximum: 110), spacing: 8)]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            itemsArea
            Divider()
            footer
        }
        .frame(width: PanelMetrics.size.width, height: PanelMetrics.size.height)
        .overlay(
            RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius - 2)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .padding(2)
                .opacity(dropTargeted ? 1 : 0)
        )
        .onDrop(of: [.fileURL, .image, .url, .plainText, .data], isTargeted: $dropTargeted) { providers in
            store.importProviders(providers)
            return true
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            LogoMark(size: 16)
            Text("Notchbox").font(.headline)
            Spacer()

            Button { state.pinned.toggle() } label: {
                Image(systemName: state.pinned ? "pin.fill" : "pin")
            }
            .buttonStyle(.borderless)
            .help(state.pinned ? "Unpin: close when clicking elsewhere" : "Pin: stay open when clicking elsewhere")

            Menu {
                Button("Paste from Clipboard") { store.importPasteboard(.general) }
                Button("Save Notchzip to Downloads") { actions.saveZip() }.disabled(store.items.isEmpty)
                Button("Show Storage Folder") { NSWorkspace.shared.open(store.root) }
                Button("Remove All") { store.removeAll() }.disabled(store.items.isEmpty)
                Divider()
                Toggle("Open at Login", isOn: launchAtLogin)
                Divider()
                Button("Quit Notchbox") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }

    private var itemsArea: some View {
        Group {
            if store.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("Drop files, screenshots or text here")
                        .foregroundStyle(.secondary)
                    Text("⌘V pastes whatever is on the clipboard")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(store.items) { item in
                            ItemTile(item: item, url: store.url(for: item), store: store)
                        }
                    }
                    .padding(10)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if state.isZipping {
                ProgressView().controlSize(.small)
                Text("Making Notchzip…").foregroundStyle(.secondary)
            } else if let message = state.message {
                Text(message).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text(store.items.isEmpty ? "Empty" : "\(store.items.count) item\(store.items.count == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if store.items.count > 1 {
                Image(systemName: "square.stack.3d.up")
                    .frame(width: 24, height: 24)
                    .overlay(DragSource(urls: { store.allURLs }))
                    .help("Drag to take all \(store.items.count) items at once")
            }

            Button { actions.airDrop() } label: {
                Label {
                    Text("AirDrop")
                } icon: {
                    if let image = NSSharingService(named: .sendViaAirDrop)?.image {
                        Image(nsImage: image).resizable().frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "dot.radiowaves.left.and.right")
                    }
                }
            }
            .help("Zip everything as Notchzip.zip and send it with AirDrop")

            Button { actions.share() } label: {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
            .background(ShareAnchor(holder: state.shareAnchor))
            .help("Zip everything as Notchzip.zip and send it with Messages, Mail and more")
        }
        .font(.system(size: 12))
        .disabled(store.items.isEmpty || state.isZipping)
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { on in
                do {
                    if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    NSLog("Notchbox: login item change failed: \(error)")
                }
            }
        )
    }
}

/// Gives the share picker an AppKit view to point at.
final class AnchorHolder { weak var view: NSView? }

struct ShareAnchor: NSViewRepresentable {
    let holder: AnchorHolder
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        holder.view = view
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) { holder.view = nsView }
}

// MARK: - Tile

struct ItemTile: View {
    let item: BayItem
    let url: URL
    let store: BayStore

    @State private var thumbnail: NSImage?
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Color.clear
                }
            }
            .frame(width: 76, height: 60)

            Text(item.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 88)
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(hovering ? 0.08 : 0))
        )
        .overlay(
            DragSource(
                urls: { [url] },
                preview: { thumbnail },
                onDoubleClick: { NSWorkspace.shared.open(url) },
                menu: { contextMenu },
                passThroughCorner: true
            )
        )
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button { store.remove(item) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 15))
                }
                .buttonStyle(.borderless)
                .padding(3)
                .help("Remove from Notchbox")
            }
        }
        .onHover { hovering = $0 }
        .help(item.name)
        .task(id: url) { thumbnail = await Thumbnails.image(for: url) }
    }

    private var contextMenu: NSMenu {
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("Open") { NSWorkspace.shared.open(url) })
        menu.addItem(ClosureMenuItem("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) })
        menu.addItem(ClosureMenuItem("Copy") {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([url as NSURL])
        })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Remove") { store.remove(item) })
        return menu
    }
}

enum Thumbnails {
    static func image(for url: URL) async -> NSImage {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 76, height: 60),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .all
        )
        if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            return rep.nsImage
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
