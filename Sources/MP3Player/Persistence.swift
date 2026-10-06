import Foundation

/// On-disk shape of the library. Tracks and playlist membership are stored by
/// file path — the runtime Track UUIDs aren't stable across launches.
struct SavedState: Codable {
    var trackPaths: [String]
    var playlists: [SavedPlaylist]
    /// User-renamed titles, keyed by file path. Optional so libraries saved
    /// before this feature still decode.
    var customTitles: [String: String]?
}

struct SavedPlaylist: Codable {
    var name: String
    var trackPaths: [String]
}

enum Persistence {
    private static var fileURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("MP3Player", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("library.json")
    }

    static func save(_ state: SavedState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func load() -> SavedState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(SavedState.self, from: data)
    }
}
