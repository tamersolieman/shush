import Foundation

/// A short spoken cue that expands to a longer block of text: say "my calendly", get the link.
///
/// Unlike a dictionary correction this is never applied inside a sentence — see
/// `SnippetMatcher` for why the cue must be the whole utterance.
public struct Snippet: Identifiable, Codable, Hashable, Sendable {
    /// Not part of the file format; a fresh one is minted on every load.
    public var id = UUID()
    public var cue: String
    public var text: String
    public var isEnabled: Bool

    public init(id: UUID = UUID(), cue: String, text: String, isEnabled: Bool = true) {
        self.id = id
        self.cue = cue
        self.text = text
        self.isEnabled = isEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case cue, text
        case isEnabled = "enabled"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cue = try container.decode(String.self, forKey: .cue)
        text = try container.decode(String.self, forKey: .text)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }
}

/// Finds the snippet a finished utterance is asking for.
///
/// **Whole utterance only.** A cue like "intro email" would otherwise expand every time you
/// said those words in an ordinary sentence, and there is no undo for text that has already
/// been typed into someone else's app.
///
/// Comparison ignores case, diacritics, punctuation and spacing, because the engine and the
/// cleanup pass add all of those to what was said ("My Calendly." for "my calendly"), and
/// engines sometimes glue or split words ("mycalendly").
public enum SnippetMatcher {
    /// The comparison form of a cue or utterance. Empty means it has nothing to match on.
    public static func key(_ text: String) -> String {
        String(
            text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .filter { $0.isLetter || $0.isNumber }
        )
    }

    public static func match(_ utterance: String, in snippets: [Snippet]) -> Snippet? {
        let spoken = key(utterance)
        guard !spoken.isEmpty else { return nil }
        return snippets.first { $0.isEnabled && key($0.cue) == spoken }
    }
}

/// The JSON file snippets are stored in and imported from / exported to:
///
/// ```json
/// [{ "cue": "my calendly", "text": "calendly.com/you" }]
/// ```
///
/// `enabled` is optional and defaults to true, so a hand-written file stays short.
public enum SnippetFile {
    public static func decode(_ data: Data) throws -> [Snippet] {
        try JSONDecoder().decode([Snippet].self, from: data).filter {
            !SnippetMatcher.key($0.cue).isEmpty && !$0.text.isEmpty
        }
    }

    public static func encode(_ snippets: [Snippet]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(snippets)
    }

    /// Folds `imported` into `existing`. A cue that already exists keeps its place and takes
    /// the imported text; the rest are added in file order after it.
    public static func merge(_ imported: [Snippet], into existing: [Snippet]) -> [Snippet] {
        var merged = existing
        for incoming in imported {
            let incomingKey = SnippetMatcher.key(incoming.cue)
            if let index = merged.firstIndex(where: { SnippetMatcher.key($0.cue) == incomingKey }) {
                merged[index].text = incoming.text
                merged[index].isEnabled = incoming.isEnabled
            } else {
                merged.append(incoming)
            }
        }
        return merged
    }
}
