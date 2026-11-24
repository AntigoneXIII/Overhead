import Foundation

/// Packs everything in the box into Notchzip.zip. Unzipping it gives a
/// "Notchzip" folder with the items inside.
enum Notchzip {
    private static let prefix = "Notchbox-zip-"
    private static var lastWorkDir: URL?

    enum Failure: LocalizedError {
        case dittoFailed(Int32)
        var errorDescription: String? {
            switch self {
            case .dittoFailed(let code): return "Couldn't create the zip (ditto exited with \(code))."
            }
        }
    }

    /// Runs on a background thread. The zip stays on disk until the next
    /// one is made (or the app relaunches) so AirDrop has time to send it.
    static func make(from urls: [URL]) throws -> URL {
        let fm = FileManager.default
        if let old = lastWorkDir { try? fm.removeItem(at: old) }

        let work = fm.temporaryDirectory.appendingPathComponent(prefix + UUID().uuidString, isDirectory: true)
        let folder = work.appendingPathComponent("Notchzip", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        lastWorkDir = work

        var used = Set<String>()
        for url in urls {
            let name = uniqueName(url.lastPathComponent, taken: &used)
            try fm.copyItem(at: url, to: folder.appendingPathComponent(name)) // APFS clone, near-instant
        }

        let zip = work.appendingPathComponent("Notchzip.zip")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", folder.path, zip.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw Failure.dittoFailed(ditto.terminationStatus) }
        return zip
    }

    /// Saves a copy into ~/Downloads without overwriting an older Notchzip.
    static func saveToDownloads(_ zip: URL) throws -> URL {
        let fm = FileManager.default
        let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        var dest = downloads.appendingPathComponent("Notchzip.zip")
        var n = 2
        while fm.fileExists(atPath: dest.path) {
            dest = downloads.appendingPathComponent("Notchzip \(n).zip")
            n += 1
        }
        try fm.copyItem(at: zip, to: dest)
        return dest
    }

    static func cleanUpOldZips() {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        let entries = (try? fm.contentsOfDirectory(atPath: tmp.path)) ?? []
        for name in entries where name.hasPrefix(prefix) {
            try? fm.removeItem(at: tmp.appendingPathComponent(name))
        }
    }

    private static func uniqueName(_ name: String, taken: inout Set<String>) -> String {
        guard taken.contains(name) else { taken.insert(name); return name }
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        var n = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            if !taken.contains(candidate) { taken.insert(candidate); return candidate }
            n += 1
        }
    }
}
