import Foundation

struct Playlist: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var trackIDs: [UUID]

    static func == (lhs: Playlist, rhs: Playlist) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.trackIDs == rhs.trackIDs
    }
}

/// What the browse overlay is currently showing. Playlists are referenced by id
/// so the overlay always resolves the live copy.
enum BrowseTarget: Equatable {
    case allTracks
    case playlist(UUID)
}
