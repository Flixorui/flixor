//
//  BackdropColorExtractor.swift
//  FlixorMac
//
//  Dominant color of a backdrop image, for tinting the details page. Works for
//  any image URL, so it doesn't need a Plex server.
//

import AppKit
import SwiftUI

struct BackdropRGB: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }

    /// The page tint: mostly the theme background, moved toward this color, and
    /// kept dark enough for white text.
    func pageTint(over background: BackdropRGB) -> BackdropRGB {
        let fraction = 0.42
        var tint = BackdropRGB(
            red: background.red + (red - background.red) * fraction,
            green: background.green + (green - background.green) * fraction,
            blue: background.blue + (blue - background.blue) * fraction
        )
        let luminance = 0.2126 * tint.red + 0.7152 * tint.green + 0.0722 * tint.blue
        let maxLuminance = 0.13
        if luminance > maxLuminance {
            let scale = maxLuminance / luminance
            tint = BackdropRGB(red: tint.red * scale, green: tint.green * scale, blue: tint.blue * scale)
        }
        return tint
    }

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init?(_ color: Color) {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        self.init(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
    }
}

enum BackdropColorExtractor {
    private final class Box: NSObject {
        let value: BackdropRGB
        init(_ value: BackdropRGB) { self.value = value }
    }

    private static let cache = NSCache<NSURL, Box>()

    /// Nil when the image can't be loaded or is almost entirely black or white.
    static func dominantColor(for url: URL) async -> BackdropRGB? {
        if let cached = cache.object(forKey: url as NSURL) { return cached.value }
        let task = Task.detached(priority: .utility) { () -> BackdropRGB? in
            guard let image = await loadImage(url),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            return dominantColor(of: cgImage)
        }
        guard let result = await task.value else { return nil }
        cache.setObject(Box(result), forKey: url as NSURL)
        return result
    }

    /// Through ImageCache, so it shares the download the backdrop view starts.
    private static func loadImage(_ url: URL) async -> NSImage? {
        try? await ImageCache.shared.load(url: url).image
    }

    /// Groups the pixels of a tiny copy of the image into color buckets, counting
    /// vivid pixels for more, and averages the winning bucket.
    private static func dominantColor(of image: CGImage) -> BackdropRGB? {
        let width = 48
        let height = 27
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: buffer.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                  ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        struct Bucket { var weight = 0.0; var red = 0.0; var green = 0.0; var blue = 0.0 }
        var buckets: [Int: Bucket] = [:]
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let r = Int(pixels[offset]), g = Int(pixels[offset + 1]), b = Int(pixels[offset + 2])
            let high = max(r, g, b)
            guard high > 24 else { continue }
            let saturation = Double(high - min(r, g, b)) / Double(high)
            if high > 240 && saturation < 0.1 { continue }

            let weight = 0.25 + saturation
            let key = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4)
            var bucket = buckets[key, default: Bucket()]
            bucket.weight += weight
            bucket.red += Double(r) * weight
            bucket.green += Double(g) * weight
            bucket.blue += Double(b) * weight
            buckets[key] = bucket
        }

        guard let best = buckets.values.max(by: { $0.weight < $1.weight }) else { return nil }
        return BackdropRGB(
            red: best.red / best.weight / 255,
            green: best.green / best.weight / 255,
            blue: best.blue / best.weight / 255
        )
    }
}
