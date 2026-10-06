import Foundation
import AppKit

struct Track: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var artwork: NSImage?
    /// A user-chosen title that overrides the file's metadata (SoundCloud rips
    /// often have junk titles). When set, it's shown verbatim — no annotation
    /// stripping — since the user picked it deliberately.
    var customTitle: String? = nil

    // Compare the fields that affect display, not just id — otherwise SwiftUI
    // treats a row as unchanged when async metadata (artwork/artist/title)
    // arrives and never re-renders it.
    static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.customTitle == rhs.customTitle &&
        lhs.artist == rhs.artist &&
        lhs.duration == rhs.duration &&
        lhs.artwork === rhs.artwork
    }

    var displayTitle: String {
        if let customTitle, !customTitle.isEmpty { return customTitle }
        return title.isEmpty ? url.deletingPathExtension().lastPathComponent : title
    }

    /// Title with trailing annotations stripped — "(Album Version (Explicit))",
    /// "[Remastered]", etc. — so the UI shows the plain song name.
    var cleanTitle: String {
        if let customTitle, !customTitle.isEmpty { return customTitle }
        var result = ""
        var depth = 0
        for ch in displayTitle {
            if ch == "(" || ch == "[" { depth += 1; continue }
            if ch == ")" || ch == "]" { depth = max(0, depth - 1); continue }
            if depth == 0 { result.append(ch) }
        }
        let cleaned = result.split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        return cleaned.isEmpty ? displayTitle : cleaned
    }
}
