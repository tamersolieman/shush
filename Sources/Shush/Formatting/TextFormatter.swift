import Foundation

/// The cleanup pass between raw transcription and injection.
///
/// This is where Wispr Flow actually earns its keep — raw STT output is full of filler
/// words, missing punctuation, and spoken corrections. Swapping in an LLM-backed
/// formatter (Apple Foundation Models on-device, or Claude for the high-quality tier)
/// is the point of keeping this behind a protocol.
protocol TextFormatter: Sendable {
    func format(_ raw: String) async -> String
}

/// Deterministic, zero-latency cleanup. Good enough to be useful on its own and always
/// the fallback when a model-backed formatter is unavailable or times out.
struct RuleBasedFormatter: TextFormatter {
    var removeFillerWords: Bool = true

    /// Standalone filler words, ordered longest-first so hyphenated forms like "uh-huh"
    /// match before "uh".
    private static let fillers = ["uh-huh", "um", "uh", "erm", "uhm", "hmm", "mhm"]

    /// Short list of common English stutter words collapsed when repeated consecutively.
    /// Intentionally excludes expressive/grammatical doubles ("bye bye", "had had", "that
    /// that is true") and non-English words (e.g. Arabic "جدا جدا").
    private static let stutterWords: Set<String> = [
        "the", "a", "an", "i", "we", "you", "to", "of", "in", "it", "is",
        "and", "or", "but", "should", "can", "will",
    ]

    /// Spoken punctuation people actually use mid-dictation.
    private static let spokenPunctuation: [(String, String)] = [
        ("new paragraph", "\n\n"),
        ("new line", "\n"),
        ("open paren", " ("),
        ("close paren", ") "),
    ]

    func format(_ raw: String) async -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }

        if removeFillerWords {
            text = stripFillers(from: text)
            text = removeStutterDuplicates(in: text)
        }
        text = applySpokenPunctuation(to: text)
        text = collapseWhitespace(in: text)
        text = cleanOrphanCommas(in: text)
        text = capitalizeSentences(in: text)
        text = ensureTerminalPunctuation(in: text)

        return text
    }

    private func stripFillers(from text: String) -> String {
        var result = text
        for filler in Self.fillers {
            // Match the filler as a whole word, plus a trailing comma if the ASR added one.
            let escaped = NSRegularExpression.escapedPattern(for: filler)
            // A filler ending the text takes the comma before it along, so "I think so, um"
            // doesn't leave "I think so," — that comma is the pause, not part of the sentence.
            let trailing = "(?i)[ \\t]*,?[ \\t]*(?<![\\w'-])\(escaped)(?![\\w'-])[ \\t,]*$"
            result = result.replacingOccurrences(of: trailing, with: "", options: .regularExpression)
            let pattern = "(?i)(?<![\\w'-])\(escaped)(?![\\w'-]),?"
            result = result.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }
        return result
    }

    private func removeStutterDuplicates(in text: String) -> String {
        let joined = Self.stutterWords.joined(separator: "|")
        let pattern = "(?i)(?<![\\w'])(\(joined))[ \\t]+\\1(?![\\w'])"
        var result = text
        while true {
            let updated = result.replacingOccurrences(
                of: pattern,
                with: "$1",
                options: .regularExpression
            )
            if updated == result { break }
            result = updated
        }
        return result
    }

    private func cleanOrphanCommas(in text: String) -> String {
        text
            .replacingOccurrences(of: ",(?:[ \\t]*,)+", with: ",", options: .regularExpression)
            .replacingOccurrences(of: "(^|[.!?\\n])[ \\t]*,[ \\t]*", with: "$1 ", options: .regularExpression)
            .replacingOccurrences(of: ",[ \\t]*([.!?])", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func applySpokenPunctuation(to text: String) -> String {
        var result = text
        for (phrase, replacement) in Self.spokenPunctuation {
            result = result.replacingOccurrences(
                of: "(?i)\\b\(phrase)\\b",
                with: replacement,
                options: .regularExpression
            )
        }
        return result
    }

    private func collapseWhitespace(in text: String) -> String {
        text
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " +([,.!?;:])", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func capitalizeSentences(in text: String) -> String {
        var result = ""
        var capitalizeNext = true

        for character in text {
            if capitalizeNext, character.isLetter {
                result.append(Character(character.uppercased()))
                capitalizeNext = false
            } else {
                result.append(character)
                if ".!?\n".contains(character) { capitalizeNext = true }
            }
        }
        return result
    }

    private func ensureTerminalPunctuation(in text: String) -> String {
        guard let last = text.last, last.isLetter || last.isNumber else { return text }
        return text + "."
    }
}

/// No-op formatter, for comparing raw engine output against the cleanup pass.
struct PassthroughFormatter: TextFormatter {
    func format(_ raw: String) async -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
