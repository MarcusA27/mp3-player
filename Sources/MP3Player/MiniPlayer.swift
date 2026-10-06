import SwiftUI
import AppKit
import Carbon

// MARK: - Global hotkey

private func fourCharCode(_ s: String) -> FourCharCode {
    var result: FourCharCode = 0
    for ch in s.utf16.prefix(4) { result = (result << 8) + FourCharCode(ch) }
    return result
}

/// A system-wide hotkey via Carbon's RegisterEventHotKey — fires no matter which
/// app is frontmost, including over another app's fullscreen space, and needs no
/// Accessibility permission.
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                if let userData {
                    Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue().action()
                }
                return noErr
            },
            1, &eventType, selfPtr, &handlerRef
        )

        let hotKeyID = EventHotKeyID(signature: fourCharCode("MPLY"), id: 1)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

// MARK: - Mini player window

/// Owns the floating mini-player panel and the ⌥⌘M hotkey that toggles it.
@MainActor
final class MiniPlayerController: ObservableObject {
    private var panel: NSPanel?
    private var hotKey: GlobalHotKey?
    private weak var player: AudioPlayer?

    func configure(player: AudioPlayer) {
        guard hotKey == nil else { return }
        self.player = player
        hotKey = GlobalHotKey(
            keyCode: UInt32(kVK_ANSI_M),
            modifiers: UInt32(cmdKey | optionKey)
        ) { [weak self] in
            Task { @MainActor in self?.toggle() }
        }
    }

    func toggle() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            present()
        }
    }

    private func present() {
        if panel == nil { build() }
        position()
        panel?.orderFrontRegardless()
    }

    private func build() {
        guard let player else { return }
        let hosting = NSHostingView(rootView: MiniPlayerView().environmentObject(player))
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 160),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        // Above the menu bar so it rides over fullscreen content...
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        // ...and present on every space, including other apps' fullscreen spaces,
        // without pulling the user out of them.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.contentView = hosting
        self.panel = panel
    }

    private func position() {
        guard let panel, let screen = NSScreen.main else { return }
        let visible = screen.frame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 90))
    }
}

// MARK: - Mini player view

private struct MiniPlayerView: View {
    @EnvironmentObject private var player: AudioPlayer

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 26) {
                Button { player.previous() } label: {
                    Image(systemName: "backward.fill").font(.system(size: 15))
                }
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 22)
                }
                Button { player.next() } label: {
                    Image(systemName: "forward.fill").font(.system(size: 15))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .disabled(player.tracks.isEmpty)
            .frame(width: 300)
            .padding(.vertical, 8)
            .background { glassCapsule }

            MiniScrubber().frame(width: 330)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(width: 380, height: 100)
        .background { backdrop }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
        .padding(30)
    }

    /// A static stand-in for Liquid Glass: SwiftUI's real .glassEffect only
    /// activates when its window is key, and this panel is deliberately
    /// non-activating (so it floats over other apps without stealing focus).
    /// So we paint the glassy look ourselves — tint, dots, a top sheen, and a
    /// rim highlight — which reads the same whether or not the panel is focused.
    private var glassCapsule: some View {
        ZStack {
            Capsule().fill(.black.opacity(0.22))
            DotField(luminance: player.stageLuminance, active: player.isPlaying)
                .opacity(0.32)
                .clipShape(.capsule)
            Capsule().fill(
                LinearGradient(
                    colors: [.white.opacity(0.12), .white.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom
                )
            )
        }
        .overlay(
            Capsule().strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.4), .white.opacity(0.08)],
                    startPoint: .top, endPoint: .bottom
                ),
                lineWidth: 1
            )
        )
        .allowsHitTesting(false)
    }

    /// A dark, blurred bloom of the cover — the same "world" the in-app bar sits
    /// on, so the glass and dots read the same way here.
    private var backdrop: some View {
        ZStack {
            if let art = player.currentTrack?.artwork {
                Image(nsImage: art)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 30)
                    .opacity(0.7)
            } else {
                Color.black
            }
            Rectangle().fill(.black.opacity(0.4))
        }
    }
}

/// A slim, draggable progress bar — the transport scrubber shrunk down for the
/// mini player.
private struct MiniScrubber: View {
    @EnvironmentObject private var player: AudioPlayer
    @State private var dragging = false
    @State private var dragValue: Double = 0

    var body: some View {
        let dur = max(player.duration, 0.01)
        let cur = dragging ? dragValue : player.currentTime
        let frac = min(max(cur / dur, 0), 1)

        HStack(spacing: 7) {
            Text(timeString(cur))
                .frame(width: 28, alignment: .leading)
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.22)).frame(height: 3)
                    Capsule().fill(.white.opacity(0.9)).frame(width: w * frac, height: 3)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            dragging = true
                            dragValue = min(max(Double(g.location.x / w), 0), 1) * dur
                        }
                        .onEnded { _ in
                            player.seek(to: dragValue)
                            dragging = false
                        }
                )
            }
            .frame(height: 12)
            Text("-" + timeString(max(dur - cur, 0)))
                .frame(width: 32, alignment: .trailing)
        }
        .font(.system(size: 9).monospacedDigit())
        .foregroundStyle(.white.opacity(0.55))
    }
}
