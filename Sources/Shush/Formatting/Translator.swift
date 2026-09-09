import Foundation
import Translation

/// On-device translation, run after the dictionary pass. Needs a known source language —
/// `TranslationSession(installedSource:target:)` has no "detect for me" mode, so this is a
/// no-op whenever `speechLanguage` is "auto" rather than a specific language.
enum Translator {
    static func translateToEnglish(_ text: String, sourceIdentifier: String) async -> String {
        guard !text.isEmpty, sourceIdentifier != "auto" else { return text }

        let source = Locale.Language(identifier: sourceIdentifier)
        guard source.languageCode?.identifier.lowercased() != "en" else { return text }

        let session = TranslationSession(installedSource: source, target: Locale.Language(identifier: "en"))
        guard await session.isReady else {
            Log.speech.info("translation pack for \(sourceIdentifier, privacy: .public) not installed — leaving text as-is")
            return text
        }

        do {
            return try await session.translate(text).targetText
        } catch {
            Log.speech.error("translation failed: \(error.localizedDescription)")
            return text
        }
    }
}
