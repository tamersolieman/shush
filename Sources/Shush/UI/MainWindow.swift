import ShushDictionary
import AppKit
import SwiftUI

/// The app's main window — a persistent left sidebar plus a content area whose top bar and
/// body change per section. Matches the Pencil design (`shush_app.pen`): Dashboard,
/// Transcripts, Dictionary and Settings all live behind the same sidebar nav rather than
/// Settings being a separate window.
struct MainWindow: View {
    @Bindable var controller: DictationController
    @State private var settings = Settings.shared

    @State private var section: Section = .dashboard
    @State private var sidebarVisible = true

    enum Section: String, CaseIterable, Identifiable {
        case dashboard, transcripts, dictionary, settings

        var id: String { rawValue }
        var title: String {
            switch self {
            case .dashboard: "Dashboard"
            case .transcripts: "Transcripts"
            case .dictionary: "Dictionary"
            case .settings: "Settings"
            }
        }
        var icon: String {
            switch self {
            case .dashboard: "square.grid.2x2"
            case .transcripts: "text.bubble"
            case .dictionary: "book.closed"
            case .settings: "gearshape"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(section: $section, isCollapsed: !sidebarVisible)
            ContentArea(controller: controller, section: section)
        }
        .animation(DS.Motion.base, value: sidebarVisible)
        // 960 was enough for the dashboard's old 3-card layout; the 5-tile KPI strip plus a
        // fixed-ish right column needs more room, especially with the sidebar expanded.
        .frame(minWidth: 1100, minHeight: 640)
        .background(DS.Color.background)
        .preferredColorScheme(settings.appearance.colorScheme)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    sidebarVisible.toggle()
                } label: {
                    Image(systemName: "sidebar.leading")
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
                .help(sidebarVisible ? "Collapse Sidebar" : "Expand Sidebar")
            }
        }
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @Binding var section: MainWindow.Section
    /// Collapsed keeps every nav item as an icon-only rail instead of hiding the sidebar
    /// outright — same idea as Xcode/Mail's collapsed sidebar.
    let isCollapsed: Bool

    var body: some View {
        VStack(alignment: isCollapsed ? .center : .leading, spacing: DS.Space.section) {
            BrandMark()
                .frame(width: 28, height: 28)

            VStack(alignment: isCollapsed ? .center : .leading, spacing: DS.Space.snug) {
                ForEach(MainWindow.Section.allCases) { candidate in
                    NavRow(section: candidate, isSelected: section == candidate, isCollapsed: isCollapsed) {
                        section = candidate
                    }
                }
            }

            Spacer()
        }
        .padding(isCollapsed ? DS.Space.base : DS.Space.wide)
        .frame(width: isCollapsed ? 64 : 240)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DS.Color.sidebarBackground)
    }
}

private struct NavRow: View {
    let section: MainWindow.Section
    let isSelected: Bool
    let isCollapsed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.base) {
                Image(systemName: section.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? DS.Color.primary : DS.Color.textSecondary)
                    .frame(width: 16)
                if !isCollapsed {
                    Text(section.title)
                        .font(DS.Font.navLabel)
                        .foregroundStyle(isSelected ? DS.Color.primary : DS.Color.textPrimary)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, DS.Space.base)
            .frame(height: 40)
            .frame(maxWidth: isCollapsed ? nil : .infinity)
            .background(isSelected ? DS.Color.primaryLight : .clear, in: .rect(cornerRadius: DS.Radius.control))
        }
        .buttonStyle(.plain)
        .help(section.title)
    }
}

// MARK: - Content area

private struct ContentArea: View {
    @Bindable var controller: DictationController
    let section: MainWindow.Section

    var body: some View {
        VStack(spacing: 0) {
            TopBar(controller: controller, section: section)

            switch section {
            case .dashboard: StatsDashboard()
            case .transcripts: TranscriptionsPage(controller: controller)
            case .dictionary: DictionaryPanel()
            case .settings: SettingsPageView(controller: controller)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DS.Color.background)
    }
}

private struct TopBar: View {
    @Bindable var controller: DictationController
    let section: MainWindow.Section

    var body: some View {
        HStack {
            Text(section.title)
                .font(DS.Font.pageTitle)
                .foregroundStyle(DS.Color.textPrimary)

            Spacer()

            switch section {
            case .dashboard, .transcripts:
                RecordControl(controller: controller)
            case .dictionary:
                EmptyView()
            case .settings:
                EmptyView()
            }
        }
        .padding(.horizontal, DS.Space.panel)
        .frame(height: 60)
    }
}

/// Record button + elapsed timer, shown on Dashboard and Transcripts — the two pages where
/// seeing your history makes "start another one" natural.
private struct RecordControl: View {
    @Bindable var controller: DictationController

    @State private var elapsed: TimeInterval = 0
    @State private var startedAt: Date?

    private var isRecording: Bool { controller.state.isActive }

    var body: some View {
        HStack(spacing: DS.Space.base) {
            if isRecording {
                Text(counterText)
                    .font(DS.Font.counter)
                    .foregroundStyle(DS.Color.textPrimary)
            }
            Button {
                if isRecording {
                    controller.stopButtonRecording()
                } else {
                    controller.startButtonRecording()
                }
            } label: {
                HStack(spacing: DS.Space.snug) {
                    Circle()
                        .fill(.white)
                        .frame(width: 8, height: 8)
                    Text(isRecording ? "Stop" : "Record")
                        .font(DS.Font.button)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, DS.Space.roomy)
                .frame(height: 36)
                .background(isRecording ? DS.Color.danger : DS.Color.primary, in: .rect(cornerRadius: DS.Radius.control))
            }
            .buttonStyle(.plain)
        }
        .onChange(of: controller.state.isActive) { _, active in
            startedAt = active ? Date() : nil
            if !active { elapsed = 0 }
        }
        .task(id: startedAt) {
            guard let startedAt else { return }
            while !Task.isCancelled {
                elapsed = Date().timeIntervalSince(startedAt)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private var counterText: String {
        let total = Int(elapsed)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

// MARK: - Transcripts page

private struct TranscriptionsPage: View {
    @Bindable var controller: DictationController
    @State private var store = RunStore.shared
    @State private var query = ""

    private var runs: [DictationRun] {
        let all = Array(store.runs.reversed())
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all }
        return all.filter { $0.text.localizedStandardContains(trimmed) }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(text: $query, placeholder: "Search transcripts")

            if runs.isEmpty {
                EmptyPage(
                    title: store.runs.isEmpty ? "No transcripts yet" : "No matches",
                    detail: store.runs.isEmpty ? "Hit Record to start dictating." : "Try a different search."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: DS.Space.base) {
                        ForEach(runs) { run in
                            TranscriptCard(run: run) {
                                withAnimation(DS.Motion.base) { RunLog.delete(run) }
                            }
                        }
                    }
                    .padding(DS.Space.panel)
                }
            }
        }
    }
}

private struct TranscriptCard: View {
    let run: DictationRun
    let onDelete: () -> Void

    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.snug) {
            Text(run.text)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: DS.Space.base) {
                Text("\(run.engine) · \(run.date.formatted(date: .omitted, time: .shortened))")
                    .font(DS.Font.meta)
                    .foregroundStyle(DS.Color.textTertiary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(run.text, forType: .string)
                    didCopy = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        didCopy = false
                    }
                } label: {
                    Text(didCopy ? "Copied" : "Copy")
                        .font(DS.Font.meta)
                        .foregroundStyle(DS.Color.textSecondary)
                        .padding(.horizontal, DS.Space.snug)
                        .frame(height: 24)
                        .background(DS.Color.surfaceSecondary, in: .rect(cornerRadius: DS.Radius.chip))
                }
                .buttonStyle(.plain)
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundStyle(DS.Color.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DS.Space.roomy)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.surface, in: .rect(cornerRadius: DS.Radius.card))
    }
}

// MARK: - Shared

struct SearchBar: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: DS.Space.base) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(DS.Color.textSecondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.textPrimary)
        }
        .padding(.horizontal, DS.Space.base)
        .frame(height: 36)
        .background(DS.Color.surface, in: .rect(cornerRadius: DS.Radius.control))
        .padding(.horizontal, DS.Space.panel)
        .padding(.vertical, DS.Space.roomy)
    }
}

struct EmptyPage: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: DS.Space.snug) {
            Text(title)
                .font(DS.Font.label)
                .foregroundStyle(DS.Color.textPrimary)
            Text(detail)
                .font(DS.Font.meta)
                .foregroundStyle(DS.Color.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
