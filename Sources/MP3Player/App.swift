import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct MP3PlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var player = AudioPlayer()

    var body: some Scene {
        WindowGroup("Player") {
            ContentView()
                .environmentObject(player)
                .frame(width: 828, height: 595)
                .background(WindowConfigurator(cornerRadius: 12))
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Files…") {
                    NotificationCenter.default.post(name: .openFilesRequested, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandMenu("Playback") {
                Button("Play / Pause") { player.togglePlayPause() }
                    .keyboardShortcut(.space, modifiers: [])
                Button("Next") { player.next() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                Button("Previous") { player.previous() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let openFilesRequested = Notification.Name("openFilesRequested")
}

/// Reaches the hosting NSWindow to apply custom rounded corners.
struct WindowConfigurator: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            if let content = window.contentView {
                content.wantsLayer = true
                content.layer?.cornerRadius = cornerRadius
                content.layer?.masksToBounds = true
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
