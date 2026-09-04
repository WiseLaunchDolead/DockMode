import Foundation

public struct DockPreviewLayoutMetrics: Equatable, Sendable {
    public let iconSize: Double
    public let contentWidth: Double
    public let fitsWithoutScrolling: Bool

    public init(iconSize: Double, contentWidth: Double, fitsWithoutScrolling: Bool) {
        self.iconSize = iconSize
        self.contentWidth = contentWidth
        self.fitsWithoutScrolling = fitsWithoutScrolling
    }
}

public enum DockPreviewLayoutCalculator {
    public static let minimumIconSize = 30.0
    public static let maximumIconSize = 58.0

    public static func metrics(
        for items: [DockItem],
        availableWidth: Double
    ) -> DockPreviewLayoutMetrics {
        let iconSize = preferredIconSize(for: items, availableWidth: availableWidth)
        let contentWidth = requiredWidth(for: items, iconSize: iconSize)
        return DockPreviewLayoutMetrics(
            iconSize: iconSize,
            contentWidth: contentWidth,
            fitsWithoutScrolling: contentWidth <= availableWidth
        )
    }

    public static func requiredWidth(for items: [DockItem], iconSize: Double) -> Double {
        guard !items.isEmpty else { return 0 }

        let itemWidths = items.reduce(0.0) { partial, item in
            let minimumHitWidth = max(30, iconSize * 0.52)
            let contentWidth: Double
            switch item.content {
            case .application:
                contentWidth = iconSize
            case .spacer(.compact):
                contentWidth = max(12, iconSize * 0.28)
            case .spacer(.regular):
                contentWidth = max(24, iconSize * 0.55)
            case .spacer(.flexible):
                contentWidth = max(44, iconSize * 0.9)
            }
            return partial + max(minimumHitWidth, contentWidth) + 8
        }

        let spacing = max(5, iconSize * 0.10)
        let spacingCount = Double(items.count)
        let fixedHorizontalSpace = 32.0 + 36.0 + 20.0
        return fixedHorizontalSpace + itemWidths + (spacing * spacingCount)
    }

    private static func preferredIconSize(
        for items: [DockItem],
        availableWidth: Double
    ) -> Double {
        guard !items.isEmpty else { return 54 }

        if requiredWidth(for: items, iconSize: maximumIconSize) <= availableWidth {
            return maximumIconSize
        }
        guard requiredWidth(for: items, iconSize: minimumIconSize) <= availableWidth else {
            return minimumIconSize
        }

        var lowerBound = minimumIconSize
        var upperBound = maximumIconSize
        for _ in 0..<24 {
            let candidate = (lowerBound + upperBound) / 2
            if requiredWidth(for: items, iconSize: candidate) <= availableWidth {
                lowerBound = candidate
            } else {
                upperBound = candidate
            }
        }
        return lowerBound
    }
}
