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

    /// Words before "sorry" that indicate a genuine apology rather than a retraction.
    private static let apologyPreceders: Set<String> = [
        "i", "im", "am", "was", "were", "feel", "so", "very", "really", "truly",
        "terribly", "awfully", "deeply",
    ]

    /// Words after "sorry" that indicate a genuine apology clause rather than a replacement word.
    private static let apologyFollowers: Set<String> = [
        "i", "for", "about", "to", "that", "if", "we", "you", "they", "it", "this", "my",
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

        if removeFillerWords { text = stripFillers(from: text) }
        text = applySorryCorrections(in: text)
        text = removeConsecutiveDuplicates(in: text)
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
            let pattern = "(?i)(?<![\\w'-])\(escaped)(?![\\w'-]),?"
            result = result.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }
        return result
    }

    /// Replaces simple `"<word>,? sorry,? <word>"` single-word retractions while leaving
    /// genuine apologies like `"I'm sorry I missed..."` intact.
    private func applySorryCorrections(in text: String) -> String {
        let pattern = "(?i)(?<![\\w'])([\\p{L}\\d]+),?[ \\t]+sorry,?[ \\t]+([\\p{L}\\d]+)(?![\\w'])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return text }

        let result = NSMutableString(string: text)
        for match in matches.reversed() {
            let retracted = nsText.substring(with: match.range(at: 1))
            let replacement = nsText.substring(with: match.range(at: 2))
            if Self.apologyPreceders.contains(retracted.lowercased())
                || Self.apologyFollowers.contains(replacement.lowercased()) {
                continue
            }
            result.replaceCharacters(in: match.range, with: replacement)
        }
        return result as String
    }

    private func removeConsecutiveDuplicates(in text: String) -> String {
        var result = text
        let pattern = "(?i)(?<![\\w'])([\\p{L}]+)[ \\t]+\\1(?![\\w'])"
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
