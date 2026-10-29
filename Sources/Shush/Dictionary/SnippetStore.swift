import ShushDictionary
import Foundation
import Observation

/// Snippets, persisted as `snippets.json` next to `dictionary.txt` in the app's Application
/// Support folder. The file is the same shape `Import`/`Export` use, so a backup is just a copy.
///
/// No file watcher, unlike `DictionaryStore`: JSON isn't something to hand-edit in a hurry, and
/// re-importing a file is the supported way to bring edits in.
@MainActor
@Observable
final class SnippetStore {
    static let shared = SnippetStore()

    private(set) var snippets: [Snippet] = []

    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Shush", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("snippets.json")
    }

    private init() {
        load()
    }

    // MARK: - Editing

    func add(_ snippet: Snippet) {
        snippets.insert(snippet, at: 0)
        save()
    }

    func update(_ snippet: Snippet) {
        guard let index = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        snippets[index] = snippet
        save()
    }

    func delete(_ snippet: Snippet) {
        snippets.removeAll { $0.id == snippet.id }
        save()
    }

    /// Case- and diacritic-insensitive search across the cue and the expansion.
    func filtered(by query: String) -> [Snippet] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return snippets }
        return snippets.filter {
            $0.cue.localizedStandardContains(trimmed) || $0.text.localizedStandardContains(trimmed)
        }
    }

    func match(_ utterance: String) -> Snippet? {
        SnippetMatcher.match(utterance, in: snippets)
    }

    /// Two snippets with the same cue would make one of them unreachable.
    func hasCue(_ cue: String, excluding id: UUID?) -> Bool {
        let key = SnippetMatcher.key(cue)
        return snippets.contains { $0.id != id && SnippetMatcher.key($0.cue) == key }
    }

    // MARK: - Import / export

    /// - Returns: how many snippets the file contained (new and overwritten alike).
    func importFile(at url: URL) throws -> Int {
        let imported = try SnippetFile.decode(Data(contentsOf: url))
        snippets = SnippetFile.merge(imported, into: snippets)
        save()
        return imported.count
    }

    func export(to url: URL) throws {
        try SnippetFile.encode(snippets).write(to: url, options: .atomic)
    }

    // MARK: - Sync

    /// Whether anything has ever been saved here, so a fresh Mac doesn't count as having data
    /// to contribute to its first sync.
    var hasFile: Bool { FileManager.default.fileExists(atPath: Self.fileURL.path) }

    func applyRemote(_ remote: [Snippet]) {
        snippets = remote
        save(pushToDrive: false)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL) else { return }
        do {
            snippets = try SnippetFile.decode(data)
        } catch {
            // Starting empty is fine; the next save overwriting a hand-edited file with a
            // typo in it is not. Move it aside so nothing is lost.
            Log.app.error("snippets.json unreadable (\(error.localizedDescription)) — moved to snippets.json.bak")
            let backup = Self.fileURL.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: Self.fileURL, to: backup)
        }
    }

    private func save(pushToDrive: Bool = true) {
        try? SnippetFile.encode(snippets).write(to: Self.fileURL, options: .atomic)
        if pushToDrive { SyncEngine.shared.scheduleSnippetsPush() }
    }
}
