import Testing
@testable import ShushDictionary

@Suite("Snippet formatting")
struct SnippetFormatTests {
    private func apply(_ style: SnippetFormat.Style, _ text: String, _ selection: Range<Int>) -> SnippetFormat.Edit {
        SnippetFormat.apply(style, to: text, selection: selection)
    }

    @Test("bold wraps the selection and keeps the inner text selected")
    func boldWraps() {
        let edit = apply(.bold, "say hello now", 4..<9)
        #expect(edit.text == "say **hello** now")
        #expect(edit.selection == 6..<11)
    }

    @Test("bold on an already wrapped selection unwraps it")
    func boldToggles() {
        let wrapped = apply(.bold, "say hello now", 4..<9)
        let edit = apply(.bold, wrapped.text, wrapped.selection)
        #expect(edit.text == "say hello now")
        #expect(edit.selection == 4..<9)
    }

    @Test("with nothing selected a marker pair is inserted and the cursor sits between")
    func emptySelection() {
        let edit = apply(.italic, "ab", 1..<1)
        #expect(edit.text == "a__b")
        #expect(edit.selection == 2..<2)
    }

    @Test("italic inside bold wraps rather than unwrapping the bold")
    func italicInsideBold() {
        let edit = apply(.italic, "**x**", 2..<3)
        #expect(edit.text == "**_x_**")
    }

    @Test("bullet list prefixes every selected line and skips blank ones")
    func bulletLines() {
        let edit = apply(.bulletList, "one\n\ntwo", 0..<8)
        #expect(edit.text == "- one\n\n- two")
    }

    @Test("bullet list toggles off when every line already has one")
    func bulletToggles() {
        let edit = apply(.bulletList, "- one\n- two", 0..<11)
        #expect(edit.text == "one\ntwo")
    }

    @Test("numbered list numbers sequentially and converts bullet lines")
    func numberedConverts() {
        let edit = apply(.numberedList, "- one\ntwo\nthree", 0..<15)
        #expect(edit.text == "1. one\n2. two\n3. three")
    }

    @Test("a cursor on one line formats just that line, and a trailing newline is not swallowed")
    func lineBoundaries() {
        #expect(apply(.bulletList, "a\nb\nc", 2..<2).text == "a\n- b\nc")
        #expect(apply(.bulletList, "a\nb\nc", 0..<4).text == "- a\n- b\nc")
    }

    @Test("a cursor on an empty line starts a list")
    func emptyLineStartsList() {
        let edit = apply(.bulletList, "", 0..<0)
        #expect(edit.text == "- ")
        #expect(edit.selection == 2..<2)
    }

    @Test("link wraps a label, wraps a URL as the target, or inserts a template")
    func links() {
        let label = apply(.link, "see docs here", 4..<8)
        #expect(label.text == "see [docs](url) here")
        #expect(label.selection == 11..<14)

        let url = apply(.link, "https://a.com", 0..<13)
        #expect(url.text == "[text](https://a.com)")
        #expect(url.selection == 1..<5)

        let empty = apply(.link, "", 0..<0)
        #expect(empty.text == "[text](url)")
        #expect(empty.selection == 1..<5)
    }
}
