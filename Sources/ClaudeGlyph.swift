import AppKit

/// The Claude burst mark, drawn as vectors.
///
/// There's no official Claude icon asset on this machine to link against, so
/// this is a hand-built approximation: eleven rays of alternating length with
/// round caps, which is what the mark reads as at menu bar sizes. Drop a PNG at
/// `~/Library/Application Support/ClaudeUsage/menubar-icon.png` to override it
/// with the real artwork.
enum ClaudeGlyph {
    private static let rayCount = 11
    // The short rays need to clear the solid centre the eleven round caps form,
    // which on a 1x display is only a couple of pixels across.
    private static let lengths: [CGFloat] = [1.0, 0.72]
    private static let widthRatio: CGFloat = 0.09

    static var customIconURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/ClaudeUsage/menubar-icon.png")
    }

    /// Menu bar image — a template so macOS tints it for light/dark and for the
    /// highlighted state automatically.
    static func statusBarImage(size: CGFloat = 17) -> NSImage {
        if let custom = loadCustomIcon(size: size) { return custom }

        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            draw(in: rect)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func loadCustomIcon(size: CGFloat) -> NSImage? {
        guard let image = NSImage(contentsOf: customIconURL) else { return nil }
        image.size = NSSize(width: size, height: size)
        image.isTemplate = true
        return image
    }

    private static func draw(in rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let size = min(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let lineWidth = size * widthRatio
        // Inset by half the line width so the round caps don't clip.
        let radius = size / 2 - lineWidth / 2

        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setLineCap(.round)
        ctx.setLineWidth(lineWidth)

        for i in 0..<rayCount {
            let angle = (CGFloat(i) / CGFloat(rayCount)) * .pi * 2 - .pi / 2
            let length = radius * lengths[i % lengths.count]
            ctx.move(to: center)
            ctx.addLine(to: CGPoint(x: center.x + cos(angle) * length,
                                    y: center.y + sin(angle) * length))
            ctx.strokePath()
        }
    }
}
