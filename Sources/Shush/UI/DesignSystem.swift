import AppKit
import SwiftUI

/// The design system for Shush — a flat sidebar-nav app, from the Pencil design at
/// `shush_app.pen` (Dashboard / Transcripts / Dictionary / Settings, persistent left
/// sidebar, blue accent on white/light-gray surfaces). Replaces the earlier hardware-panel
/// direction entirely.
///
/// Every value a view needs lives here; components never declare their own colors, sizes,
/// radii or durations.
enum DS {

    // MARK: - Color

    /// Light/dark pairs straight from the Pencil file's variables (`shush_app.pen`, themed
    /// `mode: light/dark` values). Resolved per-appearance via `face(light:dark:)`, so every
    /// token below tracks whichever appearance the window is actually drawing in —
    /// including an explicit override from `Settings.appearance` (wired through
    /// `.preferredColorScheme` at the window root), not just the system setting.
    enum Color {
        static let background = face(light: 0xFFFFFF, dark: 0x0F172A)
        static let surface = face(light: 0xF9FAFB, dark: 0x1E293B)
        static let surfaceSecondary = face(light: 0xEFEFEF, dark: 0x334155)
        static let sidebarBackground = face(light: 0xF3F4F6, dark: 0x1A202C)

        static let textPrimary = face(light: 0x1A1A1A, dark: 0xF1F5F9)
        static let textSecondary = face(light: 0x666666, dark: 0xCBD5E1)
        static let textTertiary = face(light: 0x999999, dark: 0x94A3B8)

        static let border = face(light: 0xE5E5E5, dark: 0x334155)
        static let divider = face(light: 0xEFEFEF, dark: 0x334155)

        static let primary = face(light: 0x3B82F6, dark: 0x60A5FA)
        /// No dark value in the source file (it's a flat `#DBEAFE`) — a muted dark-blue tint
        /// keeps the same "selected nav row" role without a pale swatch glaring on a dark
        /// sidebar.
        static let primaryLight = face(light: 0xDBEAFE, dark: 0x1E3A5F)

        /// Nominal / positive — used sparingly, e.g. a "fastest" badge. Not themed in the
        /// source file; same in both appearances.
        static let success = SwiftUI.Color(hex: 0x22C55E)
        static let warning = SwiftUI.Color(hex: 0xF59E0B)
        static let danger = SwiftUI.Color(hex: 0xEF4444)
        /// Two extra accents, dashboard-only — distinguishing five-plus metric tiles at a
        /// glance needs more hues than the four semantic colors above cover.
        static let purple = SwiftUI.Color(hex: 0x8B5CF6)
        static let rose = SwiftUI.Color(hex: 0xF43F5E)

        /// Resolves to the light or dark value for whatever appearance is actually active —
        /// the window's, not necessarily `NSApp`'s, so `.preferredColorScheme` overrides work.
        private static func face(light: UInt32, dark: UInt32) -> SwiftUI.Color {
            SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(hex: isDark ? dark : light)
            })
        }
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

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// The waveform brand mark, shared by the sidebar and the menu bar item — replaces the
/// "Shush" wordmark and the placeholder SF Symbol respectively.
struct BrandMark: View {
    var body: some View {
        if let url = Bundle.main.url(forResource: "BrandMark", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "waveform")
        }
    }
}

/// Menu bar glyph — a template image so AppKit tints it to match the light/dark menu bar,
/// same as any SF Symbol would.
struct StatusBarIcon: View {
    /// Shared with the manual `NSStatusItem` in `AppDelegate`, which needs the raw image to
    /// set on its button directly rather than through a SwiftUI label.
    static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "StatusBarIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }()

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image)
        } else {
            Image(systemName: "waveform")
        }
    }
}
