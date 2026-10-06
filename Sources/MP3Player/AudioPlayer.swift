import Foundation
import AVFoundation
import AppKit
import SwiftUI

enum RepeatMode: CaseIterable {
    case off, all, one

    var symbol: String {
        switch self {
        case .off, .all: return "repeat"
        case .one: return "repeat.1"
        }
    }
}

@MainActor
final class AudioPlayer: NSObject, ObservableObject {
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var currentIndex: Int? = nil
    @Published private(set) var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published var volume: Float = 0.8 {
        didSet { engine?.volume = volume }
    }
    @Published var repeatMode: RepeatMode = .off
    @Published var shuffle = false
    @Published private(set) var palette: [Color] = ColorExtractor.fallback
    @Published private(set) var stageLuminance: Double = 0.5
    @Published private(set) var playlists: [Playlist] = []
    @Published var showQueue = false

    /// Ordered track IDs for the current playback context — the playlist (or the
    /// full library) the current song was started from. Empty means the full
    /// library. This is what next/previous and the queue follow, so playing from
    /// a playlist advances through that playlist, not the global track list.
    private var contextIDs: [UUID] = []

    /// The current playback context resolved to live tracks, in order.
    private var contextTracks: [Track] {
        guard !contextIDs.isEmpty else { return tracks }
        return contextIDs.compactMap { id in tracks.first { $0.id == id } }
    }

    /// Tracks that will play after the current one, in order.
    var upNext: [Track] {
        let ctx = contextTracks
        guard let id = currentTrack?.id,
              let i = ctx.firstIndex(where: { $0.id == id }) else { return [] }
        return Array(ctx[(i + 1)...])
    }

    private var engine: AVAudioPlayer?
    private var ticker: Timer?
    private var isRestoring = false

    override init() {
        super.init()
        restore()
    }

    var currentTrack: Track? {
        guard let i = currentIndex, tracks.indices.contains(i) else { return nil }
        return tracks[i]
    }

    // MARK: - Persistence

    private func persist() {
        guard !isRestoring else { return }
        let pathFor: (UUID) -> String? = { id in self.tracks.first { $0.id == id }?.url.path }
        var customTitles: [String: String] = [:]
        for track in tracks where track.customTitle?.isEmpty == false {
            customTitles[track.url.path] = track.customTitle
        }
        let state = SavedState(
            trackPaths: tracks.map { $0.url.path },
            playlists: playlists.map { pl in
                SavedPlaylist(name: pl.name, trackPaths: pl.trackIDs.compactMap(pathFor))
            },
            customTitles: customTitles.isEmpty ? nil : customTitles
        )
        Persistence.save(state)
    }

    private func restore() {
        guard let state = Persistence.load() else { return }
        isRestoring = true
        let urls = state.trackPaths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        addFiles(urls)

        if let customTitles = state.customTitles {
            for i in tracks.indices {
                if let custom = customTitles[tracks[i].url.path] {
                    tracks[i].customTitle = custom
                }
            }
        }

        var idByPath: [String: UUID] = [:]
        for track in tracks { idByPath[track.url.path] = track.id }
        playlists = state.playlists.map { saved in
            Playlist(name: saved.name, trackIDs: saved.trackPaths.compactMap { idByPath[$0] })
        }
        isRestoring = false
    }

    /// Rename a track's shown title. An empty name clears the override, falling
    /// back to the file's metadata title.
    func renameTrack(_ track: Track, to newTitle: String) {
        guard let idx = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        tracks[idx].customTitle = trimmed.isEmpty ? nil : trimmed
        persist()
    }

    // MARK: - Library

    func addFiles(_ urls: [URL]) {
        for url in urls {
            guard !tracks.contains(where: { $0.url == url }) else { continue }
            let placeholder = Track(
                url: url,
                title: url.deletingPathExtension().lastPathComponent,
                artist: "",
                album: "",
                duration: 0,
                artwork: nil
            )
            tracks.append(placeholder)
            let id = placeholder.id
            Task { await loadMetadata(for: url, trackID: id) }
        }
        if currentIndex == nil, !tracks.isEmpty {
            currentIndex = 0
        }
        persist()
    }

    func removeTrack(_ track: Track) {
        guard let idx = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        let wasCurrent = idx == currentIndex
        tracks.remove(at: idx)
        if tracks.isEmpty {
            stop()
            currentIndex = nil
        } else if wasCurrent {
            currentIndex = min(idx, tracks.count - 1)
            load(at: currentIndex!, autoplay: isPlaying)
        } else if let ci = currentIndex, idx < ci {
            currentIndex = ci - 1
        }
        persist()
    }

    // MARK: - Playlists

    @discardableResult
    func createPlaylist(name: String = "New Playlist") -> Playlist {
        let playlist = Playlist(name: name, trackIDs: [])
        playlists.append(playlist)
        persist()
        return playlist
    }

    func renamePlaylist(_ id: UUID, to name: String) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[i].name = name
        persist()
    }

    func deletePlaylist(_ id: UUID) {
        playlists.removeAll { $0.id == id }
        persist()
    }

    func addToPlaylist(_ trackID: UUID, playlistID: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        if !playlists[i].trackIDs.contains(trackID) {
            playlists[i].trackIDs.append(trackID)
            persist()
        }
    }

    func removeFromPlaylist(_ trackID: UUID, playlistID: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[i].trackIDs.removeAll { $0 == trackID }
        persist()
    }

    func tracks(in playlist: Playlist) -> [Track] {
        playlist.trackIDs.compactMap { id in tracks.first { $0.id == id } }
    }

    /// One artwork per distinct album in the playlist, in track order.
    func distinctCovers(in playlist: Playlist) -> [NSImage] {
        var seen = Set<String>()
        var result: [NSImage] = []
        for track in tracks(in: playlist) {
            guard let art = track.artwork else { continue }
            let key = track.album.isEmpty ? track.id.uuidString : track.album
            if seen.insert(key).inserted { result.append(art) }
        }
        return result
    }

    private func loadMetadata(for url: URL, trackID: UUID) async {
        let asset = AVURLAsset(url: url)
        var title = ""
        var artist = ""
        var album = ""
        var artwork: NSImage?
        var dur: TimeInterval = 0

        if let cmDuration = try? await asset.load(.duration) {
            dur = CMTimeGetSeconds(cmDuration)
            if dur.isNaN || dur.isInfinite { dur = 0 }
        }

        if let metadata = try? await asset.load(.commonMetadata) {
            for item in metadata {
                guard let key = item.commonKey else { continue }
                let string = (try? await item.load(.stringValue)).flatMap { $0 } ?? ""
                switch key {
                case .commonKeyTitle:
                    title = string
                case .commonKeyArtist:
                    artist = string
                case .commonKeyAlbumName:
                    album = string
                case .commonKeyArtwork:
                    if let data = try? await item.load(.dataValue) {
                        artwork = NSImage(data: data)
                    }
                default:
                    break
                }
            }
        }

        guard let idx = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        if !title.isEmpty { tracks[idx].title = title }
        tracks[idx].artist = artist
        tracks[idx].album = album
        tracks[idx].duration = dur
        tracks[idx].artwork = artwork
        if idx == currentIndex {
            if engine == nil { duration = dur }
            refreshPalette()
        }
    }

    private func refreshPalette() {
        if let art = currentTrack?.artwork {
            let extracted = ColorExtractor.palette(from: art, count: 6)
            palette = extracted.count >= 3 ? extracted : ColorExtractor.fallback
        } else {
            palette = ColorExtractor.fallback
        }
        stageLuminance = ColorExtractor.averageLuminance(of: palette)
    }

    // MARK: - Transport

    /// Play a track, setting the playback context (the list it came from) so the
    /// queue and next/previous follow that order rather than the global library.
    func play(_ track: Track, context: [Track]) {
        contextIDs = context.map { $0.id }
        playTrack(track)
    }

    func playTrack(_ track: Track) {
        guard let idx = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        currentIndex = idx
        load(at: idx, autoplay: true)
    }

    private func load(at index: Int, autoplay: Bool) {
        guard tracks.indices.contains(index) else { return }
        let track = tracks[index]
        stopTicker()
        refreshPalette()
        do {
            let player = try AVAudioPlayer(contentsOf: track.url)
            player.delegate = self
            player.volume = volume
            player.prepareToPlay()
            engine = player
            duration = player.duration
            currentTime = 0
            if autoplay { play() } else { isPlaying = false }
        } catch {
            NSLog("Failed to load \(track.url.lastPathComponent): \(error.localizedDescription)")
            engine = nil
        }
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            if engine == nil, let i = currentIndex {
                load(at: i, autoplay: true)
            } else {
                play()
            }
        }
    }

    private func play() {
        guard let engine else {
            if let i = currentIndex { load(at: i, autoplay: true) }
            return
        }
        engine.play()
        isPlaying = true
        startTicker()
    }

    func pause() {
        engine?.pause()
        isPlaying = false
        stopTicker()
    }

    func stop() {
        engine?.stop()
        engine = nil
        isPlaying = false
        currentTime = 0
        stopTicker()
    }

    func next(userInitiated: Bool = true) {
        let ctx = contextTracks
        guard !ctx.isEmpty else { return }
        let curID = currentTrack?.id
        let i = ctx.firstIndex(where: { $0.id == curID }) ?? -1

        let target: Track
        if shuffle, ctx.count > 1 {
            var n = Int.random(in: 0..<ctx.count)
            while ctx[n].id == curID { n = Int.random(in: 0..<ctx.count) }
            target = ctx[n]
        } else if i + 1 >= ctx.count {
            // Reached the end. Wrap when the user asks or repeat-all is on;
            // otherwise stop at the end of the context.
            if userInitiated || repeatMode == .all {
                target = ctx[0]
            } else {
                stop()
                return
            }
        } else {
            target = ctx[i + 1]
        }
        playTrack(target)
    }

    func previous() {
        let ctx = contextTracks
        guard !ctx.isEmpty else { return }
        // Restart current track if more than 3s in.
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        let curID = currentTrack?.id
        let i = ctx.firstIndex(where: { $0.id == curID }) ?? 0
        let target = i - 1 < 0 ? ctx[ctx.count - 1] : ctx[i - 1]
        playTrack(target)
    }

    func seek(to time: TimeInterval) {
        guard let engine else { return }
        let clamped = max(0, min(time, engine.duration))
        engine.currentTime = clamped
        currentTime = clamped
    }

    func cycleRepeat() {
        let all = RepeatMode.allCases
        let i = all.firstIndex(of: repeatMode) ?? 0
        repeatMode = all[(i + 1) % all.count]
    }

    // MARK: - Ticker

    private func startTicker() {
        stopTicker()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard let engine, engine.isPlaying else { return }
        currentTime = engine.currentTime
    }
}

extension AudioPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard flag else { return }
            switch repeatMode {
            case .one:
                seek(to: 0)
                play()
            case .all, .off:
                next(userInitiated: false)
            }
        }
    }
}
