import SwiftUI

/// Kept as an alias to `DS.Color.primary` rather than removed outright — `Waveform` below
/// is the only remaining caller, and giving the brand a name keeps that call site readable.
enum Brand {
    static var gradient: LinearGradient {
        LinearGradient(colors: [DS.Color.primary], startPoint: .leading, endPoint: .trailing)
    }
}

/// The floating HUD, in the same DS tokens as the rest of the app — a blurred backdrop
/// (it floats over arbitrary apps/desktops, so it needs the material for legibility) tinted
/// with the theme's surface color, so light/dark and the explicit override both apply here
/// too, not just in the main window.
struct HUDView: View {
    @Bindable var controller: DictationController
    @State private var settings = Settings.shared

    var body: some View {
        HStack(spacing: DS.Space.roomy) {
            Waveform(level: controller.level, isActive: controller.state == .listening)
                .frame(width: 84, height: 28)

            Text(label)
                .font(DS.Font.medium(14))
                .foregroundStyle(isError ? DS.Color.danger : DS.Color.textPrimary)
                .lineLimit(2)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeOut(duration: 0.12), value: controller.transcript)
        }
        .padding(.horizontal, DS.Space.section)
        .padding(.vertical, DS.Space.roomy)
        .frame(width: 420, height: 76)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(DS.Color.surface.opacity(0.55))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(DS.Color.border, lineWidth: DS.Border.hairline)
                }
                .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        }
        .preferredColorScheme(settings.appearance.colorScheme)
    }

    private var isError: Bool {
        if case .error = controller.state { return true }
        return false
    }

    private var label: String {
        switch controller.state {
        case .starting: "Listening…"
        case .listening: controller.transcript.isEmpty ? "Listening…" : controller.transcript
        // Parakeet transcribes in one pass on release, so there's nothing to show until
        // it lands — say what's happening instead of leaving an empty pill.
        case .finishing: controller.transcript.isEmpty ? "Transcribing…" : controller.transcript
        case .error(let message): message
        case .idle: ""
        }
    }
}

/// Level-reactive bars. Each bar gets a fixed phase offset so the group ripples rather
/// than pumping in unison.
private struct Waveform: View {
    let level: Float
    let isActive: Bool

    private static let barCount = 12
    private static let phases: [Double] = (0..<barCount).map { index in
        // Irrational multiplier keeps the offsets from lining up into a visible period.
        (Double(index) * 0.618).truncatingRemainder(dividingBy: 1)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<Self.barCount, id: \.self) { index in
                    Capsule()
                        .fill(Brand.gradient)
                        .frame(width: 3, height: height(for: index, at: t))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func height(for index: Int, at time: TimeInterval) -> CGFloat {
        let floorHeight: CGFloat = 3
        guard isActive else { return floorHeight }

        let phase = Self.phases[index]
        let wave = sin(time * 6.0 + phase * .pi * 2)
        let amplitude = CGFloat(max(0.04, level))
        // Wave rides on top of the level so bars still breathe during quiet passages.
        let scaled = amplitude * (0.55 + 0.45 * CGFloat(wave))
        return floorHeight + max(0, scaled) * 23
    }
}
