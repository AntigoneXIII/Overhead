import AppKit
import QuickLookThumbnailing
import ServiceManagement
import SwiftUI

// MARK: - Shape

/// The notch silhouette: flush with the top of the screen, small concave
/// flares at the top corners and rounded bottom corners.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        let t = topRadius, b = bottomRadius
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + t, y: r.minY + t), control: CGPoint(x: r.minX + t, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + t, y: r.maxY - b))
        p.addQuadCurve(to: CGPoint(x: r.minX + t + b, y: r.maxY), control: CGPoint(x: r.minX + t, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - t - b, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - t, y: r.maxY - b), control: CGPoint(x: r.maxX - t, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - t, y: r.minY + t))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - t, y: r.minY))
        p.closeSubpath()
        return p
    }
}

enum Brand {
    static let logo: NSImage = {
        let image = Bundle.main.image(forResource: "logo-mark")
            ?? NSImage(systemSymbolName: "shippingbox.fill", accessibilityDescription: "Notchbox")!
        image.isTemplate = true
        return image
    }()
}

struct LogoMark: View {
    var size: CGFloat
    var body: some View {
        Image(nsImage: Brand.logo)
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .foregroundStyle(.white)
    }
}

// MARK: - Root

struct NotchRootView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: BayStore
    let actions: NotchActions

    var body: some View {
        let open = model.isOpen
        let size = open ? model.openSize : model.closedSize
        let topRadius: CGFloat = open ? 12 : 6

        ZStack(alignment: .top) {
            NotchShape(topRadius: topRadius, bottomRadius: open ? 22 : 9)
                .fill(Color.black)
                .shadow(color: .black.opacity(open ? 0.4 : 0), radius: 16, y: 8)

            if open {
                OpenContent(model: model, store: store, actions: actions)
                    .padding(.horizontal, topRadius)
                    .transition(.opacity.animation(.easeOut(duration: 0.15)))
            } else {
                ClosedContent(model: model, count: store.items.count)
                    .padding(.horizontal, topRadius)
                    .transition(.opacity.animation(.easeIn(duration: 0.1)))
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(NotchShape(topRadius: topRadius, bottomRadius: open ? 22 : 9))
        .onDrop(of: [.fileURL, .image, .url, .plainText, .data], isTargeted: $model.dropTargeted) { providers in
            store.importProviders(providers)
            return true
        }
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: open)
    }
}

// MARK: - Closed

struct ClosedContent: View {
    @ObservedObject var model: NotchModel
    let count: Int

    var body: some View {
        HStack(spacing: 0) {
            LogoMark(size: model.notchHeight * 0.58)
                .frame(width: NotchModel.earWidth)
            Spacer(minLength: 0)
            Text(count > 0 ? "\(count)" : "")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: NotchModel.earWidth)
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { model.isOpen = true }
        .help("Notchbox")
    }
}

// MARK: - Open

struct OpenContent: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: BayStore
    let actions: NotchActions

    private let columns = [GridItem(.adaptive(minimum: 92, maximum: 110), spacing: 8)]

    var body: some View {
        VStack(spacing: 0) {
            header
            itemsArea
            footer
        }
    }

    /// Sits in the menu bar strip, either side of the (real or drawn) notch.
    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                LogoMark(size: 14)
                Text("Notchbox").font(.system(size: 12, weight: .semibold))
            }
            .contentShape(Rectangle())
            .onTapGesture { model.isOpen = false }

            Spacer(minLength: model.hardwareNotchWidth + 12)

            Button { model.pinned.toggle() } label: {
                Image(systemName: model.pinned ? "pin.fill" : "pin")
            }
            .buttonStyle(.borderless)
            .help(model.pinned ? "Unpin: close when clicking elsewhere" : "Pin: stay open when clicking elsewhere")

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
        .padding(.horizontal, 14)
        .frame(height: model.notchHeight)
    }

    private var itemsArea: some View {
        Group {
            if store.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 26, weight: .light))
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
                    .padding(8)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(model.dropTargeted ? 0.08 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(model.dropTargeted ? 0.5 : 0), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        )
        .padding(.horizontal, 10)
        .padding(.top, 4)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if model.isZipping {
                ProgressView().controlSize(.small)
                Text("Making Notchzip…").foregroundStyle(.secondary)
            } else if let message = model.message {
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
            .background(ShareAnchor(holder: model.shareAnchor))
            .help("Zip everything as Notchzip.zip and send it with Messages, Mail and more")
        }
        .font(.system(size: 12))
        .disabled(store.items.isEmpty || model.isZipping)
        .padding(.horizontal, 14)
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
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 88)
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(hovering ? 0.1 : 0))
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
