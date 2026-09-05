import AppKit
import CoreGraphics

public enum ProfileMenuIconRenderer {
    public static let iconSize = NSSize(width: 14, height: 14)

    public static func image(for color: ProfileColor) -> NSImage {
        let scale = 2
        let pixelWidth = Int(iconSize.width) * scale
        let pixelHeight = Int(iconSize.height) * scale
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: pixelWidth,
                  height: pixelHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: pixelWidth * 4,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                      | CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return configuredImage(NSImage(size: iconSize))
        }
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        let swatchBounds = CGRect(
            x: scale,
            y: scale,
            width: pixelWidth - (scale * 2),
            height: pixelHeight - (scale * 2)
        )
        let swatch = CGPath(
            roundedRect: swatchBounds,
            cornerWidth: 3 * CGFloat(scale),
            cornerHeight: 3 * CGFloat(scale),
            transform: nil
        )
        context.addPath(swatch)
        context.setFillColor(
            red: color.red,
            green: color.green,
            blue: color.blue,
            alpha: color.alpha
        )
        context.fillPath()

        context.addPath(swatch)
        context.setStrokeColor(red: 0, green: 0, blue: 0, alpha: 0.16)
        context.setLineWidth(0.75 * CGFloat(scale))
        context.strokePath()

        guard let renderedImage = context.makeImage() else {
            return configuredImage(NSImage(size: iconSize))
        }
        return configuredImage(NSImage(cgImage: renderedImage, size: iconSize))
    }

    private static func configuredImage(_ image: NSImage) -> NSImage {
        image.isTemplate = false
        image.accessibilityDescription = String(localized: "Profile color")
        return image
    }
}

public enum StatusBarIconRenderer {
    public static let iconSize = NSSize(width: 18, height: 18)
    private static let opticalVerticalOffset: CGFloat = 0.5

    public static func image() -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        guard let symbol = NSImage(
            systemSymbolName: "rectangle.3.group",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(configuration) else {
            return configuredImage(NSImage(size: iconSize))
        }

        let image = NSImage(size: iconSize, flipped: false) { bounds in
            let scale = min(
                bounds.width / symbol.size.width,
                bounds.height / symbol.size.height
            )
            let renderedSize = NSSize(
                width: symbol.size.width * scale,
                height: symbol.size.height * scale
            )
            let renderedRect = NSRect(
                x: bounds.midX - (renderedSize.width / 2),
                y: bounds.midY - (renderedSize.height / 2) + opticalVerticalOffset,
                width: renderedSize.width,
                height: renderedSize.height
            )
            symbol.draw(
                in: renderedRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
            return true
        }

        return configuredImage(image)
    }

    private static func configuredImage(_ image: NSImage) -> NSImage {
        image.alignmentRect = NSRect(origin: .zero, size: iconSize)
        image.isTemplate = true
        return image
    }
}
