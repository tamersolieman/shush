import SwiftUI

/// The design system for Shosh — ported from the Tamer Solieman Design System
/// (tamersolieman.com: `src/app/(site)/globals.css`, public front end only).
///
/// Every value a view needs lives here; components never declare their own colors, sizes,
/// radii or durations. The physical control metaphor (panels, wells, screws, VU needle) stays
/// — see `Equipment.swift` — but every color, type, spacing, radius, shadow and motion value
/// below is now a direct port of that system's tokens, not an invented "equipment" palette.
///
/// Two faces: light and dark, switched by appearance rather than `[data-theme]`, since macOS
/// has no in-app theme toggle equivalent to the site's. Same tokens, same names either way.
///
/// - One primary accent: `accent-primary` (blue), for selection and focus.
/// - `record` uses the system's `danger` token — the one place red appears, matching its
///   semantic role (the recording lamp is a state indicator, not decoration).
enum DS {

    // MARK: - Color

    /// Surfaces, from the outer body inward. `Face` resolves each to light or dark based on
    /// the current appearance.
    enum Color {
        /// The outer body of the unit — `--surface-canvas`.
        static let chassis = face(light: 0xF7F8F9, dark: 0x14181B)

        /// The main working surface — `--surface-card`.
        static let panel = face(light: 0xFFFFFF, dark: 0x1D2328)

        /// Top bevel highlight on a raised element — `--border-subtle`.
        static let panelHighlight = face(light: 0xE8ECEF, dark: 0x3A444C)

        /// Bottom bevel shade on a raised element — `--border-default`.
        static let panelShade = face(light: 0xC7D0D6, dark: 0x5A6873)

        /// Recessed wells — where lists, meters and readouts sit — `--surface-raised`.
        static let well = face(light: 0xE8ECEF, dark: 0x262E34)

        /// The dark window of a readout. Backdrop for readouts and the transcript list.
        /// Always dark regardless of face — `neutral-900` / `neutral-950`.
        static let deck = face(light: 0x1D2328, dark: 0x14181B)

        /// Button caps and other raised controls — `--surface-card` / `--surface-raised`.
        static let cap = face(light: 0xFFFFFF, dark: 0x262E34)

        /// The hard line where two panels meet — `--border-default`.
        static let seam = face(light: 0xC7D0D6, dark: 0x5A6873)

        // Text
        /// Primary readable text — `--text-primary`.
        static let ink = face(light: 0x14181B, dark: 0xF7F8F9)
        /// Supporting text — timings, counts, secondary rows — `--text-secondary`.
        static let inkSecondary = face(light: 0x5A6873, dark: 0xC7D0D6)
        /// Silkscreened panel labels — `--text-tertiary`.
        static let silkscreen = face(light: 0x687687, dark: 0xA3B0B9)
        /// Text on a dark readout well, regardless of face.
        static let inkOnDeck = swatch(0xF7F8F9)

        // Accent — the system's single primary accent, blue.
        /// The record lamp — `--danger`. The one deliberate red, semantic not decorative.
        static let record = swatch(0xC94F44)
        /// The lamp when unlit — a dark, desaturated lens.
        static let recordIdle = face(light: 0xD9B3AF, dark: 0x4A2E2C)

        /// A selected row — the panel lifts rather than tints — `--surface-raised`.
        static let selection = face(light: 0xE8ECEF, dark: 0x262E34)
        /// Edge on a selected or focused element — `--accent-primary`.
        static let selectionEdge = face(light: 0x2E739E, dark: 0x3B8FC4)
        /// Keyboard focus ring — `--focus-ring`.
        static let focusRing = face(light: 0x3B8FC4, dark: 0x7FBFE0)
        /// Row under the pointer, before selection — `--border-subtle`.
        static let hover = face(light: 0xE8ECEF, dark: 0x3A444C)

        // Instrumentation only. Never use these for UI chrome.
        /// VU meter face — `neutral-100`.
        static let meterFace = swatch(0xE8ECEF)
        /// The amber lamp behind a VU face — `amber-500`.
        static let meterLamp = swatch(0xD99A3E)
        /// Needle and scale printing — `neutral-950`.
        static let meterNeedle = swatch(0x14181B)
        /// Nominal level — `--success`.
        static let meterGreen = swatch(0x3F9D6D)
        /// Approaching peak — `amber-600`.
        static let meterAmber = swatch(0xB97B28)
        /// Over — `--danger`.
        static let meterRed = swatch(0xC94F44)

        // MARK: Face resolution

        private static func swatch(_ hex: UInt32) -> SwiftUI.Color { SwiftUI.Color(hex: hex) }

        /// Resolves to the light or dark value for the current appearance.
        private static func face(light: UInt32, dark: UInt32) -> SwiftUI.Color {
            SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(hex: isDark ? dark : light)
            })
        }
    }

    // MARK: - Material

    /// The physical detail that makes a panel read as a machined object rather than a filled
    /// rectangle. Structural, not part of the brand system — colors and sizes are still drawn
    /// from `Color`, `Space` and `Border` above/below.
    enum Material {
        // Brushed grain. Anisotropic: fine horizontal striations across the panel.
        static let grainLight: Double = 0.03
        static let grainDark: Double = 0.04
        static let grainPitch: CGFloat = 2
        static let grainAngle: Angle = .degrees(0)

        // Fasteners
        static let screwSize: CGFloat = 9
        static let screwInset: CGFloat = 10

        // Ventilation
        static let ventSlotWidth: CGFloat = 3
        static let ventSlotHeight: CGFloat = 22
        static let ventSlotGap: CGFloat = 4
        static let ventRadius: CGFloat = 1.5

        // Indicator lamps — small, hard-edged, lit from behind a lens.
        static let lampSize: CGFloat = 7
        static let lampSpecular: Double = 0.45
        static let lampUnlitOpacity: Double = 0.22

        // Segmented readout — the tape counter and timings.
        static let segmentThickness: CGFloat = 3
        static let segmentGap: CGFloat = 1
        static let segmentGhostOpacity: Double = 0.12

        // Transport keys — rectangular, wide, with real travel.
        static let keyHeight: CGFloat = 34
        static let keyMinWidth: CGFloat = 52
        static let keyTravel: CGFloat = 1.5

        // VU meter
        static let needleSweep: Angle = .degrees(96)
        static let needleWidth: CGFloat = 1.5
        static let meterZeroPoint: Double = 0.72
    }

    // MARK: - Type

    /// Tajawal — the system's only typeface. All 7 static weights are bundled; referenced
    /// here by PostScript name since the files aren't a single variable font.
    enum Font {
        private static let regular = "Tajawal-Regular"
        private static let medium = "Tajawal-Medium"
        private static let bold = "Tajawal-Bold"
        private static let extraBold = "Tajawal-ExtraBold"

        /// Panel labels: small, uppercase, tightly tracked. Pair with `.silkscreenTracking`
        /// and uppercase the string — the font alone doesn't make the look.
        static let silkscreen = named(bold, size: 10)
        /// A slightly larger silkscreen label, for section headers on the panel.
        static let silkscreenLarge = named(bold, size: 12)

        static let caption = named(regular, size: 11)
        static let label = named(regular, size: 13)
        /// `--text-sm`, weight 400 — body copy.
        static let body = named(regular, size: 15)
        /// `--text-sm`, weight 500 — the system's body-emphasis weight.
        static let bodyEmphasis = named(medium, size: 15)
        /// `--text-lg`, weight 800 — the system's card/post-title weight.
        static let title = named(extraBold, size: 20)

        /// Readouts and timings — `--font-mono`. Monospaced so digits don't shift as they tick.
        static let counter = SwiftUI.Font.system(size: 13, design: .monospaced).monospacedDigit()
        /// The big transport counter.
        static let counterLarge = SwiftUI.Font.system(size: 26, weight: .medium, design: .monospaced)
            .monospacedDigit()

        /// Letter spacing for silkscreen labels, in points — `--tracking-wide` (.06em) at
        /// this label size.
        static let silkscreenTracking: CGFloat = 0.7

        private static func named(_ postscriptName: String, size: CGFloat) -> SwiftUI.Font {
            .custom(postscriptName, size: size)
        }
    }

    // MARK: - Spacing

    /// `--space-*`, a 4pt grid.
    enum Space {
        static let hair: CGFloat = 2
        static let tight: CGFloat = 4
        static let snug: CGFloat = 8
        static let base: CGFloat = 12
        static let roomy: CGFloat = 16
        static let wide: CGFloat = 24
        static let panel: CGFloat = 32
    }

    // MARK: - Radius

    /// `--radius-*`.
    enum Radius {
        /// Seams and dividers — square.
        static let none: CGFloat = 0
        /// Indicator chips, small lamps — `--radius-sm`.
        static let chip: CGFloat = 6
        /// Button caps and controls — `--radius-md`.
        static let control: CGFloat = 10
        /// Recessed wells and grouped panels — `--radius-lg`.
        static let panel: CGFloat = 16
        /// The window itself — `--radius-xl`.
        static let window: CGFloat = 22
    }

    // MARK: - Border

    /// The system favors borders over shadows: `1px solid var(--border-subtle)` on every
    /// card, a focus ring on hover rather than a thickness change.
    enum Border {
        static let hairline: CGFloat = 1
        static let seam: CGFloat = 1
        static let bevel: CGFloat = 1
    }

    // MARK: - Elevation

    /// `--shadow-sm/md/lg` — real shadows appear only behind overlays (menus, popovers) in
    /// the source system; used more broadly here since macOS controls read as raised.
    enum Shadow {
        static let raised = Spec(color: .black.opacity(0.06), radius: 2, x: 0, y: 1)
        static let pressed = Spec(color: .black.opacity(0.06), radius: 1, x: 0, y: 0)
        static let panel = Spec(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
        static let window = Spec(color: .black.opacity(0.12), radius: 24, x: 0, y: 8)

        struct Spec {
            let color: SwiftUI.Color
            let radius: CGFloat
            let x: CGFloat
            let y: CGFloat
        }
    }

    // MARK: - Motion

    /// `120–200ms`, `cubic-bezier(.4,0,.2,1)` — `--duration-fast` / `--duration-base` /
    /// `--ease-standard`. No bounce.
    enum Motion {
        private static let standard = (0.4, 0.0, 0.2, 1.0)

        /// Key travel down — `--duration-fast`.
        static let press = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.12)
        /// Key travel up — `--duration-base`.
        static let release = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.2)
        /// Panel and view changes — `--duration-base`.
        static let panel = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.2)
        /// The record lamp coming on — instant, like a filament.
        static let lamp = Animation.easeOut(duration: 0.08)

        /// VU ballistics. A real VU meter reaches 99% of a step in ~300ms and overshoots
        /// slightly; that lag *is* the instrument's character, so the needle is damped
        /// rather than tracking the signal directly. Not a brand token — physical behavior.
        static let needleAttack: TimeInterval = 0.30
        static let needleRelease: TimeInterval = 0.42
        /// Peak overshoot as a fraction of the step, before settling.
        static let needleOvershoot: Double = 0.06
    }
}

// MARK: - Hex helpers

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
