import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var player: AudioPlayer
    @StateObject private var miniPlayer = MiniPlayerController()
    @State private var showImporter = false
    @State private var browsing: BrowseTarget?

    private func openBrowse(_ target: BrowseTarget) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            browsing = (browsing == target) ? nil : target
        }
    }

    private func closeBrowse() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            browsing = nil
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ShelfView(showImporter: $showImporter, browsing: browsing, onSelect: openBrowse)
                .frame(width: 250)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(.container, edges: .top)

            ZStack {
                NowPlayingView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(browsing == nil ? 1 : 0)

                if let target = browsing {
                    BrowseOverlay(target: target, onClose: closeBrowse)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(
            WorldView(palette: player.palette, artwork: player.currentTrack?.artwork)
        )
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.mp3, .mpeg4Audio, .wav, .aiff, .audio],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                let accessible = urls.filter { $0.startAccessingSecurityScopedResource() }
                player.addFiles(accessible.isEmpty ? urls : accessible)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFilesRequested)) { _ in
            showImporter = true
        }
        .onAppear { miniPlayer.configure(player: player) }
    }
}

// MARK: - Shelf (sidebar)

private struct ShelfView: View {
    @EnvironmentObject private var player: AudioPlayer
    @Environment(\.displayScale) private var displayScale
    @Binding var showImporter: Bool
    let browsing: BrowseTarget?
    let onSelect: (BrowseTarget) -> Void
    @State private var searchQuery = ""

    private var filteredPlaylists: [Playlist] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return player.playlists }
        return player.playlists.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    // Adaptive rail: contrast the stage by shifting the sidebar's brightness the
    // opposite way — lighten over dark albums, darken over bright ones.
    private var stageIsDark: Bool { player.stageLuminance < 0.48 }
    private var railBase: Color { stageIsDark ? .white : .black }
    private var railStrong: Double { stageIsDark ? 0.18 : 0.32 }
    private var railWeak: Double { stageIsDark ? 0.06 : 0.20 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    SearchRow(query: $searchQuery)
                        .padding(.bottom, 15)

                    AllTracksShelfRow(
                        count: player.tracks.count,
                        selected: browsing == .allTracks,
                        onSelect: { onSelect(.allTracks) }
                    )

                    ForEach(filteredPlaylists) { playlist in
                        Rectangle()
                            .fill(.white.opacity(0.07))
                            .frame(height: 1)
                            .padding(.horizontal, -10)
                        PlaylistShelfRow(
                            playlist: playlist,
                            selected: browsing == .playlist(playlist.id),
                            onSelect: { onSelect(.playlist(playlist.id)) }
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 22)
                .padding(.bottom, 16)
            }

            if player.showQueue {
                QueueSection()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack {
                Menu {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Add Tracks…", systemImage: "music.note")
                    }
                    Button {
                        let new = player.createPlaylist()
                        onSelect(.playlist(new.id))
                    } label: {
                        Label("New Playlist", systemImage: "rectangle.stack.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Add tracks or a new playlist")
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(alignment: .trailing) {
            // A darker rail: the glass gives material, and a darkening gradient
            // over it (deepest at the outer edge, easing toward the divider)
            // guarantees value contrast against the brighter now-playing stage
            // regardless of the album's palette. Oversized so the specular rim
            // is clipped away on all but the right (divider) edge.
            ZStack {
                Rectangle()
                    .fill(.clear)
                    .glassEffect(.clear, in: Rectangle())
                LinearGradient(
                    colors: [railBase.opacity(railStrong), railBase.opacity(railWeak)],
                    startPoint: .leading, endPoint: .trailing
                )
            }
            .padding(.top, -60)
            .padding(.bottom, -60)
            .padding(.leading, -40)
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.6), value: player.stageLuminance)
            // The glass draws a bright specular rim at the trailing seam; a thin
            // adaptive line covers it — dark over dark albums, light over bright —
            // giving a clean, quiet edge instead of glare.
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill((stageIsDark ? Color.black : Color.white).opacity(0.3))
                    .frame(width: 1)
                    .padding(.top, -60)
                    .padding(.bottom, -60)
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.6), value: player.stageLuminance)
            }
        }
    }
}

private struct QueueSection: View {
    @EnvironmentObject private var player: AudioPlayer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(height: 1)
                .padding(.horizontal, 12)

            HStack {
                Text("UP NEXT")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                        player.showQueue = false
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if player.upNext.isEmpty {
                Text("Nothing up next")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.horizontal, 18)
                    .padding(.bottom, 16)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(player.upNext) { track in
                            QueueRow(track: track)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                }
                .frame(maxHeight: 240)
            }
        }
    }
}

private struct QueueRow: View {
    @EnvironmentObject private var player: AudioPlayer
    let track: Track
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.06))
                if let art = track.artwork {
                    Image(nsImage: art)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 30, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(track.cleanTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                Text(track.artist.isEmpty ? "Unknown Artist" : track.artist)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(hovering ? .white.opacity(0.06) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { player.playTrack(track) }
        .onHover { hovering = $0 }
    }
}

/// A tiny dot-matrix equalizer where the header used to be. Columns rise and
/// fall on phase-offset sine waves (we have no live FFT, so this is a stylized
/// stand-in), colored to stay legible against the current scene.
struct DotField: View {
    let luminance: Double
    let active: Bool
    @StateObject private var clock = AnimationClock()

    private let columns = 28
    private let rows = 7
    private let dot: CGFloat = 3
    private let vGap: CGFloat = 3

    private let dotColor: Color = .white

    var body: some View {
        let t = clock.t
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(0..<columns, id: \.self) { c in
                // One shared time base with a phase gradient makes a smooth wave
                // travel across the columns; a slower second harmonic keeps it
                // from looking mechanical.
                let phase = Double(c) * 0.42
                let wave = sin(t * 1.5 + phase) * 0.34
                    + sin(t * 0.8 + phase * 0.6) * 0.16
                let level = active ? (wave + 0.5) : 0.12
                VStack(spacing: vGap) {
                    ForEach(0..<rows, id: \.self) { r in
                        let heightFromBottom = rows - 1 - r
                        let fill = level * Double(rows) - Double(heightFromBottom)
                        let op = 0.1 + 0.8 * min(max(fill, 0), 1)
                        Circle()
                            .fill(dotColor.opacity(op))
                            .frame(width: dot, height: dot)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.6), value: luminance)
        .onAppear { clock.start() }
    }
}

/// A search field shaped like the shelf rows — a 38pt glyph tile + inline field,
/// so it sits on the same grid as All Tracks and the playlists.
private struct SearchRow: View {
    @Binding var query: String

    var body: some View {
        HStack(spacing: 8) {
            TextField("", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .overlay(alignment: .leading) {
                    if query.isEmpty {
                        Text("Search")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.8))
                            .allowsHitTesting(false)
                    }
                }

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(.white.opacity(0.06))
        )
    }
}

/// The "All Tracks" entry, styled to match the playlist rows: a tile + two-line
/// label, so the library reads as one consistent list.
private struct AllTracksShelfRow: View {
    @EnvironmentObject private var player: AudioPlayer
    let count: Int
    let selected: Bool
    let onSelect: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 11) {
                PlaylistCover(cover: nil, tint: Array(player.palette.prefix(2)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("All Tracks")
                        .font(.system(size: 14, weight: selected ? .semibold : .medium))
                        .foregroundStyle(.white.opacity(selected ? 1 : 0.9))
                        .lineLimit(1)
                    Text("\(count) song\(count == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? .white.opacity(0.14) : (hovering ? .white.opacity(0.06) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct PlaylistShelfRow: View {
    @EnvironmentObject private var player: AudioPlayer
    let playlist: Playlist
    let selected: Bool
    let onSelect: () -> Void
    @State private var targeted = false

    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 11) {
                PlaylistCover(cover: player.distinctCovers(in: playlist).first, tint: Array(player.palette.prefix(2)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.name)
                        .font(.system(size: 14, weight: selected ? .semibold : .medium))
                        .foregroundStyle(.white.opacity(selected ? 1 : 0.9))
                        .lineLimit(1)
                    Text("\(playlist.trackIDs.count) song\(playlist.trackIDs.count == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? .white.opacity(0.14) : (hovering ? .white.opacity(0.06) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.white.opacity(targeted ? 0.6 : 0), lineWidth: 2)
        )
        .contextMenu {
            Button("Delete Playlist", role: .destructive) {
                player.deletePlaylist(playlist.id)
            }
        }
        .dropDestination(for: String.self) { ids, _ in
            var added = false
            for idString in ids {
                if let uuid = UUID(uuidString: idString) {
                    player.addToPlaylist(uuid, playlistID: playlist.id)
                    added = true
                }
            }
            return added
        } isTargeted: { targeted = $0 }
    }
}

/// A single, restrained playlist thumbnail — one lead cover, small and soft, so
/// it identifies the playlist without tiling over the world behind the sidebar.
private struct PlaylistCover: View {
    let cover: NSImage?
    var size: CGFloat = 38
    var tint: [Color] = []

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(.white.opacity(0.06))
            if let cover {
                Image(nsImage: cover)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "music.note.list")
                    .font(.system(size: size * 0.36))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        colors: tintColors.map { $0.opacity(0.62) },
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        )
        .animation(.easeInOut(duration: 0.6), value: tint)
    }

    private var tintColors: [Color] {
        switch tint.count {
        case 0: return [.clear, .clear]
        case 1: return [tint[0], tint[0]]
        default: return Array(tint.prefix(2))
        }
    }
}

private struct TrackRow: View {
    @EnvironmentObject private var player: AudioPlayer
    let track: Track
    var playlistContext: UUID? = nil
    /// The ordered list this row belongs to, so playback follows it as the queue.
    var queue: [Track] = []
    @State private var hovering = false

    private var isCurrent: Bool { player.currentTrack?.id == track.id }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white.opacity(0.06))
                if let art = track.artwork {
                    Image(nsImage: art)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.4))
                }
                if isCurrent && player.isPlaying {
                    RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.45))
                    Image(systemName: "waveform")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                }
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.cleanTitle)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? .white : .white.opacity(0.85))
                    .lineLimit(1)
                Text(track.artist.isEmpty ? "Unknown Artist" : track.artist)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if track.duration > 0 {
                Text(timeString(track.duration))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isCurrent ? .white.opacity(0.1) : (hovering ? .white.opacity(0.05) : .clear))
        )
        .overlay(
            TrackInteraction(
                idString: track.id.uuidString,
                cover: track.artwork,
                onClick: { player.play(track, context: queue) },
                onHover: { hovering = $0 },
                makeMenu: buildMenu
            )
        )
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let tid = track.id
        menu.addItem(ClosureMenuItem(title: "Rename…") {
            promptRename(track)
        })
        menu.addItem(.separator())
        if !player.playlists.isEmpty {
            let addTo = NSMenuItem(title: "Add to Playlist", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for playlist in player.playlists {
                let pid = playlist.id
                submenu.addItem(ClosureMenuItem(title: playlist.name) {
                    player.addToPlaylist(tid, playlistID: pid)
                })
            }
            addTo.submenu = submenu
            menu.addItem(addTo)
        }
        menu.addItem(ClosureMenuItem(title: "Add to New Playlist") {
            let new = player.createPlaylist()
            player.addToPlaylist(tid, playlistID: new.id)
        })
        if let pid = playlistContext {
            menu.addItem(ClosureMenuItem(title: "Remove from Playlist") {
                player.removeFromPlaylist(tid, playlistID: pid)
            })
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Remove from Library") {
            player.removeTrack(track)
        })
        return menu
    }

    private func promptRename(_ track: Track) {
        let alert = NSAlert()
        alert.messageText = "Rename Track"
        alert.informativeText = "Enter a new title. Leave blank to restore the original."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = track.displayTitle
        field.placeholderString = "Title"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            player.renameTrack(track, to: field.stringValue)
        }
    }
}

// MARK: - Browse overlay

private struct BrowseOverlay: View {
    @EnvironmentObject private var player: AudioPlayer
    let target: BrowseTarget
    let onClose: () -> Void

    private var currentPlaylist: Playlist? {
        if case .playlist(let id) = target { return player.playlists.first { $0.id == id } }
        return nil
    }

    private var title: String {
        switch target {
        case .allTracks: return "All Tracks"
        case .playlist: return currentPlaylist?.name ?? "Playlist"
        }
    }

    private var browseTracks: [Track] {
        switch target {
        case .allTracks: return player.tracks
        case .playlist: return currentPlaylist.map { player.tracks(in: $0) } ?? []
        }
    }

    private var trackCountLabel: String {
        "\(browseTracks.count) track\(browseTracks.count == 1 ? "" : "s")"
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { currentPlaylist?.name ?? "" },
            set: { if let id = currentPlaylist?.id { player.renamePlaylist(id, to: $0) } }
        )
    }

    private func commitName() {
        guard let id = currentPlaylist?.id else { return }
        let trimmed = (currentPlaylist?.name ?? "").trimmingCharacters(in: .whitespaces)
        player.renamePlaylist(id, to: trimmed.isEmpty ? "Untitled Playlist" : trimmed)
    }

    /// One artwork per distinct album in the playlist, in track order.
    private var collageArtworks: [NSImage] {
        var seen = Set<String>()
        var result: [NSImage] = []
        for track in browseTracks {
            guard let art = track.artwork else { continue }
            let key = track.album.isEmpty ? track.id.uuidString : track.album
            if seen.insert(key).inserted { result.append(art) }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Close")
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)

            if isAllTracks {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(trackCountLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 14)
            } else {
                VStack(spacing: 14) {
                    CollageView(artworks: collageArtworks, size: 140)
                    VStack(spacing: 6) {
                        Text("PLAYLIST")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1.5)
                            .foregroundStyle(.white.opacity(0.5))
                        TextField("Playlist Name", text: nameBinding)
                            .textFieldStyle(.plain)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .fixedSize()
                            .onSubmit(commitName)
                        Text(trackCountLabel)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 18)
            }

            if browseTracks.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(browseTracks) { track in
                            TrackRow(track: track, playlistContext: currentPlaylist?.id, queue: browseTracks)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 18)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(alignment: .leading) {
            // No glass pane — a soft scrim over the living world keeps the list
            // legible. A plain fill has no glass rim to refract the scrolling
            // rows (the chips) and no focus-driven spill over the sidebar.
            Rectangle()
                .fill(.black.opacity(0.28))
                .padding(.top, -60)
                .padding(.bottom, -60)
                .padding(.trailing, -40)
                .ignoresSafeArea()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "music.note")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.white.opacity(0.3))
            Text(isAllTracks ? "No tracks yet — add some with +" : "This playlist is empty")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
            if !isAllTracks {
                Text("Right-click a track in All Tracks to add it")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isAllTracks: Bool {
        if case .allTracks = target { return true }
        return false
    }
}

/// A fixed-size mosaic of every distinct album cover in a playlist. Cells shrink
/// as the count grows; each row fills its full width (the last, shorter row uses
/// wider cells) so there are never empty gaps.
private struct CollageView: View {
    let artworks: [NSImage]
    let size: CGFloat
    var maxCovers: Int = .max
    var cornerRadius: CGFloat = 14
    var showShadow: Bool = true

    private var covers: [NSImage] { Array(artworks.prefix(maxCovers)) }

    private var rows: [[NSImage]] {
        guard !covers.isEmpty else { return [] }
        let cols = max(1, Int(Double(covers.count).squareRoot().rounded(.up)))
        return stride(from: 0, to: covers.count, by: cols).map {
            Array(covers[$0 ..< min($0 + cols, covers.count)])
        }
    }

    var body: some View {
        Group {
            if covers.isEmpty {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius).fill(.white.opacity(0.06))
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.3, weight: .thin))
                        .foregroundStyle(.white.opacity(0.3))
                }
            } else {
                let rowH = size / CGFloat(rows.count)
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 0) {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, art in
                                Image(nsImage: art)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: size / CGFloat(row.count), height: rowH)
                                    .clipped()
                            }
                        }
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(.white.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(showShadow ? 0.35 : 0), radius: showShadow ? size * 0.12 : 0, y: showShadow ? size * 0.05 : 0)
    }
}

// MARK: - Now Playing

private struct NowPlayingView: View {
    @EnvironmentObject private var player: AudioPlayer
    @State private var volumeExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ArtworkView()
                .frame(width: 260, height: 260)
                .padding(.top, 16)
                .padding(.bottom, 28)

            VStack(spacing: 6) {
                Text(player.currentTrack?.cleanTitle ?? "Nothing Playing")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(player.currentTrack?.artist.isEmpty == false
                     ? player.currentTrack!.artist
                     : (player.currentTrack != nil ? "Unknown Artist" : "Add music to begin"))
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            .padding(.horizontal, 40)

            Spacer()

            TransportControls(volumeExpanded: volumeExpanded)
                .frame(width: 400)
                .padding(.vertical, 8)
                .background {
                    DotField(luminance: player.stageLuminance, active: player.isPlaying)
                        .opacity(0.28)
                        .clipShape(.capsule)
                        .allowsHitTesting(false)
                }
                .glassEffect(.clear.tint(.black.opacity(0.28)), in: .capsule)
                .overlay(alignment: .leading) {
                    ExpandingVolume(expanded: $volumeExpanded)
                        .padding(.leading, 16)
                }
                .overlay(alignment: .trailing) {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                            player.showQueue.toggle()
                        }
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(player.showQueue ? .white : .white.opacity(0.6))
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 16)
                    .help("Queue")
                }

            Scrubber()
                .frame(width: 400)
                .padding(.top, 14)
                .padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ArtworkView: View {
    @EnvironmentObject private var player: AudioPlayer

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.white.opacity(0.14), .white.opacity(0.04)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            if let art = player.currentTrack?.artwork {
                Image(nsImage: art)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 260, height: 260)
                    .clipped()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 64, weight: .thin))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .frame(width: 260, height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 30, y: 16)
    }
}

private struct Scrubber: View {
    @EnvironmentObject private var player: AudioPlayer
    @State private var dragging = false
    @State private var dragValue: Double = 0

    private var displayTime: Double { dragging ? dragValue : player.currentTime }

    var body: some View {
        HStack(spacing: 8) {
            Text(timeString(displayTime))
                .frame(width: 32, alignment: .leading)

            Slider(
                value: Binding(
                    get: { dragging ? dragValue : player.currentTime },
                    set: { dragValue = $0 }
                ),
                in: 0...max(player.duration, 0.01),
                onEditingChanged: { editing in
                    if editing {
                        dragging = true
                        dragValue = player.currentTime
                    } else {
                        player.seek(to: dragValue)
                        dragging = false
                    }
                }
            )
            .controlSize(.small)
            .tint(.white)

            Text("-" + timeString(max(player.duration - displayTime, 0)))
                .frame(width: 38, alignment: .trailing)
        }
        .font(.system(size: 11).monospacedDigit())
        .foregroundStyle(.white.opacity(0.5))
    }
}

private struct TransportControls: View {
    @EnvironmentObject private var player: AudioPlayer
    var volumeExpanded: Bool = false

    var body: some View {
        HStack(spacing: 22) {
            Button {
                player.shuffle.toggle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(player.shuffle ? .white : .white.opacity(0.4))
            }
            .buttonStyle(.plain)
            .opacity(volumeExpanded ? 0 : 1)
            .allowsHitTesting(!volumeExpanded)

            Button { player.previous() } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .buttonStyle(.plain)

            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(player.tracks.isEmpty)

            Button { player.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .buttonStyle(.plain)

            Button { player.cycleRepeat() } label: {
                Image(systemName: player.repeatMode.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(player.repeatMode == .off ? .white.opacity(0.4) : .white)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct ExpandingVolume: View {
    @EnvironmentObject private var player: AudioPlayer
    @Binding var expanded: Bool

    private var icon: String {
        if player.volume <= 0.001 { return "speaker.slash.fill" }
        if player.volume < 0.5 { return "speaker.wave.1.fill" }
        return "speaker.wave.2.fill"
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    expanded.toggle()
                }
            } label: {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Slider(value: Binding(
                    get: { Double(player.volume) },
                    set: { player.volume = Float($0) }
                ), in: 0...1)
                .controlSize(.mini)
                .tint(.white.opacity(0.7))
                .frame(width: 76)
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
    }
}

private struct VolumeControl: View {
    @EnvironmentObject private var player: AudioPlayer

    private var icon: String {
        if player.volume <= 0.001 { return "speaker.slash.fill" }
        if player.volume < 0.5 { return "speaker.wave.1.fill" }
        return "speaker.wave.2.fill"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 14, alignment: .leading)
            Slider(value: Binding(
                get: { Double(player.volume) },
                set: { player.volume = Float($0) }
            ), in: 0...1)
            .controlSize(.mini)
            .tint(.white.opacity(0.65))
        }
        .frame(width: 120)
    }
}

// MARK: - Helpers

func timeString(_ t: TimeInterval) -> String {
    guard t.isFinite, t >= 0 else { return "0:00" }
    let total = Int(t)
    return String(format: "%d:%02d", total / 60, total % 60)
}

extension NSImage {
    /// Loads a PNG bundled into the app's Resources by build_app.sh, downsampled
    /// with ImageIO to a crisp thumbnail — resampling a huge bitmap on the fly at
    /// display time looks soft, so we bake a sharp small version up front.
    static func bundled(_ name: String, pointSize: CGFloat, scale: CGFloat) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        // Generate the thumbnail at exactly the device-pixel size and label the
        // NSImage as pointSize, so it maps 1:1 to screen pixels with no further
        // resampling — the crispest possible downscale.
        let maxPixel = max(1, (pointSize * scale).rounded())
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return NSImage(contentsOf: url)
        }
        return NSImage(cgImage: cg, size: NSSize(width: pointSize, height: pointSize))
    }
}
