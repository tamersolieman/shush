import Foundation

/// Detects "you just hand-corrected what Shush typed" from two snapshots of a text field —
/// what Shush injected, and what the field holds after the user's edit — and if so, what
/// dictionary rule that edit implies.
///
/// Prefix/suffix trimming rather than a general diff: a real correction is a single
/// contiguous span swapped in place (select the wrong word, retype it), and this finds
/// exactly that span in O(n) with no dependency. It deliberately does not attempt to handle
/// two separate edits in one pass — those fail the word-count bound below instead, which is
/// an acceptable, honest limitation rather than something worth a real diff algorithm for.
public enum CorrectionDiff {
    public struct Correction: Equatable, Sendable {
        public let hear: String
        public let write: String
    }

    private static let maxWords = 4
    private static let maxCharacters = 40

    /// Word-level trim, not character-level: a character-level common-suffix scan can eat
    /// into the very word that changed whenever it shares letters with itself case-shifted
    /// ("claude" → "Claude" share "laude"), leaving a bogus single-letter diff. Aligning on
    /// whitespace boundaries keeps the trimmed span a whole word or phrase.
    public static func detect(original: String, current: String) -> Correction? {
        // The user kept dictating/typing past the injected text — an append, not a
        // correction. Also covers current == original (no edit at all).
        guard current != original, !current.hasPrefix(original) else { return nil }

        let originalWords = words(in: original)
        let currentWords = words(in: current)

        var prefix = 0
        let maxPrefix = min(originalWords.count, currentWords.count)
        while prefix < maxPrefix, originalWords[prefix] == currentWords[prefix] {
            prefix += 1
        }

        var suffix = 0
        let maxSuffix = maxPrefix - prefix
        while suffix < maxSuffix,
              originalWords[originalWords.count - 1 - suffix] == currentWords[currentWords.count - 1 - suffix] {
            suffix += 1
        }

        let removedWords = Array(originalWords[prefix..<(originalWords.count - suffix)])
        let insertedWords = Array(currentWords[prefix..<(currentWords.count - suffix)])

        // Pure insertion (nothing replaced) or pure deletion (nothing to map to) — neither
        // is a substitution.
        guard !removedWords.isEmpty, !insertedWords.isEmpty else { return nil }
        guard removedWords.count <= maxWords, insertedWords.count <= maxWords else { return nil }

        let removed = removedWords.joined(separator: " ")
        let inserted = insertedWords.joined(separator: " ")
        guard removed.count <= maxCharacters, inserted.count <= maxCharacters else { return nil }

        // Same letters, different punctuation/whitespace only ("world" → "world.") isn't a
        // correction worth learning. Case is preserved through this check on purpose — a
        // case-only fix ("claude" → "Claude") is a legitimate correction.
        guard lettersAndDigits(removed) != lettersAndDigits(inserted) else { return nil }
        guard !lettersAndDigits(removed).isEmpty else { return nil }

        return Correction(hear: removed, write: inserted)
    }

    private static func words(in text: String) -> [String] {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init)
    }

    private static func lettersAndDigits(_ text: String) -> String {
        String(text.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}
