import AppKit
import DockModeCore
import SwiftUI

extension Color {
    init(profileColor: ProfileColor) {
        self.init(
            .sRGB,
            red: profileColor.red,
            green: profileColor.green,
            blue: profileColor.blue,
            opacity: profileColor.alpha
        )
    }
}

extension ProfileColor {
    init(swiftUIColor: Color) {
        let nsColor = NSColor(swiftUIColor).usingColorSpace(.sRGB) ?? .systemBlue
        self.init(
            red: Double(nsColor.redComponent),
            green: Double(nsColor.greenComponent),
            blue: Double(nsColor.blueComponent),
            alpha: Double(nsColor.alphaComponent)
        )
    }
}
