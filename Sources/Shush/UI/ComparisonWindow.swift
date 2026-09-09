import SwiftUI

/// Live-updating store behind the comparison window.
///
/// The window replaced a generated HTML file opened in the browser. That approach needed a
/// `file://` URL, spawned a fresh tab on every open, and left stale tabs showing old data
/// with no way to tell which was current. A window owned by the app has none of those
/// problems: one instance, always live, nothing to refresh.
@MainActor
@Observable
final class RunStore {
    static let shared = RunStore()

    private(set) var runs: [DictationRun] = []

    private init() { reload() }

    func reload() {
        runs = RunLog.load()
    }

    /// Recordings grouped by comparison, newest first.
    var comparisons: [[DictationRun]] {
        Dictionary(grouping: runs.filter { $0.group != nil }, by: { $0.group! })
            .values
            .sorted { ($0.first?.date ?? .distantPast) > ($1.first?.date ?? .distantPast) }
    }

    var singles: [DictationRun] {
        runs.filter { $0.group == nil }.reversed()
    }
}

struct ComparisonWindow: View {
    @Bindable var controller: DictationController
    @State private var store = RunStore.shared
    @State private var settings = Settings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.section) {
                header
                recordBar

                if store.runs.isEmpty {
                    emptyState
                } else {
                    ForEach(Array(store.comparisons.enumerated()), id: \.offset) { _, group in
                        ComparisonCard(runs: group)
                    }
                    ForEach(Array(store.singles.enumerated()), id: \.offset) { _, run in
                        SingleCard(run: run)
                    }
                }
            }
            .padding(DS.Space.panel)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 560, minHeight: 420)
        .background(DS.Color.background)
        .preferredColorScheme(settings.appearance.colorScheme)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: DS.Space.hair) {
                Text("Engine comparison")
                    .font(DS.Font.bold(22))
                    .foregroundStyle(DS.Color.primary)
                Text("\(store.runs.count) recording\(store.runs.count == 1 ? "" : "s")")
                    .font(DS.Font.meta)
                    .foregroundStyle(DS.Color.textTertiary)
            }
            Spacer()
            if !store.runs.isEmpty {
                Button {
                    RunLog.clear()
                    store.reload()
                } label: {
                    Text("Clear")
                        .font(DS.Font.button)
                        .foregroundStyle(DS.Color.textSecondary)
                        .padding(.horizontal, DS.Space.roomy)
                        .frame(height: 30)
                        .background(DS.Color.surfaceSecondary, in: .rect(cornerRadius: DS.Radius.control))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// One button that records every engine at once — no hotkeys, and the results appear in
    /// this same window, so there's nowhere to go afterwards to read them.
    private var recordBar: some View {
        let isRecording = controller.state.isActive

        return VStack(alignment: .leading, spacing: DS.Space.snug) {
            Button {
                if isRecording {
                    controller.stopButtonRecording()
                } else {
                    controller.startButtonRecording()
                }
            } label: {
                HStack(spacing: DS.Space.snug) {
                    Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
                    Text(isRecording ? "Stop" : "Record all three")
                        .font(DS.Font.semibold(15))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(isRecording ? DS.Color.danger : DS.Color.primary, in: .rect(cornerRadius: DS.Radius.pill))
            }
            .buttonStyle(.plain)

            Text(statusLine(isRecording: isRecording))
                .font(DS.Font.meta)
                .foregroundStyle(DS.Color.textTertiary)
        }
        .padding(.bottom, DS.Space.tight)
    }

    private func statusLine(isRecording: Bool) -> String {
        if isRecording { return "Recording — click Stop when you're done talking." }
        if !controller.transcript.isEmpty { return controller.transcript }
        return WisprReader.isInstalled
            ? "Click Record, talk, click Stop. Apple, Parakeet and Wispr Flow all hear it."
            : "Click Record, talk, click Stop. Wispr Flow isn't installed, so it's Apple vs Parakeet."
    }

    private var emptyState: some View {
        VStack(spacing: DS.Space.base) {
            Image(systemName: "waveform")
                .font(.system(size: 30))
                .foregroundStyle(DS.Color.primary)
            Text("Hold \(settings.pushToTalkKey.displayName), say a sentence, let go.")
                .font(DS.Font.semibold(15))
                .foregroundStyle(DS.Color.textPrimary)
            Text(settings.compareMode
                 ? "Both engines run on that one recording and appear here."
                 : "Turn on Compare Mode in Settings to see both engines at once.")
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.panel + DS.Space.roomy)
    }
}

private struct ComparisonCard: View {
    let runs: [DictationRun]

    /// Fastest first. The engines are *measured* sequentially, so arrival order reflects
    /// which ran first, not which is quicker — sorting by measured time is what makes the
    /// winner readable at a glance.
    private var ranked: [DictationRun] {
        runs.sorted { $0.processSeconds < $1.processSeconds }
    }

    /// How much faster the winner was, once both are in.
    private var margin: String? {
        guard runs.count > 1,
              let best = ranked.first,
              let worst = ranked.last,
              best.processSeconds > 0
        else { return nil }
        let ratio = worst.processSeconds / best.processSeconds
        let delta = worst.processSeconds - best.processSeconds
        guard delta > 0.005 else { return "tied" }
        return String(format: "%@ %.1f× faster · %.2fs ahead", best.engine, ratio, delta)
    }

    /// Case and punctuation are normalized away: Apple auto-punctuates and Parakeet
    /// doesn't, and that's a formatting difference, not a recognition error.
    private var verdict: (String, Color) {
        if Set(runs.map(\.text)).count == 1 { return ("identical", DS.Color.success) }
        let normalized = Set(runs.map {
            $0.text.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
        })
        return normalized.count == 1 ? ("same words", DS.Color.success) : ("words differ", DS.Color.warning)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.base) {
            HStack {
                Text(runs.first.map { "\($0.date.formatted(date: .omitted, time: .standard)) · held \($0.audioSeconds, format: .number.precision(.fractionLength(1)))s" } ?? "")
                    .font(DS.Font.meta)
                    .foregroundStyle(DS.Color.textTertiary)
                Spacer()
                Text(verdict.0)
                    .font(DS.Font.meta)
                    .padding(.horizontal, DS.Space.snug).padding(.vertical, DS.Space.hair)
                    .background(verdict.1.opacity(0.16), in: Capsule())
                    .foregroundStyle(verdict.1)

                // Deletes the whole group: every engine here transcribed one utterance, so
                // removing that utterance means removing all of its rows together.
                if let group = runs.first?.group {
                    Button {
                        withAnimation { RunLog.deleteGroup(group) }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.Color.textSecondary)
                    .help("Delete this comparison")
                }
            }
            if let margin {
                HStack(spacing: DS.Space.hair) {
                    Image(systemName: margin == "tied" ? "equal.circle.fill" : "bolt.fill")
                    Text(margin)
                }
                .font(DS.Font.semibold(12))
                .foregroundStyle(DS.Color.success)
            } else if runs.count == 1 {
                HStack(spacing: DS.Space.hair) {
                    ProgressView().controlSize(.small)
                    Text("running second engine…")
                }
                .font(DS.Font.meta)
                .foregroundStyle(DS.Color.textTertiary)
            }

            Rectangle().fill(DS.Color.divider).frame(height: DS.Border.hairline)
            ForEach(Array(ranked.enumerated()), id: \.offset) { index, run in
                EngineRow(run: run, rank: index + 1, showRank: runs.count > 1)
            }
        }
        .padding(DS.Space.roomy)
        .background(DS.Color.surface, in: .rect(cornerRadius: DS.Radius.card))
    }
}

private struct EngineRow: View {
    let run: DictationRun
    let rank: Int
    let showRank: Bool

    private var isWinner: Bool { showRank && rank == 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.tight) {
            HStack(alignment: .firstTextBaseline) {
                Text(run.engine + (isWinner ? " · fastest" : ""))
                    .font(DS.Font.semibold(11))
                    .padding(.horizontal, DS.Space.snug).padding(.vertical, DS.Space.hair)
                    .background((isWinner ? DS.Color.success : DS.Color.primary).opacity(0.16), in: Capsule())
                    .foregroundStyle(isWinner ? DS.Color.success : DS.Color.primary)
                Spacer()
                Text("\(run.processSeconds, format: .number.precision(.fractionLength(2)))s")
                    .font(.system(size: isWinner ? 20 : 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isWinner ? DS.Color.success : DS.Color.textPrimary)
            }
            Text("\(run.realtimeFactor, format: .number.precision(.fractionLength(0)))× realtime · \(run.characters) chars")
                .font(DS.Font.meta)
                .foregroundStyle(DS.Color.textTertiary)
            Text(run.text.isEmpty ? "(nothing recognized)" : run.text)
                .font(DS.Font.body)
                .foregroundStyle(run.text.isEmpty ? DS.Color.textTertiary : DS.Color.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, DS.Space.tight)
    }
}

private struct SingleCard: View {
    let run: DictationRun

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.tight) {
            HStack {
                Text(run.engine).font(DS.Font.semibold(12)).foregroundStyle(DS.Color.textPrimary)
                Spacer()
                Text("\(run.processSeconds, format: .number.precision(.fractionLength(2)))s")
                    .font(DS.Font.meta).monospacedDigit().foregroundStyle(DS.Color.textTertiary)
            }
            Text(run.text)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Space.roomy)
        .background(DS.Color.surface, in: .rect(cornerRadius: DS.Radius.control))
    }
}
