import SwiftUI
import AppKit

/// A self-driven animation clock. TimelineView(.animation) does not reliably
/// tick in this Swift-package app, so we advance time with a main-run-loop
/// Timer — the same mechanism the playback scrubber uses.
@MainActor
final class AnimationClock: ObservableObject {
    @Published var t: TimeInterval = 0
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        let step = 1.0 / 30.0
        let timer = Timer(timeInterval: step, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.t += step
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}

/// A living mesh-gradient backdrop derived from the current track's artwork.
/// The interior control points drift continuously so the color churns like a
/// slow lava lamp — giving the Liquid Glass on top something alive to refract.
struct WorldView: View {
    let palette: [Color]
    let artwork: NSImage?

    @StateObject private var clock = AnimationClock()

    var body: some View {
        let t = clock.t
        ZStack {
            MeshGradient(
                width: 3,
                height: 3,
                points: points(at: t),
                colors: meshColors,
                smoothsColors: true
            )
            // The record as scenery: a slowly drifting bloom of the cover,
            // giving the Liquid Glass real organic structure to refract.
            artworkScenery(at: t)
            // Soft drifting light for extra depth behind the glass.
            lightBlobs(at: t)
            // Deepen the edges so floating controls stay legible.
            RadialGradient(
                colors: [.clear, .black.opacity(0.4)],
                center: .center, startRadius: 180, endRadius: 640
            )
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 1.4), value: palette)
        .onAppear { clock.start() }
    }

    @ViewBuilder
    private func artworkScenery(at time: TimeInterval) -> some View {
        if let artwork {
            let t = time
            Image(nsImage: artwork)
                .resizable()
                .scaledToFill()
                .scaleEffect(1.35 + CGFloat(sin(t * 0.04)) * 0.06)
                .rotationEffect(.degrees(sin(t * 0.02) * 3))
                .blur(radius: 26)
                .opacity(0.55)
        }
    }

    private func lightBlobs(at time: TimeInterval) -> some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let t = time
            ZStack {
                blob(0.12, 460)
                    .position(x: w * 0.32 + CGFloat(sin(t * 0.13)) * 90,
                              y: h * 0.34 + CGFloat(cos(t * 0.11)) * 70)
                blob(0.08, 380)
                    .position(x: w * 0.72 + CGFloat(sin(t * 0.09 + 2)) * 100,
                              y: h * 0.70 + CGFloat(cos(t * 0.15 + 1)) * 60)
                blob(0.06, 300)
                    .position(x: w * 0.55 + CGFloat(cos(t * 0.1 + 4)) * 110,
                              y: h * 0.2 + CGFloat(sin(t * 0.12 + 3)) * 55)
            }
        }
    }

    private func blob(_ opacity: Double, _ size: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(
                colors: [.white.opacity(opacity), .clear],
                center: .center, startRadius: 0, endRadius: size / 2
            ))
            .frame(width: size, height: size)
            .blur(radius: 30)
    }

    /// Nine mesh colors arranged so adjacent corners differ. Cycles the palette.
    private var meshColors: [Color] {
        let p = palette.isEmpty ? ColorExtractor.fallback : palette
        let order = [0, 2, 4, 1, 3, 5, 2, 4, 0]
        return order.map { p[$0 % p.count] }
    }

    /// Corners pinned; edge midpoints slide along their edge; center roams —
    /// so the mesh warps without ever tearing a gap at the border.
    private func points(at time: TimeInterval) -> [SIMD2<Float>] {
        let t = Float(time)
        func w(_ seed: Float, _ amp: Float, _ speed: Float) -> Float {
            amp * sin(t * speed + seed)
        }
        let topX = 0.5 + w(0.0, 0.28, 0.60)
        let botX = 0.5 + w(1.7, 0.28, 0.52)
        let leftY = 0.5 + w(3.1, 0.26, 0.56)
        let rightY = 0.5 + w(4.6, 0.26, 0.46)
        let cx = 0.5 + w(2.2, 0.25, 0.70)
        let cy = 0.5 + w(5.3, 0.25, 0.64)

        return [
            SIMD2(0, 0),      SIMD2(topX, 0),   SIMD2(1, 0),
            SIMD2(0, leftY),  SIMD2(cx, cy),    SIMD2(1, rightY),
            SIMD2(0, 1),      SIMD2(botX, 1),   SIMD2(1, 1),
        ]
    }
}
