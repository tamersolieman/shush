import AppKit
import SwiftUI

/// The app's usage dashboard — words/minute, dictionary fixes, totals, per-app breakdown,
/// and a streak calendar. Computed from `LifetimeStatsStore`, a running tally that's
/// independent of `RunLog`'s own history — so History Limit, Auto-Delete Recordings, and
/// manual deletes never make these numbers go backwards. Nothing here is benchmarked
/// against other users, because Shush only ever sees this machine.
struct StatsDashboard: View {
    @State private var lifetimeStore = LifetimeStatsStore.shared
    // `merged`: this device's totals plus every synced device's last-pushed snapshot. Equals
    // `current` when signed out or never synced, so this is a strict superset of prior behavior.
    private var stats: DictationStats { DictationStats(stats: lifetimeStore.merged) }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Space.roomy) {
                if lifetimeStore.merged.totalRuns == 0 {
                    EmptyPage(title: "No stats yet", detail: "Dictate something — the numbers fill in from there.")
                        .frame(minHeight: 300)
                } else {
                    HStack(alignment: .top, spacing: DS.Space.section) {
                        WordsPerMinuteCard(wpm: stats.wordsPerMinute)
                        FixesCard(stats: stats)
                        TotalWordsCard(stats: stats)
                    }
                    DesktopUsageCard(usage: stats.appUsage)
                    StreakCard(stats: stats)
                }
            }
            .padding(DS.Space.panel)
        }
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

private struct MonthLabel: Identifiable {
    var id: Int { columnIndex }
    let columnIndex: Int
    let text: String
}

private struct StreakInfo {
    /// Sunday-first columns, oldest week to newest, matching a GitHub contribution graph.
    let columns: [[StreakDay?]]
    let monthLabels: [MonthLabel]
    let current: Int
    let longest: Int
    /// Consecutive active days ending today (or yesterday) — outlined in the grid.
    let currentStreakDates: Set<Date>
    /// False once paging has gone back far enough that another page would still be
    /// entirely before the very first recorded day.
    let canGoOlder: Bool
}

private struct DictationStats {
    let stats: LifetimeStats

    var wordsPerMinute: Double {
        let totalMinutes = stats.totalAudioSeconds / 60
        guard totalMinutes > 0.05 else { return 0 }
        return Double(stats.totalWords) / totalMinutes
    }

    var totalWords: Int { stats.totalWords }
    var wordsCorrected: Int { stats.wordsCorrected }
    var dictionaryFixes: Int { stats.dictionaryFixes }

    /// This calendar month's words vs last month's, as a percent change. Nil until there's
    /// a previous month to compare against.
    var monthOverMonth: Double? {
        let calendar = Calendar.current
        let now = Date()
        guard let thisMonthStart = calendar.dateInterval(of: .month, for: now)?.start,
              let lastMonthStart = calendar.date(byAdding: .month, value: -1, to: thisMonthStart)
        else { return nil }

        let thisMonth = stats.monthWords[LifetimeStatsStore.monthKey(thisMonthStart, calendar: calendar)] ?? 0
        let lastMonth = stats.monthWords[LifetimeStatsStore.monthKey(lastMonthStart, calendar: calendar)] ?? 0
        guard lastMonth > 0 else { return nil }
        return (Double(thisMonth) - Double(lastMonth)) / Double(lastMonth) * 100
    }

    var appUsage: [AppUsage] {
        let tallies = Array(stats.appTallies.values)
        guard !tallies.isEmpty else { return [] }
        let total = tallies.reduce(0) { $0 + $1.count }
        return tallies.map { tally in
            AppUsage(
                name: tally.name,
                bundleID: tally.bundleID,
                runCount: tally.count,
                fraction: Double(tally.count) / Double(total)
            )
        }
        .sorted { $0.runCount > $1.runCount }
    }

    /// GitHub-style streak: every calendar day in the visible window, how many recordings
    /// (any kind — comparisons count too, this is "were you here" not "did you inject
    /// text"), plus the current and longest consecutive-day runs across all history. Built
    /// from the lifetime day-count tally, so deleted entries don't erase the streak.
    ///
    /// `page` pages the visible window back one full width (0 = the most recent weeks,
    /// ending today). Current/longest streak and the current-streak outline are always
    /// computed against *all* history, independent of which page is showing.
    func streak(page: Int, weeksSpanned: Int = 20) -> StreakInfo {
        let calendar = Calendar.current
        let dayOf: (Date) -> Date = { calendar.startOfDay(for: $0) }

        let counts: [Date: Int] = stats.dayCounts.reduce(into: [:]) { result, entry in
            guard let date = LifetimeStatsStore.date(fromDayKey: entry.key, calendar: calendar) else { return }
            result[dayOf(date)] = entry.value
        }

        let today = dayOf(Date())
        let windowEnd = calendar.date(byAdding: .day, value: -page * weeksSpanned * 7, to: today) ?? today
        guard let start = calendar.date(byAdding: .day, value: -(weeksSpanned * 7 - 1), to: windowEnd) else {
            return StreakInfo(columns: [], monthLabels: [], current: 0, longest: 0, currentStreakDates: [], canGoOlder: false)
        }

        var days: [StreakDay] = []
        var cursor = start
        while cursor <= windowEnd {
            days.append(StreakDay(date: cursor, count: counts[cursor] ?? 0))
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
        }

        var columns = Array(repeating: [StreakDay?](repeating: nil, count: 7), count: weeksSpanned)
        for day in days {
            let weekday = calendar.component(.weekday, from: day.date) - 1 // Sun = 0
            let daysFromStart = calendar.dateComponents([.day], from: start, to: day.date).day ?? 0
            let week = daysFromStart / 7
            guard columns.indices.contains(week) else { continue }
            columns[week][weekday] = day
        }

        var monthLabels: [MonthLabel] = []
        var lastMonth: Int?
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM"
        for (index, column) in columns.enumerated() {
            guard let first = column.compactMap({ $0 }).first else { continue }
            let month = calendar.component(.month, from: first.date)
            if index == 0 || month != lastMonth {
                monthLabels.append(MonthLabel(columnIndex: index, text: monthFormatter.string(from: first.date)))
            }
            lastMonth = month
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
        var currentStreakDates: Set<Date> = []
        var probe = counts[today] != nil ? today : calendar.date(byAdding: .day, value: -1, to: today)!
        while counts[probe] != nil {
            current += 1
            currentStreakDates.insert(probe)
            probe = calendar.date(byAdding: .day, value: -1, to: probe)!
        }

        let earliestActive = activeDays.first
        let canGoOlder = earliestActive.map { $0 < start } ?? false

        return StreakInfo(
            columns: columns,
            monthLabels: monthLabels,
            current: current,
            longest: longest,
            currentStreakDates: currentStreakDates,
            canGoOlder: canGoOlder
        )
    }
}

// MARK: - Cards

private struct StatCard<Content: View>: View {
    var alignment: HorizontalAlignment = .leading
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: alignment, spacing: DS.Space.base) { content }
            .padding(DS.Space.wide)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

/// Small tracked all-caps label — "TOTAL APPS USED | 36" style, top-right of a card.
private struct CapsLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(DS.Font.sectionHeader)
            .foregroundStyle(DS.Color.textTertiary)
            .kerning(0.4)
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

    /// Darkest for the top app, lightening down the ranking — same idea as the streak
    /// grid's more/less scale, just keyed by rank instead of count.
    private static let shades: [Double] = [1.0, 0.8, 0.62, 0.48, 0.36, 0.26]

    var body: some View {
        StatCard {
            HStack(alignment: .firstTextBaseline) {
                Text("Desktop usage")
                    .font(DS.Font.streakNumber)
                    .foregroundStyle(DS.Color.textPrimary)
                Spacer()
                CapsLabel("Total apps used | \(usage.count)")
            }

            if usage.isEmpty {
                Text("Dictate into a few different apps to see this fill in.")
                    .font(DS.Font.label)
                    .foregroundStyle(DS.Color.textSecondary)
            } else {
                // A `Grid`, not a `VStack` of independent rows: each column (icon, bar,
                // count, name) sizes to its widest cell and lines up across every row —
                // a plain HStack per row can't share column widths with its siblings.
                Grid(alignment: .leading, horizontalSpacing: DS.Space.base, verticalSpacing: DS.Space.base) {
                    ForEach(Array(usage.prefix(6).enumerated()), id: \.element.id) { index, app in
                        GridRow {
                            usageCells(app: app, shade: Self.shades[min(index, Self.shades.count - 1)])
                        }
                    }
                }
            }
        }
    }

    /// `Group` here isn't decorative — inside a `GridRow` it splices its children in as
    /// separate cells rather than one, which is what lets this be factored out at all.
    @ViewBuilder
    private func usageCells(app: AppUsage, shade: Double) -> some View {
        AppIcon(bundleID: app.bundleID)
            .frame(width: 20, height: 20)

        UsageBar(app: app, shade: shade)

        Text("\(app.runCount) ·")
            .font(DS.Font.semibold(11))
            .foregroundStyle(DS.Color.textPrimary)
            .gridColumnAlignment(.trailing)

        Text(app.name)
            .font(DS.Font.semibold(11))
            .foregroundStyle(DS.Color.textPrimary)
            .lineLimit(1)
    }
}

private struct UsageBar: View {
    let app: AppUsage
    let shade: Double

    private var percentText: String { "\(Int((app.fraction * 100).rounded()))%" }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: DS.Radius.chip)
                    .fill(DS.Color.surfaceSecondary)
                RoundedRectangle(cornerRadius: DS.Radius.chip)
                    .fill(DS.Color.primary.opacity(shade))
                    .frame(width: max(geo.size.width * app.fraction, 40))
                    .overlay(alignment: .trailing) {
                        Text(percentText)
                            .font(DS.Font.semibold(11))
                            .foregroundStyle(.white)
                            .padding(.trailing, DS.Space.snug)
                    }
            }
        }
        .frame(height: 28)
        .frame(maxWidth: .infinity)
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
    let stats: DictationStats

    @State private var page = 0
    /// Width available to the grid, excluding the page-arrow gutters either side —
    /// measured live so the number of weeks shown adapts to the card's actual width.
    @State private var gridWidth: CGFloat = 0

    private let cell: CGFloat = 15
    private let spacing: CGFloat = 4
    private let gutter: CGFloat = 38

    /// However many weeks fit at a fixed, GitHub-style cell size — filling the card by
    /// showing more history rather than blowing up individual squares.
    private var weeksSpanned: Int {
        guard gridWidth > 0 else { return 20 }
        let weeks = Int((gridWidth - gutter + spacing) / (cell + spacing))
        return max(8, weeks)
    }

    private var streak: StreakInfo { stats.streak(page: page, weeksSpanned: weeksSpanned) }

    var body: some View {
        StatCard {
            HStack(alignment: .firstTextBaseline) {
                Text("\(streak.current) day streak")
                    .font(DS.Font.streakNumber)
                    .foregroundStyle(DS.Color.textPrimary)
                Spacer()
                CapsLabel("Longest streak | \(streak.longest) days")
            }

            HStack(alignment: .top, spacing: DS.Space.snug) {
                PageButton(systemName: "chevron.left", enabled: streak.canGoOlder) { page += 1 }

                // `Color.clear` has no intrinsic size and genuinely fills whatever this
                // slot is offered; `StreakGrid` itself hugs its (fixed-size) content, so
                // measuring the grid directly would never see more than what it just
                // drew. This sizer sits behind it purely to report the true slot width.
                ZStack(alignment: .topLeading) {
                    Color.clear
                    StreakGrid(streak: streak, weeksSpanned: weeksSpanned, cell: cell, spacing: spacing, gutter: gutter)
                }
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }

                PageButton(systemName: "chevron.right", enabled: page > 0) { page -= 1 }
            }

            HStack {
                HStack(spacing: DS.Space.tight) {
                    Text("More").font(DS.Font.meta).foregroundStyle(DS.Color.textTertiary)
                    ForEach(0..<4) { level in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(DS.Color.primary.opacity(intensity(for: level)))
                            .frame(width: 12, height: 12)
                    }
                    Text("Less").font(DS.Font.meta).foregroundStyle(DS.Color.textTertiary)
                }
                Spacer()
                HStack(spacing: DS.Space.tight) {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(DS.Color.primary, lineWidth: 1.5)
                        .frame(width: 12, height: 12)
                    Text("Current streak").font(DS.Font.meta).foregroundStyle(DS.Color.textTertiary)
                }
            }
        }
    }

    private func intensity(for level: Int) -> Double {
        [1.0, 0.7, 0.4, 0.12][level]
    }
}

private struct PageButton: View {
    let systemName: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(enabled ? DS.Color.textSecondary : DS.Color.textTertiary.opacity(0.4))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .padding(.top, 20) // roughly centers on the month-label + grid block below it
    }
}

private struct StreakGrid: View {
    let streak: StreakInfo
    let weeksSpanned: Int
    let cell: CGFloat
    let spacing: CGFloat
    let gutter: CGFloat

    private var maxCount: Int {
        max(streak.columns.flatMap { $0 }.compactMap { $0?.count }.max() ?? 1, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.tight) {
            // Month labels, offset past the weekday gutter and positioned per column —
            // an HStack of fixed-width slots would clip "Sep" etc., so each label is
            // placed by absolute offset instead.
            ZStack(alignment: .topLeading) {
                Color.clear.frame(height: 14)
                ForEach(streak.monthLabels) { label in
                    Text(label.text)
                        .font(DS.Font.meta)
                        .foregroundStyle(DS.Color.textTertiary)
                        .fixedSize()
                        .offset(x: gutter + CGFloat(label.columnIndex) * (cell + spacing))
                }
            }

            HStack(alignment: .top, spacing: spacing) {
                VStack(alignment: .leading, spacing: spacing) {
                    ForEach(0..<7, id: \.self) { row in
                        Text(weekdayLabel(row))
                            .font(DS.Font.meta)
                            .foregroundStyle(DS.Color.textTertiary)
                            .frame(width: gutter - spacing, height: cell, alignment: .leading)
                            .fixedSize()
                    }
                }

                HStack(spacing: spacing) {
                    ForEach(Array(streak.columns.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: spacing) {
                            ForEach(0..<7, id: \.self) { row in
                                dayCell(week[row])
                            }
                        }
                    }
                }
            }
        }
    }

    private func weekdayLabel(_ row: Int) -> String {
        ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][row]
    }

    private func dayCell(_ day: StreakDay?) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color(for: day))
            .frame(width: cell, height: cell)
            .overlay {
                if let day, streak.currentStreakDates.contains(day.date) {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(DS.Color.primary, lineWidth: 1.5)
                }
            }
    }

    private func color(for day: StreakDay?) -> Color {
        guard let day, day.count > 0 else { return DS.Color.surfaceSecondary }
        let intensity = min(Double(day.count) / Double(maxCount), 1.0)
        return DS.Color.primary.opacity(0.25 + intensity * 0.75)
    }
}
