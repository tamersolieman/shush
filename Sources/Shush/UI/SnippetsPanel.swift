import ShushDictionary
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Snippets: add, edit, delete, search, import and export as JSON.
///
/// Laid out like `DictionaryPanel` on purpose — same search/add bar, same row and editor
/// shapes — so the two pages read as one family.
struct SnippetsPanel: View {
    @State private var store = SnippetStore.shared
    @State private var query = ""
    @State private var editing: Snippet?
    @State private var isAdding = false
    @State private var justAddedID: UUID?
    @State private var notice: (text: String, isError: Bool)?

    private var snippets: [Snippet] { store.filtered(by: query) }

    /// Clears the search first: an active filter would hide the snippet that was just saved,
    /// which reads as "it wasn't recorded".
    private func markAdded(_ snippet: Snippet) {
        query = ""
        store.add(snippet)
        justAddedID = snippet.id
        Task {
            try? await Task.sleep(for: .seconds(3))
            if justAddedID == snippet.id { withAnimation(DS.Motion.base) { justAddedID = nil } }
        }
    }

    private func show(_ text: String, isError: Bool = false) {
        notice = (text, isError)
        Task {
            try? await Task.sleep(for: .seconds(4))
            if notice?.text == text { withAnimation(DS.Motion.base) { notice = nil } }
        }
    }

    private func importJSON() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let count = try store.importFile(at: url)
            show("Imported \(count) snippet\(count == 1 ? "" : "s")")
        } catch {
            show("Couldn't import — expected a JSON array of {\"cue\", \"text\"}.", isError: true)
        }
    }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "snippets.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.export(to: url)
            show("Exported \(store.snippets.count) snippet\(store.snippets.count == 1 ? "" : "s")")
        } catch {
            show("Couldn't export: \(error.localizedDescription)", isError: true)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.base) {
                SearchBar(text: $query, placeholder: "Search snippets")
                    .padding(.trailing, 0)
                Button { isAdding = true } label: {
                    HStack(spacing: DS.Space.tight) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Add")
                            .font(DS.Font.button)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, DS.Space.roomy)
                    .frame(height: 36)
                    .background(DS.Color.primary, in: .rect(cornerRadius: DS.Radius.control))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("n", modifiers: .command)
            }
            .padding(.trailing, DS.Space.panel)

            if snippets.isEmpty {
                EmptyPage(
                    title: store.snippets.isEmpty ? "No snippets yet" : "No matches",
                    detail: store.snippets.isEmpty
                        ? "Say a short cue and Shush types the full text. Add one, or import a JSON file below."
                        : "Try a different search."
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: DS.Space.base) {
                            ForEach(snippets) { snippet in
                                SnippetRow(
                                    snippet: snippet,
                                    isHighlighted: snippet.id == justAddedID,
                                    onEdit: { editing = snippet },
                                    onToggle: {
                                        var updated = snippet
                                        updated.isEnabled.toggle()
                                        store.update(updated)
                                    },
                                    onDelete: { store.delete(snippet) }
                                )
                            }
                        }
                        .padding(DS.Space.panel)
                        .padding(.top, 0)
                    }
                    .onChange(of: justAddedID) { _, id in
                        guard let id else { return }
                        withAnimation(DS.Motion.base) { proxy.scrollTo(id, anchor: .top) }
                    }
                }
            }

            footer
        }
        .sheet(isPresented: $isAdding) {
            SnippetEditor(snippet: nil) { markAdded($0) }
        }
        .sheet(item: $editing) { snippet in
            SnippetEditor(snippet: snippet) { store.update($0) }
        }
    }

    private var footer: some View {
        HStack(spacing: DS.Space.roomy) {
            footerStatus
            Spacer()
            footerButton("Import JSON…", action: importJSON)
            footerButton("Export JSON…", action: exportJSON)
                .disabled(store.snippets.isEmpty)
        }
        .padding(.horizontal, DS.Space.panel)
        .padding(.vertical, DS.Space.base)
        .overlay(alignment: .top) {
            Rectangle().fill(DS.Color.divider).frame(height: DS.Border.hairline)
        }
    }

    @ViewBuilder
    private var footerStatus: some View {
        if let notice {
            Text(notice.text)
                .font(DS.Font.meta)
                .foregroundStyle(notice.isError ? DS.Color.warning : DS.Color.primary)
        } else {
            Text(justAddedID == nil ? "\(store.snippets.count) snippets" : "Saved · \(store.snippets.count) snippets")
                .font(DS.Font.meta)
                .foregroundStyle(justAddedID == nil ? DS.Color.textTertiary : DS.Color.primary)
        }
    }

    private func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(DS.Font.meta)
                .foregroundStyle(DS.Color.textSecondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Row

private struct SnippetRow: View {
    let snippet: Snippet
    let isHighlighted: Bool
    let onEdit: () -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.tight) {
            HStack(spacing: DS.Space.base) {
                Text(snippet.cue)
                    .font(DS.Font.label)
                    .foregroundStyle(DS.Color.textPrimary)

                Spacer()

                if isHovering {
                    rowButton("Edit", action: onEdit)
                    rowButton("Delete", action: onDelete)
                }

                Toggle("", isOn: Binding(get: { snippet.isEnabled }, set: { _ in onToggle() }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(DS.Color.primary)
            }

            Text(snippet.text)
                .font(DS.Font.meta)
                .foregroundStyle(DS.Color.textTertiary)
                .lineLimit(2)
        }
        .opacity(snippet.isEnabled ? 1 : 0.5)
        .padding(DS.Space.roomy)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHighlighted ? DS.Color.primaryLight : DS.Color.surface, in: .rect(cornerRadius: DS.Radius.card))
        .onHover { isHovering = $0 }
    }

    private func rowButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(DS.Font.meta)
                .foregroundStyle(DS.Color.textSecondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Editor

private struct SnippetEditor: View {
    let snippet: Snippet?
    let onSave: (Snippet) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var cue: String
    @State private var text: String
    @State private var selection: TextSelection?

    init(snippet: Snippet?, onSave: @escaping (Snippet) -> Void) {
        self.snippet = snippet
        self.onSave = onSave
        _cue = State(initialValue: snippet?.cue ?? "")
        _text = State(initialValue: snippet?.text ?? "")
    }

    private var draft: Snippet {
        Snippet(
            id: snippet?.id ?? UUID(),
            cue: cue.trimmingCharacters(in: .whitespacesAndNewlines),
            text: text,
            isEnabled: snippet?.isEnabled ?? true
        )
    }

    private var isDuplicate: Bool {
        SnippetStore.shared.hasCue(draft.cue, excluding: snippet?.id)
    }

    private var isValid: Bool {
        !SnippetMatcher.key(draft.cue).isEmpty
            && !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isDuplicate
    }

    /// With no selection yet (the box was never focused) the edit lands at the end.
    private func format(_ style: SnippetFormat.Style) {
        var lower = text.count
        var upper = lower
        if case .selection(let range)? = selection?.indices {
            lower = text.distance(from: text.startIndex, to: range.lowerBound)
            upper = text.distance(from: text.startIndex, to: range.upperBound)
        }
        let edit = SnippetFormat.apply(style, to: text, selection: lower..<upper)
        text = edit.text
        selection = TextSelection(range:
            text.index(text.startIndex, offsetBy: edit.selection.lowerBound)
                ..< text.index(text.startIndex, offsetBy: edit.selection.upperBound)
        )
    }

    private var formatBar: some View {
        HStack(spacing: DS.Space.tight) {
            formatButton("bold", "Bold", .bold)
            formatButton("italic", "Italic", .italic)
            barDivider
            formatButton("list.bullet", "Bulleted list", .bulletList)
            formatButton("list.number", "Numbered list", .numberedList)
            barDivider
            formatButton("link", "Link", .link)
        }
        .padding(.vertical, DS.Space.tight)
    }

    private var barDivider: some View {
        Rectangle().fill(DS.Color.divider).frame(width: DS.Border.hairline, height: 16)
    }

    private func formatButton(_ symbol: String, _ label: String, _ style: SnippetFormat.Style) -> some View {
        Button { format(style) } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.Color.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.roomy) {
            Text(snippet == nil ? "New snippet" : "Edit snippet")
                .font(DS.Font.pageTitle)
                .foregroundStyle(DS.Color.textPrimary)

            VStack(alignment: .leading, spacing: DS.Space.base) {
                FormField("When you say") {
                    TextField("my calendly", text: $cue).frame(height: 32)
                }
                FormField("Type") {
                    VStack(alignment: .leading, spacing: 0) {
                        formatBar
                        TextEditor(text: $text, selection: $selection)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 120, maxHeight: 200)
                    }
                }
            }

            Text("Only fires when the cue is all you say, never inside a longer sentence. Formatting is typed as Markdown, so it renders where Markdown does.")
                .font(DS.Font.meta)
                .foregroundStyle(DS.Color.textTertiary)

            if isDuplicate {
                HStack(alignment: .top, spacing: DS.Space.snug) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Color.warning)
                    Text("Another snippet already uses this cue.")
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.textPrimary)
                }
                .padding(DS.Space.base)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.Color.warning.opacity(0.1), in: .rect(cornerRadius: DS.Radius.control))
            }

            HStack(spacing: DS.Space.snug) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .padding(.horizontal, DS.Space.roomy)
                    .frame(height: 32)
                    .background(DS.Color.surfaceSecondary, in: .rect(cornerRadius: DS.Radius.control))
                Button {
                    guard isValid else { return }
                    onSave(draft)
                    dismiss()
                } label: {
                    Text("Save")
                        .foregroundStyle(.white)
                        .padding(.horizontal, DS.Space.roomy)
                        .frame(height: 32)
                        .background(DS.Color.primary, in: .rect(cornerRadius: DS.Radius.control))
                }
                .buttonStyle(.plain)
                .disabled(!isValid)
                .opacity(isValid ? 1 : 0.5)
            }
        }
        .padding(DS.Space.panel)
        .frame(width: 460)
        .background(DS.Color.background)
    }
}
