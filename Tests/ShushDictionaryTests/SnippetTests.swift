import Testing
import Foundation
@testable import ShushDictionary

@Suite("Snippets")
struct SnippetTests {
    private let calendly = Snippet(cue: "my calendly", text: "calendly.com/you")

    @Test("matches the whole utterance regardless of case, punctuation and spacing")
    func matchesWholeUtterance() {
        for spoken in ["my calendly", "My Calendly.", "  my  calendly!  ", "my-calendly", "mycalendly"] {
            #expect(SnippetMatcher.match(spoken, in: [calendly]) == calendly)
        }
    }

    @Test("never fires on a cue inside a longer sentence")
    func ignoresPartialUtterance() {
        #expect(SnippetMatcher.match("send them my calendly please", in: [calendly]) == nil)
        #expect(SnippetMatcher.match("my calendly link", in: [calendly]) == nil)
    }

    @Test("disabled snippets and empty utterances never match")
    func disabledAndEmpty() {
        var off = calendly
        off.isEnabled = false
        #expect(SnippetMatcher.match("my calendly", in: [off]) == nil)
        #expect(SnippetMatcher.match("...", in: [calendly]) == nil)
    }

    @Test("decode accepts the documented shape, defaults enabled, drops blank rows")
    func decodeFile() throws {
        let json = """
        [
          {"cue": "my calendly", "text": "calendly.com/you"},
          {"cue": "intro email", "text": "Hey, would love to find time…", "enabled": false},
          {"cue": "  ", "text": "no cue"},
          {"cue": "no text", "text": ""}
        ]
        """
        let snippets = try SnippetFile.decode(Data(json.utf8))
        #expect(snippets.map(\.cue) == ["my calendly", "intro email"])
        #expect(snippets.map(\.isEnabled) == [true, false])
    }

    @Test("decode rejects JSON that is not a snippet array")
    func decodeRejectsWrongShape() {
        #expect(throws: (any Error).self) { try SnippetFile.decode(Data(#"{"my calendly": "x"}"#.utf8)) }
    }

    @Test("encode then decode round trips, multi-line text included")
    func roundTrip() throws {
        let original = [Snippet(cue: "sign off", text: "Best,\nTamer"), Snippet(cue: "site", text: "a.com/b", isEnabled: false)]
        let decoded = try SnippetFile.decode(SnippetFile.encode(original))
        #expect(decoded.map(\.cue) == original.map(\.cue))
        #expect(decoded.map(\.text) == original.map(\.text))
        #expect(decoded.map(\.isEnabled) == original.map(\.isEnabled))
    }

    @Test("merge overwrites a matching cue in place and appends the rest")
    func merge() {
        let existing = [calendly, Snippet(cue: "site", text: "old.com")]
        let imported = [Snippet(cue: "Site.", text: "new.com"), Snippet(cue: "sign off", text: "Best")]
        let merged = SnippetFile.merge(imported, into: existing)
        #expect(merged.map(\.cue) == ["my calendly", "site", "sign off"])
        #expect(merged[1].text == "new.com")
        #expect(merged[1].id == existing[1].id)
    }
}
