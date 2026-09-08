import SwiftUI

/// The design system for Shosh — a flat sidebar-nav app, from the Pencil design at
/// `shosh_app.pen` (Dashboard / Transcripts / Dictionary / Settings, persistent left
/// sidebar, blue accent on white/light-gray surfaces). Replaces the earlier hardware-panel
/// direction entirely.
///
/// Every value a view needs lives here; components never declare their own colors, sizes,
/// radii or durations.
enum DS {

    // MARK: - Color

    enum Color {
        static let background = SwiftUI.Color(hex: 0xFFFFFF)
        static let surface = SwiftUI.Color(hex: 0xF9FAFB)
        static let surfaceSecondary = SwiftUI.Color(hex: 0xEFEFEF)
        static let sidebarBackground = SwiftUI.Color(hex: 0xF3F4F6)

        static let textPrimary = SwiftUI.Color(hex: 0x1A1A1A)
        static let textSecondary = SwiftUI.Color(hex: 0x666666)
        static let textTertiary = SwiftUI.Color(hex: 0x999999)

        static let border = SwiftUI.Color(hex: 0xE5E5E5)
        static let divider = SwiftUI.Color(hex: 0xEFEFEF)

        static let primary = SwiftUI.Color(hex: 0x3B82F6)
        static let primaryLight = SwiftUI.Color(hex: 0xDBEAFE)

        /// Nominal / positive — used sparingly, e.g. a "fastest" badge.
        static let success = SwiftUI.Color(hex: 0x22C55E)
        static let warning = SwiftUI.Color(hex: 0xF59E0B)
        static let danger = SwiftUI.Color(hex: 0xEF4444)
    }

    // MARK: - Type

    /// System font stands in for the design's Inter — same geometric-grotesque proportions,
    /// zero-cost (no bundling), and matches every size in the source design 1:1.
    enum Font {
        static func regular(_ size: CGFloat) -> SwiftUI.Font { .system(size: size, weight: .regular) }
        static func medium(_ size: CGFloat) -> SwiftUI.Font { .system(size: size, weight: .medium) }
        static func semibold(_ size: CGFloat) -> SwiftUI.Font { .system(size: size, weight: .semibold) }
        static func bold(_ size: CGFloat) -> SwiftUI.Font { .system(size: size, weight: .bold) }

        static let logo = bold(20)
        static let pageTitle = semibold(20)
        static let navLabel = medium(13)
        static let sectionHeader = medium(11)
        static let label = medium(13)
        static let value = regular(13)
        static let body = regular(13)
        static let meta = regular(11)
        static let button = medium(12)
        static let metricValue = bold(32)
        static let metricTitle = medium(12)
        static let metricSubtitle = regular(11)
        static let streakNumber = bold(36)

        static let counter = SwiftUI.Font.system(size: 14, design: .monospaced).monospacedDigit()
    }

    // MARK: - Spacing

    enum Space {
        static let hair: CGFloat = 2
        static let tight: CGFloat = 4
        static let snug: CGFloat = 8
        static let base: CGFloat = 12
        static let roomy: CGFloat = 16
        static let wide: CGFloat = 20
        static let section: CGFloat = 24
        static let panel: CGFloat = 32
    }

    // MARK: - Radius

    enum Radius {
        static let none: CGFloat = 0
        static let chip: CGFloat = 6
        static let control: CGFloat = 8
        static let card: CGFloat = 12
        static let pill: CGFloat = 999
    }

    // MARK: - Border

    enum Border {
        static let hairline: CGFloat = 1
    }

    // MARK: - Motion

    enum Motion {
        static let fast = Animation.easeOut(duration: 0.12)
        static let base = Animation.easeInOut(duration: 0.18)
    }
}

private extension SwiftUI.Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
