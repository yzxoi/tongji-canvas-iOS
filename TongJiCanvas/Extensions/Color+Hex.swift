import SwiftUI

// MARK: - Color hex initialiser

extension Color {
    init(hex: UInt32) {
        self.init(
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >>  8) & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255
        )
    }
}

// MARK: - Design tokens

/// Centralised palette + spacing tokens.  Every accent/surface in the app
/// flows from one of these so the design stays coherent when iterated on.
enum Palette {
    /// Primary brand accent — saturated violet used on CTAs, active borders, key icons.
    static let accent       = Color(hex: 0x7C3AED)
    /// One step lighter than `accent` for gradients.
    static let accentLight  = Color(hex: 0x9333EA)
    /// One step deeper than `accent` for emphasis text on light surfaces.
    static let accentDeep   = Color(hex: 0x5B21B6)
    /// Soft tint of `accent` for selected-state backgrounds (`.opacity(0.08–0.15)` zones).
    static let accentMuted  = Color(hex: 0xB8A2FF)
    /// Pale accent surface for hero panels, info chips.
    static let accentSurface = Color(hex: 0xF3EFFF)

    /// Linear gradient used on the primary CTA in the floating dock.
    static let accentGradient = LinearGradient(
        colors: [accent, accentLight],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Diagonal gradient used on hero headers (About, success screens).
    static let heroGradient = LinearGradient(
        colors: [accent, accentLight],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

enum Radius {
    static let card:  CGFloat = 24
    static let panel: CGFloat = 20
    static let inner: CGFloat = 16
    static let pill:  CGFloat = 999
}

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 28
}
