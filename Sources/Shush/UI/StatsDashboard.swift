import AppKit
import SwiftUI

/// The app's usage dashboard — a KPI strip, monthly trend, desktop usage, correction
/// accuracy, busiest weekday, and a streak calendar. Computed from `LifetimeStatsStore`, a
/// running tally that's independent of `RunLog`'s own history — so History Limit,
/// Auto-Delete Recordings, and manual deletes never make these numbers go backwards.
/// Nothing here is benchmarked against other users, because Shush only ever sees this
/// machine.
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
                    KPIStrip(stats: stats)

                    HStack(alignment: .top, spacing: DS.Space.roomy) {
                        VStack(spacing: DS.Space.roomy) {
                            MonthlyTrendCard(stats: stats)
                            DesktopUsageCard(usage: stats.appUsage)
                        }
                        VStack(spacing: DS.Space.roomy) {
                            CorrectionAccuracyCard(stats: stats)
                            DictionaryFixesCard(stats: stats)
                            BusiestWeekdayCard(stats: stats)
                        }
                        .frame(minWidth: 260, maxWidth: 340)
                    }

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

private struct MonthPoint: Identifiable {
    var id: String { key }
    let key: String
    let label: String
    let words: Int
    let fraction: Double
}

private struct WeekdayCount: Identifiable {
    var id: String { label }
    let label: String
    let count: Int
    let fraction: Double
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

    /// "14.2h", or minutes once under an hour — total time spent dictating, lifetime.
    var totalTimeFormatted: String {
        let hours = stats.totalAudioSeconds / 3600
        if hours >= 1 { return String(format: "%.1fh", hours) }
        return "\(max(Int(stats.totalAudioSeconds / 60), 0))m"
    }

    /// Rough per-session average — `totalRuns` includes comparison runs (which inject no
    /// words), so this slightly undercounts true injected-run averages rather than needing a
    /// second tally just for this one number.
    var avgWordsPerSession: Int {
        guard stats.totalRuns > 0 else { return 0 }
        return Int((Double(stats.totalWords) / Double(stats.totalRuns)).rounded())
    }

    /// Share of dictated words the dictionary had to auto-correct — the inverse of this is
    /// shown as "accuracy".
    var correctionRatePercent: Double {
        guard stats.totalWords > 0 else { return 0 }
        return Double(stats.wordsCorrected) / Double(stats.totalWords) * 100
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

    /// The last 6 calendar months' word counts, oldest first, each normalized against the
    /// tallest month in the window for bar heights.
    var monthlyTrend: [MonthPoint] {
        let calendar = Calendar.current
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"

        let points: [(key: String, label: String, words: Int)] = (0...5).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .month, value: -offset, to: now) else { return nil }
            let key = LifetimeStatsStore.monthKey(date, calendar: calendar)
            return (key, formatter.string(from: date), stats.monthWords[key] ?? 0)
        }
        let maxWords = max(points.map(\.words).max() ?? 1, 1)
        return points.map { MonthPoint(key: $0.key, label: $0.label, words: $0.words, fraction: Double($0.words) / Double(maxWords)) }
    }

    /// Every recorded day's count, bucketed by weekday (Monday first) and summed across all
    /// history — which day of the week you tend to dictate most.
    var busiestWeekdays: [WeekdayCount] {
        let calendar = Calendar.current
        var totals = [Int](repeating: 0, count: 7) // Mon = 0 ... Sun = 6
        for (key, count) in stats.dayCounts {
            guard let date = LifetimeStatsStore.date(fromDayKey: key, calendar: calendar) else { continue }
            let sundayFirst = calendar.component(.weekday, from: date) - 1 // Sun = 0
            totals[(sundayFirst + 6) % 7] += count
        }
        let maxTotal = max(totals.max() ?? 1, 1)
        let labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        return (0..<7).map { WeekdayCount(label: labels[$0], count: totals[$0], fraction: Double(totals[$0]) / Double(maxTotal)) }
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

// MARK: - Shared card pieces

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

/// A colored square behind an SF Symbol — every card and KPI tile leads with one of these so
/// the dashboard reads as a set of distinct metrics at a glance, not a wall of numbers.
private struct IconChip: View {
    let systemName: String
    let tint: Color
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.Radius.control + 2)
                .fill(tint.opacity(0.15))
            Image(systemName: systemName)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
    }
}

/// A card's title row: icon chip + label, the same shape on every card in the second row.
private struct CardHeader: View {
    let icon: String
    let tint: Color
    let title: String

    var body: some View {
        HStack(spacing: DS.Space.snug) {
            IconChip(systemName: icon, tint: tint, size: 32)
            Text(title).font(DS.Font.label).foregroundStyle(DS.Color.textPrimary)
        }
    }
}

// MARK: - KPI strip

private struct KPIStrip: View {
    let stats: DictationStats

    var body: some View {
        HStack(spacing: DS.Space.roomy) {
            KPITile(
                icon: "doc.text.fill", tint: DS.Color.primary,
                value: stats.totalWords.formatted(), label: "Total Words",
                sub: trendSubtitle, subColor: trendColor
            )
            KPITile(
                icon: "gauge.with.dots.needle.67percent", tint: DS.Color.purple,
                value: stats.wordsPerMinute > 0 ? "\(Int(stats.wordsPerMinute.rounded()))" : "—", label: "Words / Min",
                sub: "avg \(stats.avgWordsPerSession) / session"
            )
            KPITile(
                icon: "clock.fill", tint: DS.Color.warning,
                value: stats.totalTimeFormatted, label: "Total Time",
                sub: "\(stats.stats.totalRuns.formatted()) sessions"
            )
            KPITile(
                icon: "flame.fill", tint: DS.Color.rose,
                value: "\(stats.streak(page: 0).current)", label: "Day Streak",
                sub: "best \(stats.streak(page: 0).longest) days"
            )
            KPITile(
                icon: "wand.and.stars", tint: DS.Color.success,
                value: String(format: "%.1f%%", stats.correctionRatePercent), label: "Correction Rate",
                sub: "\(stats.dictionaryFixes) fixes"
            )
        }
    }

    private var trendSubtitle: String {
        guard let trend = stats.monthOverMonth else { return "this month" }
        return "\(trend >= 0 ? "↑" : "↓") \(abs(Int(trend.rounded())))% this month"
    }

    private var trendColor: Color { (stats.monthOverMonth ?? 0) >= 0 ? DS.Color.success : DS.Color.danger }
}

private struct KPITile: View {
    let icon: String
    let tint: Color
    let value: String
    let label: String
    let sub: String
    var subColor: Color = DS.Color.textTertiary

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.snug) {
            IconChip(systemName: icon, tint: tint)
            Text(value).font(DS.Font.bold(24)).foregroundStyle(DS.Color.textPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(DS.Font.metricSubtitle).foregroundStyle(DS.Color.textSecondary)
                Text(sub).font(.system(size: 10, weight: .semibold)).foregroundStyle(subColor)
            }
        }
        .padding(DS.Space.wide)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.surface, in: .rect(cornerRadius: DS.Radius.card))
    }
}

// MARK: - Monthly trend

private struct MonthlyTrendCard: View {
    let stats: DictationStats

    var body: some View {
        StatCard {
            CardHeader(icon: "chart.bar.fill", tint: DS.Color.primary, title: "Monthly words dictated")

            HStack(alignment: .bottom, spacing: DS.Space.roomy) {
                ForEach(stats.monthlyTrend) { point in
                    VStack(spacing: DS.Space.tight) {
                        Text(point.words.formatted())
                            .font(.system(size: 10))
                            .foregroundStyle(DS.Color.textTertiary)
                        RoundedRectangle(cornerRadius: DS.Radius.chip)
                            .fill(point.fraction >= 0.999 ? DS.Color.primary : DS.Color.primary.opacity(0.35))
                            .frame(height: max(point.fraction * 130, 4))
                        Text(point.label)
                            .font(DS.Font.meta)
                            .foregroundStyle(point.fraction >= 0.999 ? DS.Color.primary : DS.Color.textTertiary)
                            .fontWeight(point.fraction >= 0.999 ? .semibold : .regular)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 170)
        }
    }
}

// MARK: - Desktop usage

private struct DesktopUsageCard: View {
    let usage: [AppUsage]

    /// Darkest for the top app, lightening down the ranking — same idea as the streak
    /// grid's more/less scale, just keyed by rank instead of count.
    private static let shades: [Double] = [1.0, 0.8, 0.62, 0.48, 0.36, 0.26]

    var body: some View {
        StatCard {
            HStack {
                CardHeader(icon: "macwindow", tint: DS.Color.purple, title: "Desktop usage")
                Spacer()
                Text("\(usage.count) apps").font(DS.Font.meta).foregroundStyle(DS.Color.textTertiary)
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
        ZStack {
            Circle().fill(DS.Color.primary.opacity(shade * 0.18))
            AppIcon(bundleID: app.bundleID).frame(width: 16, height: 16)
        }
        .frame(width: 26, height: 26)

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
        ZStack(alignment: .trailing) {
            DynamicBar(fraction: app.fraction, tint: DS.Color.primary.opacity(shade))
            Text(percentText)
                .font(DS.Font.semibold(11))
                .foregroundStyle(.white)
                .padding(.trailing, DS.Space.snug)
        }
        .frame(height: 28)
    }
}

/// A proportional fill bar sized entirely by its container's flexible layout — no
/// `GeometryReader`. `GeometryReader` has no well-defined "ideal size," and asking for one
/// as a `Grid` cell (`UsageBar`) or between rigid `HStack` siblings (`BusiestWeekdayCard`)
/// let the reported width balloon far past the actual window, which is what was blowing the
/// whole dashboard's layout out past its edge whenever the sidebar toggled changed the
/// available width. `.scaleEffect` only affects rendering, not layout, so the fill can shrink
/// from a full-width shape without ever telling its parent it needs more room than it has —
/// and because it's driven by the container's live width on every layout pass, it stays
/// correct through the sidebar's expand/collapse animation instead of needing a remeasure.
private struct DynamicBar: View {
    let fraction: Double
    let tint: Color
    var minimumVisibleFraction: Double = 0.08

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: DS.Radius.chip)
                .fill(DS.Color.surfaceSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            RoundedRectangle(cornerRadius: DS.Radius.chip)
                .fill(tint)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(x: max(fraction, minimumVisibleFraction), y: 1, anchor: .leading)
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

// MARK: - Correction accuracy / fixes / busiest weekday

private struct CorrectionAccuracyCard: View {
    let stats: DictationStats

    private var accuracyPercent: Double { 100 - stats.correctionRatePercent }
    private var accuracyFraction: Double { max(min(accuracyPercent / 100, 1), 0) }

    var body: some View {
        StatCard {
            CardHeader(icon: "checkmark.shield.fill", tint: DS.Color.success, title: "Correction accuracy")

            HStack(spacing: DS.Space.roomy) {
                ZStack {
                    Circle().stroke(DS.Color.success.opacity(0.15), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: accuracyFraction)
                        .stroke(DS.Color.success, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: DS.Space.tight) {
                    Text(String(format: "%.1f%%", accuracyPercent))
                        .font(DS.Font.bold(22))
                        .foregroundStyle(DS.Color.textPrimary)
                    Text("\(stats.wordsCorrected.formatted()) of \(stats.totalWords.formatted()) words auto-corrected")
                        .font(DS.Font.meta)
                        .foregroundStyle(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct DictionaryFixesCard: View {
    let stats: DictationStats

    var body: some View {
        HStack(spacing: DS.Space.roomy) {
            IconChip(systemName: "wand.and.stars", tint: DS.Color.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(stats.dictionaryFixes)").font(DS.Font.bold(22)).foregroundStyle(DS.Color.textPrimary)
                Text("Correction rules fired").font(DS.Font.metricSubtitle).foregroundStyle(DS.Color.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Space.wide)
        .frame(maxWidth: .infinity)
        .background(DS.Color.surface, in: .rect(cornerRadius: DS.Radius.card))
    }
}

private struct BusiestWeekdayCard: View {
    let stats: DictationStats

    var body: some View {
        StatCard {
            CardHeader(icon: "calendar", tint: DS.Color.warning, title: "Busiest day of week")

            VStack(spacing: DS.Space.snug) {
                ForEach(stats.busiestWeekdays) { day in
                    HStack(spacing: DS.Space.snug) {
                        Text(day.label)
                            .font(DS.Font.meta)
                            .foregroundStyle(DS.Color.textTertiary)
                            .frame(width: 30, alignment: .leading)
                        DynamicBar(
                            fraction: day.fraction,
                            tint: day.fraction >= 0.999 ? DS.Color.warning : DS.Color.warning.opacity(0.35)
                        )
                        .frame(height: 14)
                    }
                }
            }
        }
    }
}

// MARK: - Streak

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
            HStack {
                CardHeader(icon: "flame.fill", tint: DS.Color.rose, title: "\(streak.current) day streak")
                Spacer()
                Text("Longest streak | \(streak.longest) days")
                    .font(DS.Font.sectionHeader)
                    .foregroundStyle(DS.Color.textTertiary)
                    .kerning(0.4)
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
                            .fill(DS.Color.rose.opacity(intensity(for: level)))
                            .frame(width: 12, height: 12)
                    }
                    Text("Less").font(DS.Font.meta).foregroundStyle(DS.Color.textTertiary)
                }
                Spacer()
                HStack(spacing: DS.Space.tight) {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(DS.Color.rose, lineWidth: 1.5)
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
                        .strokeBorder(DS.Color.rose, lineWidth: 1.5)
                }
            }
    }

    private func color(for day: StreakDay?) -> Color {
        guard let day, day.count > 0 else { return DS.Color.surfaceSecondary }
        let intensity = min(Double(day.count) / Double(maxCount), 1.0)
        return DS.Color.rose.opacity(0.25 + intensity * 0.75)
    }
}
