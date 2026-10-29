import Foundation

/// The edits behind the snippet editor's formatting bar, as pure text transforms.
///
/// Snippets are plain text that happens to contain Markdown, typed into the target app
/// verbatim — so formatting is just inserting the right symbols around the selection. Kept out
/// of the view so the toggling and line handling can be unit tested.
///
/// Italic uses `_` rather than `*` so it can never be confused with the `**` of bold when
/// deciding whether a selection is already wrapped.
///
/// Offsets are in `Character`s, not `String.Index`, so they stay valid across the edit.
public enum SnippetFormat {
    public enum Style: Sendable {
        case bold, italic, bulletList, numberedList, link
    }

    public struct Edit: Equatable, Sendable {
        public var text: String
        public var selection: Range<Int>
    }

    public static func apply(_ style: Style, to text: String, selection: Range<Int>) -> Edit {
        let chars = Array(text)
        let range = selection.clamped(to: 0..<chars.count)
        switch style {
        case .bold: return wrap(chars, range, marker: "**")
        case .italic: return wrap(chars, range, marker: "_")
        case .bulletList: return list(chars, range, numbered: false)
        case .numberedList: return list(chars, range, numbered: true)
        case .link: return link(chars, range)
        }
    }

    // MARK: - Inline

    /// Wraps the selection in `marker`, or unwraps it if the markers already sit right
    /// outside it. With nothing selected it inserts a pair and parks the cursor between.
    private static func wrap(_ chars: [Character], _ range: Range<Int>, marker: String) -> Edit {
        let mark = Array(marker)
        let width = mark.count
        var out = chars

        let hasBefore = range.lowerBound >= width
            && Array(chars[(range.lowerBound - width)..<range.lowerBound]) == mark
        let hasAfter = range.upperBound + width <= chars.count
            && Array(chars[range.upperBound..<(range.upperBound + width)]) == mark

        if hasBefore && hasAfter {
            out.removeSubrange(range.upperBound..<(range.upperBound + width))
            out.removeSubrange((range.lowerBound - width)..<range.lowerBound)
            return Edit(text: String(out), selection: (range.lowerBound - width)..<(range.upperBound - width))
        }

        out.insert(contentsOf: mark, at: range.upperBound)
        out.insert(contentsOf: mark, at: range.lowerBound)
        return Edit(text: String(out), selection: (range.lowerBound + width)..<(range.upperBound + width))
    }

    /// `[selection](url)` with the placeholder selected so typing replaces it. A selected
    /// URL becomes the target instead, with the label placeholder selected.
    private static func link(_ chars: [Character], _ range: Range<Int>) -> Edit {
        let selected = String(chars[range])
        let markdown: String
        let pick: Range<Int>

        if selected.hasPrefix("http://") || selected.hasPrefix("https://") {
            markdown = "[text](\(selected))"
            pick = 1..<5
        } else {
            let label = selected.isEmpty ? "text" : selected
            markdown = "[\(label)](url)"
            pick = selected.isEmpty ? 1..<5 : (label.count + 3)..<(label.count + 6)
        }

        var out = chars
        out.replaceSubrange(range, with: Array(markdown))
        return Edit(text: String(out), selection: (range.lowerBound + pick.lowerBound)..<(range.lowerBound + pick.upperBound))
    }

    // MARK: - Lists

    private enum Marker { case bullet, numbered }

    /// Prefixes every line the selection touches, or strips the prefixes when they are all
    /// already of this kind. A line of the other kind is converted rather than doubled up.
    private static func list(_ chars: [Character], _ range: Range<Int>, numbered: Bool) -> Edit {
        var start = range.lowerBound
        while start > 0 && chars[start - 1] != "\n" { start -= 1 }

        var end = range.upperBound
        if !range.isEmpty, end > start, chars[end - 1] == "\n" {
            end -= 1
        } else {
            while end < chars.count && chars[end] != "\n" { end += 1 }
        }

        let target: Marker = numbered ? .numbered : .bullet
        let lines = String(chars[start..<end]).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let isSingleLine = lines.count == 1
        let isBlank: (String) -> Bool = { $0.trimmingCharacters(in: .whitespaces).isEmpty }

        let considered = lines.filter { isSingleLine || !isBlank($0) }
        let removing = !considered.isEmpty && considered.allSatisfy { split($0).marker == target }

        var counter = 1
        let rewritten = lines.map { line -> String in
            guard isSingleLine || !isBlank(line) else { return line }
            let body = split(line).body
            if removing { return body }
            defer { counter += 1 }
            return (numbered ? "\(counter). " : "- ") + body
        }.joined(separator: "\n")

        var out = chars
        out.replaceSubrange(start..<end, with: Array(rewritten))
        let newEnd = start + rewritten.count
        return Edit(text: String(out), selection: range.isEmpty ? newEnd..<newEnd : start..<newEnd)
    }

    private static func split(_ line: String) -> (marker: Marker?, body: String) {
        if line.hasPrefix("- ") { return (.bullet, String(line.dropFirst(2))) }
        let digits = line.prefix { $0.isASCII && $0.isNumber }
        if !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") {
            return (.numbered, String(line.dropFirst(digits.count + 2)))
        }
        return (nil, line)
    }
}
