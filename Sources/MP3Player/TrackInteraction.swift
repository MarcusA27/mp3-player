import SwiftUI
import AppKit

/// AppKit-backed interaction layer for a track row. Lets a drag start from
/// anywhere on the row while keeping the drag image (the album cover) centered
/// on the cursor — SwiftUI's `.draggable` can't do this, as it anchors the
/// preview to the source view's center. Because an overlay must own all mouse
/// handling, it also carries click-to-play, hover, and the right-click menu.
struct TrackInteraction: NSViewRepresentable {
    let idString: String
    let cover: NSImage?
    let onClick: @MainActor () -> Void
    let onHover: @MainActor (Bool) -> Void
    let makeMenu: @MainActor () -> NSMenu

    func makeNSView(context: Context) -> TrackInteractionNSView {
        let view = TrackInteractionNSView()
        view.update(idString: idString, cover: cover, onClick: onClick, onHover: onHover, makeMenu: makeMenu)
        return view
    }

    func updateNSView(_ nsView: TrackInteractionNSView, context: Context) {
        nsView.update(idString: idString, cover: cover, onClick: onClick, onHover: onHover, makeMenu: makeMenu)
    }
}

final class TrackInteractionNSView: NSView, NSDraggingSource {
    private var idString = ""
    private var cover: NSImage?
    private var onClick: @MainActor () -> Void = {}
    private var onHover: @MainActor (Bool) -> Void = { _ in }
    private var makeMenu: @MainActor () -> NSMenu = { NSMenu() }

    private var downPoint: NSPoint = .zero
    private var dragging = false
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    func update(
        idString: String,
        cover: NSImage?,
        onClick: @escaping @MainActor () -> Void,
        onHover: @escaping @MainActor (Bool) -> Void,
        makeMenu: @escaping @MainActor () -> NSMenu
    ) {
        self.idString = idString
        self.cover = cover
        self.onClick = onClick
        self.onHover = onHover
        self.makeMenu = makeMenu
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }

    override func mouseDown(with event: NSEvent) {
        downPoint = convert(event.locationInWindow, from: nil)
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragging else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - downPoint.x, point.y - downPoint.y) > 4 else { return }
        dragging = true

        let item = NSPasteboardItem()
        item.setString(idString, forType: .string)
        let dragItem = NSDraggingItem(pasteboardWriter: item)
        let size = NSSize(width: 48, height: 48)
        let frame = NSRect(
            x: downPoint.x - size.width / 2,
            y: downPoint.y - size.height / 2,
            width: size.width,
            height: size.height
        )
        dragItem.setDraggingFrame(frame, contents: dragImage(size))
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if !dragging { onClick() }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        makeMenu()
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation { .copy }

    private func dragImage(_ size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        let rect = NSRect(origin: .zero, size: size)
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).addClip()
        if let cover {
            // Center-crop the (possibly non-square) cover to a square source rect.
            let side = min(cover.size.width, cover.size.height)
            let src = NSRect(
                x: (cover.size.width - side) / 2,
                y: (cover.size.height - side) / 2,
                width: side, height: side
            )
            cover.draw(in: rect, from: src, operation: .copy, fraction: 1)
        } else {
            NSColor.white.withAlphaComponent(0.12).setFill()
            rect.fill()
        }
        image.unlockFocus()
        return image
    }
}

/// An NSMenuItem that runs a closure when selected.
final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void
    init(title: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @MainActor @objc private func fire() { handler() }
}
