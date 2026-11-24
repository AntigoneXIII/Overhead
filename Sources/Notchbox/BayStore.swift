import AppKit
import UniformTypeIdentifiers

struct BayItem: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let added: Date
}

/// Holds the items in the box. Every item is a real file kept in
/// ~/Library/Application Support/Notchbox/<id>/<name>, so dragging it out
/// always hands other apps a normal file. Copies on APFS are clones, so
/// holding a file costs no extra disk space.
final class BayStore: ObservableObject {
    static let shared = BayStore()

    @Published private(set) var items: [BayItem] = []

    let root: URL
    private let io = DispatchQueue(label: "notchbox.io")
    private var indexURL: URL { root.appendingPathComponent("index.json") }

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = support.appendingPathComponent("Notchbox", isDirectory: true)
        // Carry over anything stored by the earlier "Holding Bay" build.
        let legacy = support.appendingPathComponent("HoldingBay", isDirectory: true)
        if !FileManager.default.fileExists(atPath: root.path), FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.moveItem(at: legacy, to: root)
        }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        load()
    }

    func url(for item: BayItem) -> URL {
        root.appendingPathComponent(item.id.uuidString, isDirectory: true)
            .appendingPathComponent(item.name)
    }

    var allURLs: [URL] { items.map(url(for:)) }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([BayItem].self, from: data) else { return }
        items = decoded.filter { FileManager.default.fileExists(atPath: url(for: $0).path) }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private func commit(_ item: BayItem) {
        DispatchQueue.main.async {
            self.items.insert(item, at: 0)
            self.save()
        }
    }

    // MARK: Removing

    func remove(_ item: BayItem) {
        items.removeAll { $0.id == item.id }
        save()
        let dir = root.appendingPathComponent(item.id.uuidString, isDirectory: true)
        io.async { try? FileManager.default.removeItem(at: dir) }
    }

    func removeAll() {
        let gone = items
        items.removeAll()
        save()
        io.async {
            for item in gone {
                try? FileManager.default.removeItem(at: self.root.appendingPathComponent(item.id.uuidString))
            }
        }
    }

    // MARK: Adding (these run on whatever thread calls them)

    /// Copies synchronously. Callers handing over temporary files must call
    /// this before their callback returns, because the file is deleted after.
    private func ingestFile(_ source: URL, name: String? = nil) {
        let item = BayItem(id: UUID(), name: Self.clean(name ?? source.lastPathComponent), added: Date())
        let dest = url(for: item)
        do {
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: dest)
            commit(item)
        } catch {
            try? FileManager.default.removeItem(at: dest.deletingLastPathComponent())
            NSLog("Notchbox: could not add \(source.path): \(error)")
        }
    }

    private func ingestData(_ data: Data, name: String) {
        let item = BayItem(id: UUID(), name: Self.clean(name), added: Date())
        let dest = url(for: item)
        do {
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: dest)
            commit(item)
        } catch {
            NSLog("Notchbox: could not save \(name): \(error)")
        }
    }

    private func ingestText(_ text: String) {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let base = firstLine.trimmingCharacters(in: .whitespaces).prefix(40)
        ingestData(Data(text.utf8), name: (base.isEmpty ? "Text \(Self.stamp())" : String(base)) + ".txt")
    }

    private func ingestWebLink(_ link: URL) {
        let plist: [String: String] = ["URL": link.absoluteString]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else { return }
        ingestData(data, name: (link.host ?? "Link") + ".webloc")
    }

    func addFiles(_ urls: [URL]) {
        io.async { urls.forEach { self.ingestFile($0) } }
    }

    /// Handles drops onto the panel (SwiftUI hands us item providers).
    func importProviders(_ providers: [NSItemProvider]) {
        for p in providers {
            if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { self.io.async { self.ingestFile(url) } }
                }
            } else if let type = p.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) {
                loadFile(from: p, type: type)
            } else if p.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { self.io.async { self.ingestWebLink(url) } }
                }
            } else if p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                _ = p.loadObject(ofClass: String.self) { text, _ in
                    if let text { self.io.async { self.ingestText(text) } }
                }
            } else if let type = p.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .data) == true }) {
                // Covers promised files (Mail attachments, Photos, etc.)
                loadFile(from: p, type: type)
            }
        }
    }

    private func loadFile(from provider: NSItemProvider, type: String) {
        let ext = UTType(type)?.preferredFilenameExtension ?? "dat"
        let base = provider.suggestedName ?? "Item \(Self.stamp())"
        let name = base.hasSuffix(".\(ext)") ? base : "\(base).\(ext)"
        _ = provider.loadFileRepresentation(forTypeIdentifier: type) { tmp, _ in
            if let tmp { self.ingestFile(tmp, name: name) } // temp file: copy before returning
        }
    }

    /// Handles drops onto the menu bar icon and ⌘V in the panel.
    func importPasteboard(_ pb: NSPasteboard) {
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            addFiles(urls)
        } else if let promises = pb.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver], !promises.isEmpty {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            let queue = OperationQueue()
            for promise in promises {
                promise.receivePromisedFiles(atDestination: tmp, options: [:], operationQueue: queue) { url, error in
                    if error == nil { self.ingestFile(url) }
                }
            }
        } else if let png = pb.data(forType: .png) {
            io.async { self.ingestData(png, name: "Image \(Self.stamp()).png") }
        } else if let tiff = pb.data(forType: .tiff),
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            io.async { self.ingestData(png, name: "Image \(Self.stamp()).png") }
        } else if let links = pb.readObjects(forClasses: [NSURL.self]) as? [URL], let link = links.first {
            io.async { self.ingestWebLink(link) }
        } else if let text = pb.string(forType: .string), !text.isEmpty {
            io.async { self.ingestText(text) }
        }
    }

    // MARK: Helpers

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return f.string(from: Date())
    }

    private static func clean(_ name: String) -> String {
        let s = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? "Item" : s
    }
}
