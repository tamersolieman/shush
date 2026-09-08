import ShoshDictionary
import AppKit
import SwiftUI

/// The dictionary: add, edit, delete, search.
///
/// Both entry kinds live in one list rather than separate tabs — they're two shapes of the
/// same idea and you want to see everything you've taught it at once. The kind is carried by
/// a small tag on each row.
struct DictionaryPanel: View {
    @State private var store = DictionaryStore.shared
    @State private var query = ""
    @State private var editing: DictionaryEntry?
    @State private var isAdding = false

    private var entries: [DictionaryEntry] { store.filtered(by: query) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.base) {
                SearchBar(text: $query, placeholder: "Search dictionary")
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

            if entries.isEmpty {
                EmptyPage(
                    title: store.entries.isEmpty ? "Dictionary is empty" : "No matches",
                    detail: store.entries.isEmpty
                        ? "Add words it keeps getting wrong."
                        : "Try a different search."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: DS.Space.base) {
                        ForEach(entries) { entry in
                            DictionaryRow(
                                entry: entry,
                                onEdit: { editing = entry },
                                onToggle: {
                                    var updated = entry
                                    updated.isEnabled.toggle()
                                    store.update(updated)
                                },
                                onDelete: { store.delete(entry) }
                            )
                        }
                    }
                    .padding(DS.Space.panel)
                    .padding(.top, 0)
                }
            }

            footer
        }
        .sheet(isPresented: $isAdding) {
            DictionaryEditor(entry: nil) { store.add($0) }
        }
        .sheet(item: $editing) { entry in
            DictionaryEditor(entry: entry) { store.update($0) }
        }
    }

    /// The file path is shown because the spec asks for the dictionary to be editable outside
    /// the UI — which is only true if you can find it.
    private var footer: some View {
        HStack(spacing: DS.Space.snug) {
            Text("\(store.entries.count) entries")
                .font(DS.Font.meta)
                .foregroundStyle(DS.Color.textTertiary)
            Spacer()
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([DictionaryStore.fileURL])
            } label: {
                Text("Reveal dictionary.txt")
                    .font(DS.Font.meta)
                    .foregroundStyle(DS.Color.textTertiary)
            }
            .buttonStyle(.plain)
            .help(DictionaryStore.fileURL.path)
        }
        .padding(.horizontal, DS.Space.panel)
        .padding(.vertical, DS.Space.base)
        .overlay(alignment: .top) {
            Rectangle().fill(DS.Color.divider).frame(height: DS.Border.hairline)
        }
    }
}

// MARK: - Row

private struct DictionaryRow: View {
    let entry: DictionaryEntry
    let onEdit: () -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.tight) {
            HStack(spacing: DS.Space.base) {
                Text(entry.write)
                    .font(DS.Font.label)
                    .foregroundStyle(DS.Color.textPrimary)

                Text(entry.kind == .correction ? "Fix" : "Term")
                    .font(DS.Font.meta)
                    .foregroundStyle(DS.Color.textTertiary)
                    .padding(.horizontal, DS.Space.snug)
                    .frame(height: 18)
                    .background(DS.Color.surfaceSecondary, in: .rect(cornerRadius: DS.Radius.chip))

                Spacer()

                if isHovering {
                    rowButton("Edit", action: onEdit)
                    rowButton("Delete", action: onDelete)
                }

                Toggle("", isOn: Binding(get: { entry.isEnabled }, set: { _ in onToggle() }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(DS.Color.primary)
            }

            if entry.kind == .correction {
                Text("\(entry.hear) → \(entry.write)")
                    .font(DS.Font.meta)
                    .foregroundStyle(DS.Color.primary)
            }
        }
        .opacity(entry.isEnabled ? 1 : 0.5)
        .padding(DS.Space.roomy)
        .background(DS.Color.surface, in: .rect(cornerRadius: DS.Radius.card))
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

/// Add or edit one entry, with the false-positive warning shown live as you type.
private struct DictionaryEditor: View {
    let entry: DictionaryEntry?
    let onSave: (DictionaryEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var kind: DictionaryEntry.Kind
    @State private var hear: String
    @State private var write: String

    init(entry: DictionaryEntry?, onSave: @escaping (DictionaryEntry) -> Void) {
        self.entry = entry
        self.onSave = onSave
        _kind = State(initialValue: entry?.kind ?? .term)
        _hear = State(initialValue: entry?.hear ?? "")
        _write = State(initialValue: entry?.write ?? "")
    }

    private var draft: DictionaryEntry {
        DictionaryEntry(
            id: entry?.id ?? UUID(),
            kind: kind,
            write: write.trimmingCharacters(in: .whitespacesAndNewlines),
            hear: kind == .correction ? hear.trimmingCharacters(in: .whitespacesAndNewlines) : "",
            isEnabled: entry?.isEnabled ?? true
        )
    }

    private var warnings: [DictionaryWarning] { DictionaryWarning.check(draft) }

    private var isValid: Bool {
        !draft.write.isEmpty && (kind == .term || !draft.hear.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.roomy) {
            Text(entry == nil ? "New entry" : "Edit entry")
                .font(DS.Font.pageTitle)
                .foregroundStyle(DS.Color.textPrimary)

            kindPicker

            VStack(alignment: .leading, spacing: DS.Space.base) {
                if kind == .correction {
                    field("When you hear", text: $hear, prompt: "cloud code")
                }
                field(
                    kind == .correction ? "Write" : "Word or phrase",
                    text: $write,
                    prompt: kind == .correction ? "Claude Code" : "Anthropic"
                )
            }

            ForEach(warnings) { warning in
                HStack(alignment: .top, spacing: DS.Space.snug) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Color.warning)
                    Text(warning.message)
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
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

    private var kindPicker: some View {
        HStack(spacing: DS.Space.snug) {
            ForEach([DictionaryEntry.Kind.term, .correction], id: \.self) { candidate in
                Button {
                    withAnimation(DS.Motion.base) { kind = candidate }
                } label: {
                    Text(candidate == .term ? "Term" : "Correction")
                        .font(DS.Font.label)
                        .foregroundStyle(kind == candidate ? DS.Color.primary : DS.Color.textSecondary)
                        .padding(.horizontal, DS.Space.base)
                        .frame(height: 32)
                        .background(
                            kind == candidate ? DS.Color.primaryLight : DS.Color.surface,
                            in: .rect(cornerRadius: DS.Radius.control)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.tight) {
            Text(label)
                .font(DS.Font.sectionHeader)
                .foregroundStyle(DS.Color.textTertiary)
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.textPrimary)
                .padding(.horizontal, DS.Space.base)
                .frame(height: 32)
                .background(DS.Color.surface, in: .rect(cornerRadius: DS.Radius.control))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.control)
                        .strokeBorder(DS.Color.border, lineWidth: DS.Border.hairline)
                )
        }
    }
}
