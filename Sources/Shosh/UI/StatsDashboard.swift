import AppKit
import SwiftUI

/// The app's usage dashboard — words/minute, dictionary fixes, totals, per-app breakdown,
/// and a streak calendar. All computed from `RunLog`'s own history; nothing here is
/// benchmarked against other users, because Shosh only ever sees this machine.
struct StatsDashboard: View {
    @State private var store = RunStore.shared
    private var stats: DictationStats { DictationStats(runs: store.runs) }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Space.roomy) {
                if store.runs.isEmpty {
                    EmptyPage(title: "No stats yet", detail: "Dictate something — the numbers fill in from there.")
                        .frame(minHeight: 300)
                } else {
                    HStack(alignment: .top, spacing: DS.Space.section) {
                        WordsPerMinuteCard(wpm: stats.wordsPerMinute)
                        FixesCard(stats: stats)
                        TotalWordsCard(stats: stats)
                    }
                    HStack(alignment: .top, spacing: DS.Space.section) {
                        DesktopUsageCard(usage: stats.appUsage)
                        StreakCard(streak: stats.streak)
                    }
                }
            }
            .padding(DS.Space.panel)
        }
        .onAppear { store.reload() }
    }
}

// MARK: - Data

private struct AppUsage: Identifiable {
    var id: String { bundleID ?? name }
    let name: String
    let bundleID: String?
    let runCount: Int
    let fraction: Double
}

private struct StreakDay: Identifiable {
    var id: Date { date }
    let date: Date
    let count: Int
}

private struct StreakInfo {
    let days: [StreakDay]
    let current: Int
    let longest: Int
    let weeksSpanned: Int
}

private struct DictationStats {
    let runs: [DictationRun]

    /// Real dictations only — a comparison run injects nothing, so it isn't "spoken output".
    private var injected: [DictationRun] { runs.filter { $0.group == nil } }

    var wordsPerMinute: Double {
        let totalWords = injected.reduce(0) { $0 + $1.wordCount }
        let totalMinutes = injected.reduce(0.0) { $0 + $1.audioSeconds } / 60
        guard totalMinutes > 0.05 else { return 0 }
        return Double(totalWords) / totalMinutes
    }

    var totalWords: Int { injected.reduce(0) { $0 + $1.wordCount } }

    var wordsCorrected: Int {
        injected.reduce(0) { $0 + ($1.corrections?.reduce(0) { $0 + $1.count } ?? 0) }
    }

    var dictionaryFixes: Int {
        injected.reduce(0) { $0 + ($1.corrections?.count ?? 0) }
    }

    /// This calendar month's words vs last month's, as a percent change. Nil until there's
    /// a previous month to compare against.
    var monthOverMonth: Double? {
        let calendar = Calendar.current
        let now = Date()
        guard let thisMonthStart = calendar.dateInterval(of: .month, for: now)?.start,
              let lastMonthStart = calendar.date(byAdding: .month, value: -1, to: thisMonthStart)
        else { return nil }

        let thisMonth = injected.filter { $0.date >= thisMonthStart }.reduce(0) { $0 + $1.wordCount }
        let lastMonth = injected.filter { $0.date >= lastMonthStart && $0.date < thisMonthStart }
            .reduce(0) { $0 + $1.wordCount }
        guard lastMonth > 0 else { return nil }
        return (Double(thisMonth) - Double(lastMonth)) / Double(lastMonth) * 100
    }

    var appUsage: [AppUsage] {
        let named = injected.compactMap { run -> (String, String?)? in
            guard let name = run.appName else { return nil }
            return (name, run.appBundleID)
        }
        guard !named.isEmpty else { return [] }

        let grouped = Dictionary(grouping: named, by: \.0)
        let total = named.count
        return grouped.map { name, entries in
            AppUsage(
                name: name,
                bundleID: entries.first?.1,
                runCount: entries.count,
                fraction: Double(entries.count) / Double(total)
            )
        }
        .sorted { $0.runCount > $1.runCount }
    }

    /// GitHub-style streak: every calendar day in the visible window, how many recordings
    /// (any kind — comparisons count too, this is "were you here" not "did you inject
    /// text"), plus the current and longest consecutive-day runs across all history.
    var streak: StreakInfo {
        let calendar = Calendar.current
        let dayOf: (Date) -> Date = { calendar.startOfDay(for: $0) }

        let counts = Dictionary(grouping: runs.map { dayOf($0.date) }, by: { $0 })
            .mapValues(\.count)

        let weeksSpanned = 18
        let today = dayOf(Date())
        guard let start = calendar.date(byAdding: .day, value: -(weeksSpanned * 7 - 1), to: today) else {
            return StreakInfo(days: [], current: 0, longest: 0, weeksSpanned: weeksSpanned)
        }

        var days: [StreakDay] = []
        var cursor = start
        while cursor <= today {
            days.append(StreakDay(date: cursor, count: counts[cursor] ?? 0))
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
        }

        // Longest run over *all* history, not just the visible window.
        let activeDays = Set(counts.keys).sorted()
        var longest = 0
        var run = 0
        var previous: Date?
        for day in activeDays {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previous = day
        }

        // Current streak: consecutive active days ending today (or yesterday, so a streak
        // isn't reported broken before today has actually ended).
        var current = 0
        var probe = counts[today] != nil ? today : calendar.date(byAdding: .day, value: -1, to: today)!
        while counts[probe] != nil {
            current += 1
            probe = calendar.date(byAdding: .day, value: -1, to: probe)!
        }

        return StreakInfo(days: days, current: current, longest: longest, weeksSpanned: weeksSpanned)
    }
}

// MARK: - Cards

private struct StatCard<Content: View>: View {
    var alignment: HorizontalAlignment = .leading
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: alignment, spacing: DS.Space.base) { content }
            .padding(DS.Space.wide)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Color.surface, in: .rect(cornerRadius: DS.Radius.card))
    }
}

private struct CardDivider: View {
    var body: some View {
        Rectangle().fill(DS.Color.divider).frame(height: DS.Border.hairline)
    }
}

private struct MetricTitle: View {
    let text: String
    var body: some View {
        Text(text).font(DS.Font.metricTitle).foregroundStyle(DS.Color.textPrimary)
    }
}

private struct MetricSubtitle: View {
    let text: String
    var body: some View {
        Text(text).font(DS.Font.metricSubtitle).foregroundStyle(DS.Color.textTertiary)
    }
}

private struct WordsPerMinuteCard: View {
    let wpm: Double
    /// Visual ceiling for the arc — comfortably above fast conversational speech.
    private let scaleMax: Double = 200

    var body: some View {
        StatCard {
            Text(wpm > 0 ? "\(Int(wpm.rounded()))" : "—")
                .font(DS.Font.metricValue)
                .foregroundStyle(DS.Color.primary)
            MetricTitle(text: "Words per minute")

            GaugeArc(fraction: min(wpm / scaleMax, 1))
                .frame(height: 90)
                .frame(maxWidth: .infinity)
        }
    }
}

/// A semicircular progress arc.
private struct GaugeArc: View {
    let fraction: Double

    var body: some View {
        Canvas { context, size in
            let pivot = CGPoint(x: size.width / 2, y: size.height)
            let radius = min(size.width / 2, size.height) - 6

            var track = Path()
            track.addArc(center: pivot, radius: radius, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            context.stroke(track, with: .color(DS.Color.surfaceSecondary), style: StrokeStyle(lineWidth: 10, lineCap: .round))

            var progress = Path()
            let end = 180 - 180 * fraction
            progress.addArc(center: pivot, radius: radius, startAngle: .degrees(180), endAngle: .degrees(end), clockwise: false)
            context.stroke(progress, with: .color(DS.Color.primary), style: StrokeStyle(lineWidth: 10, lineCap: .round))
        }
    }
}

private struct FixesCard: View {
    let stats: DictationStats

    var body: some View {
        StatCard {
            Text("\(stats.dictionaryFixes)")
                .font(DS.Font.metricValue)
                .foregroundStyle(DS.Color.primary)
            MetricTitle(text: "Dictionary fixes")

            CardDivider()

            VStack(alignment: .leading, spacing: DS.Space.tight) {
                MetricSubtitle(text: "\(stats.wordsCorrected) words corrected")
                MetricSubtitle(text: "\(stats.dictionaryFixes) correction rules fired")
            }
        }
    }
}

private struct TotalWordsCard: View {
    let stats: DictationStats

    private var books: Int { stats.totalWords / 90_000 }

    var body: some View {
        StatCard {
            HStack(alignment: .top) {
                Text(stats.totalWords.formatted())
                    .font(DS.Font.metricValue)
                    .foregroundStyle(DS.Color.primary)
                Spacer()
                if let trend = stats.monthOverMonth {
                    TrendBadge(percent: trend)
                }
            }
            MetricTitle(text: "Total words dictated")

            CardDivider()

            Text(books > 0
                 ? "You've written \(books) complete book\(books == 1 ? "" : "s")!"
                 : "Keep going — \(90_000 - stats.totalWords) words to your first book.")
                .font(DS.Font.metricSubtitle)
                .foregroundStyle(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TrendBadge: View {
    let percent: Double

    var body: some View {
        HStack(spacing: DS.Space.hair) {
            Image(systemName: percent >= 0 ? "arrow.up.right" : "arrow.down.right")
            Text("\(abs(Int(percent.rounded())))% this month")
        }
        .font(DS.Font.meta)
        .foregroundStyle(percent >= 0 ? DS.Color.success : DS.Color.danger)
        .padding(.horizontal, DS.Space.snug)
        .padding(.vertical, DS.Space.hair)
        .background((percent >= 0 ? DS.Color.success : DS.Color.danger).opacity(0.12), in: .capsule)
    }
}

private struct DesktopUsageCard: View {
    let usage: [AppUsage]

    var body: some View {
        StatCard {
            HStack(alignment: .firstTextBaseline) {
                Text("Desktop usage")
                    .font(DS.Font.semibold(13))
                    .foregroundStyle(DS.Color.textPrimary)
                Spacer()
                Text("\(usage.count) apps")
                    .font(DS.Font.sectionHeader)
                    .foregroundStyle(DS.Color.textTertiary)
            }

            if usage.isEmpty {
                Text("Dictate into a few different apps to see this fill in.")
                    .font(DS.Font.label)
                    .foregroundStyle(DS.Color.textSecondary)
            } else {
                VStack(spacing: DS.Space.base) {
                    ForEach(usage.prefix(6)) { app in
                        AppUsageRow(app: app)
                    }
                }
            }
        }
    }
}

private struct AppUsageRow: View {
    let app: AppUsage

    var body: some View {
        HStack(spacing: DS.Space.base) {
            AppIcon(bundleID: app.bundleID)
                .frame(width: 20, height: 20)

            Text(app.name)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.textPrimary)
                .lineLimit(1)
                .frame(width: 110, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: DS.Radius.chip)
                        .fill(DS.Color.surfaceSecondary)
                    RoundedRectangle(cornerRadius: DS.Radius.chip)
                        .fill(DS.Color.primary)
                        .frame(width: max(geo.size.width * app.fraction, 4))
                }
            }
            .frame(height: 8)

            Text("\(Int((app.fraction * 100).rounded()))%")
                .font(DS.Font.meta)
                .foregroundStyle(DS.Color.textTertiary)
                .frame(width: 36, alignment: .trailing)
        }
    }
}

/// The real running app icon, looked up by bundle id and cached — falls back to a generic
/// glyph for runs recorded before app-tracking existed.
private struct AppIcon: View {
    let bundleID: String?

    var body: some View {
        if let bundleID, let image = AppIconCache.shared.icon(for: bundleID) {
            Image(nsImage: image).resizable().scaledToFit()
        } else {
            Image(systemName: "app.dashed")
                .foregroundStyle(DS.Color.textSecondary)
        }
    }
}

@MainActor
private final class AppIconCache {
    static let shared = AppIconCache()
    private var cache: [String: NSImage] = [:]

    func icon(for bundleID: String) -> NSImage? {
        if let cached = cache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = image
        return image
    }
}

private struct StreakCard: View {
    let streak: StreakInfo

    var body: some View {
        StatCard {
            HStack(alignment: .firstTextBaseline) {
                Text("\(streak.current) day streak")
                    .font(DS.Font.semibold(13))
                    .foregroundStyle(DS.Color.textPrimary)
                Spacer()
                Text("Longest \(streak.longest) days")
                    .font(DS.Font.sectionHeader)
                    .foregroundStyle(DS.Color.textTertiary)
            }

            StreakGrid(days: streak.days, weeks: streak.weeksSpanned)

            HStack(spacing: DS.Space.tight) {
                Text("Less").font(DS.Font.meta).foregroundStyle(DS.Color.textTertiary)
                ForEach(0..<4) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DS.Color.primary.opacity(intensity(for: level)))
                        .frame(width: 12, height: 12)
                }
                Text("More").font(DS.Font.meta).foregroundStyle(DS.Color.textTertiary)
            }
        }
    }

    private func intensity(for level: Int) -> Double {
        [0.12, 0.4, 0.7, 1.0][level]
    }
}

private struct StreakGrid: View {
    let days: [StreakDay]
    let weeks: Int

    /// Sunday-first rows, oldest week to newest column, matching a GitHub contribution graph.
    private var columns: [[StreakDay?]] {
        var grid = Array(repeating: [StreakDay?](repeating: nil, count: 7), count: weeks)
        let calendar = Calendar.current
        for day in days {
            let weekday = calendar.component(.weekday, from: day.date) - 1 // Sun = 0
            let daysFromStart = calendar.dateComponents([.day], from: days.first?.date ?? day.date, to: day.date).day ?? 0
            let week = daysFromStart / 7
            guard grid.indices.contains(week) else { continue }
            grid[week][weekday] = day
        }
        return grid
    }

    private var maxCount: Int { max(days.map(\.count).max() ?? 1, 1) }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, week in
                VStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { row in
                        cell(week[row])
                    }
                }
            }
        }
    }

    private func cell(_ day: StreakDay?) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color(for: day))
            .frame(width: 12, height: 12)
    }

    private func color(for day: StreakDay?) -> Color {
        guard let day, day.count > 0 else { return DS.Color.surfaceSecondary }
        let intensity = min(Double(day.count) / Double(maxCount), 1.0)
        return DS.Color.primary.opacity(0.25 + intensity * 0.75)
    }
}
