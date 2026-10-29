import Foundation

extension DictionaryEntry {
    /// What makes two entries "the same rule": a correction is identified by what is heard, a
    /// term by its text. Case, diacritics and surrounding spaces don't count.
    var mergeKey: String {
        let basis = kind == .correction ? "c:\(hear)" : "t:\(write)"
        return basis
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Combines two copies of the dictionary when both changed since they last agreed (two
    /// Macs edited while apart). `local` wins on a rule both have, and a rule only one side
    /// has is kept — so a deletion made on only one side comes back, which is the safer
    /// mistake: losing a rule silently is worse than keeping a stale one.
    public static func union(local: [DictionaryEntry], remote: [DictionaryEntry]) -> [DictionaryEntry] {
        var seen = Set(local.map(\.mergeKey))
        return local + remote.filter { seen.insert($0.mergeKey).inserted }
    }
}
