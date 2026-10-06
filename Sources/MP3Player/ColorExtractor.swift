import AppKit
import SwiftUI

enum ColorExtractor {
    /// Extracts a small palette of dominant, vivid colors from an image by
    /// downscaling and bucketing pixels in quantized RGB space.
    static func palette(from image: NSImage, count: Int = 6) -> [Color] {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }

        let w = 44, h = 44
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &data, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }

        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        struct Bucket { var r = 0.0, g = 0.0, b = 0.0, n = 0 }
        var buckets: [Int: Bucket] = [:]

        for i in stride(from: 0, to: data.count, by: 4) {
            let a = Int(data[i + 3])
            if a < 32 { continue }
            let r = Int(data[i]), g = Int(data[i + 1]), b = Int(data[i + 2])
            // Quantize to 3 bits per channel (8 levels).
            let key = (r >> 5) << 6 | (g >> 5) << 3 | (b >> 5)
            var bucket = buckets[key] ?? Bucket()
            bucket.r += Double(r); bucket.g += Double(g); bucket.b += Double(b)
            bucket.n += 1
            buckets[key] = bucket
        }

        // Score buckets by frequency, boosted toward more saturated colors.
        let scored = buckets.values.map { bucket -> (color: NSColor, score: Double) in
            let r = bucket.r / Double(bucket.n) / 255
            let g = bucket.g / Double(bucket.n) / 255
            let b = bucket.b / Double(bucket.n) / 255
            let maxC = max(r, g, b), minC = min(r, g, b)
            let sat = maxC == 0 ? 0 : (maxC - minC) / maxC
            let score = Double(bucket.n) * (0.35 + sat)
            return (NSColor(red: r, green: g, blue: b, alpha: 1), score)
        }

        let top = scored.sorted { $0.score > $1.score }.prefix(count)
        return top.map { vivify($0.color) }
    }

    /// Nudges saturation and brightness up so palettes read as luminous scenery
    /// rather than muddy averages.
    private static func vivify(_ color: NSColor) -> Color {
        guard let c = color.usingColorSpace(.deviceRGB) else { return Color(color) }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        // Near-neutral colors (white/gray/black line art) keep their grayscale
        // character instead of getting an invented hue.
        if s < 0.12 {
            return Color(hue: 0, saturation: 0, brightness: min(1, max(0.1, b)))
        }
        s = min(1, s * 1.25 + 0.08)
        b = min(1, max(0.28, b * 1.05))
        return Color(hue: h, saturation: s, brightness: b)
    }

    /// Average perceptual luminance (0 dark … 1 bright) of a palette — used to
    /// decide whether the stage is bright or dark so the sidebar can contrast it.
    static func averageLuminance(of colors: [Color]) -> Double {
        guard !colors.isEmpty else { return 0.5 }
        var sum = 0.0
        for color in colors {
            let ns = NSColor(color).usingColorSpace(.deviceRGB) ?? .gray
            sum += 0.2126 * Double(ns.redComponent)
                 + 0.7152 * Double(ns.greenComponent)
                 + 0.0722 * Double(ns.blueComponent)
        }
        return sum / Double(colors.count)
    }

    /// Calm default world for when nothing is playing.
    static let fallback: [Color] = [
        Color(hue: 0.66, saturation: 0.55, brightness: 0.42),
        Color(hue: 0.72, saturation: 0.5, brightness: 0.5),
        Color(hue: 0.58, saturation: 0.45, brightness: 0.38),
        Color(hue: 0.78, saturation: 0.4, brightness: 0.45),
        Color(hue: 0.5, saturation: 0.4, brightness: 0.4),
        Color(hue: 0.62, saturation: 0.5, brightness: 0.35),
    ]
}
