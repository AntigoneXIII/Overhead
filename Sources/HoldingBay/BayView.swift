import AppKit
import QuickLookThumbnailing
import ServiceManagement
import SwiftUI

final class PanelState: ObservableObject {
    @Published var pinned = false
}

struct BayView: View {
    @ObservedObject var store: BayStore
    @ObservedObject var state: PanelState
    @State private var dropTargeted = false

    private let columns = [GridItem(.adaptive(minimum: 92, maximum: 110), spacing: 8)]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.items.isEmpty {
                emptyState
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
        HStack(spacing: 10) {
            Text("Holding Bay").font(.headline)
            if !store.items.isEmpty {
                Text("\(store.items.count)").foregroundStyle(.secondary)
            }
            Spacer()

            if store.items.count > 1 {
                Image(systemName: "square.stack.3d.up")
                    .frame(width: 22, height: 22)
                    .overlay(DragSource(urls: { store.allURLs }))
                    .help("Drag to move all \(store.items.count) items at once")
            }

            Button {
                state.pinned.toggle()
            } label: {
                Image(systemName: state.pinned ? "pin.fill" : "pin")
            }
            .buttonStyle(.borderless)
            .help(state.pinned ? "Unpin: close when clicking elsewhere" : "Pin: keep open when clicking elsewhere")

            Menu {
                Button("Paste from Clipboard") { store.importPasteboard(.general) }
                Button("Show Folder in Finder") { NSWorkspace.shared.open(store.root) }
                Button("Remove All") { store.removeAll() }.disabled(store.items.isEmpty)
                Divider()
                Toggle("Open at Login", isOn: launchAtLogin)
                Divider()
                Button("Quit Holding Bay") { NSApp.terminate(nil) }
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

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text("Drop files, screenshots or text here")
                .foregroundStyle(.secondary)
            Text("⌘V pastes whatever is on the clipboard")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { on in
                do {
                    if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    NSLog("HoldingBay: login item change failed: \(error)")
                }
            }
        )
    }
}

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
                .help("Remove from bay")
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
