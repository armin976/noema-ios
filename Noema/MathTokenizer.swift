// MathTokenizer.swift
//  MathTokenizer.swift
//  Noema
//
//  Splits text into text and LaTeX math segments.
//  Supports inline ($...$, \(...\)) and block ($$...$$, \[...\]) math.
//  Handles escaped dollars (\\$) so they are not treated as delimiters.

import Foundation

public enum MathToken: Equatable {
    case text(String)
    case inline(String)
    case block(String)
    /// Represents an unterminated/incomplete LaTeX segment (e.g., unclosed $, $$, \(, or \[).
    /// Renderers should show this as plain red text without attempting LaTeX formatting.
    case incomplete(String)
}

public struct MathTokenizer {
    /// Removes LaTeX boxing macros while preserving their contents.
    /// Supported patterns:
    /// - \boxed{arg}
    /// - \fbox{arg}
    /// - \framebox[...][...]{arg} (drops optional args)
    /// - \colorbox{color}{arg}
    /// - \fcolorbox{border}{bg}{arg}
    /// The transformation is applied recursively until no more box macros remain.
    private static func stripBoxing(_ input: String) -> String {
        guard !input.isEmpty else { return input }
        var s = input

        func isEscape(_ scalars: String.UnicodeScalarView, _ i: inout String.UnicodeScalarIndex) -> Bool {
            if i == scalars.startIndex { return false }
            let prev = scalars.index(before: i)
            return scalars[prev] == "\\".unicodeScalars.first!
        }

        // Find the matching closing '}' for a brace group starting at `openIdx` (which must point to '{').
        func findMatchingBrace(in text: String, from openIdx: String.Index) -> String.Index? {
            precondition(text[openIdx] == "{", "findMatchingBrace must start at '{'")
            var depth = 0
            var i = openIdx
            let end = text.endIndex
            while i < end {
                let ch = text[i]
                if ch == "\\" { // skip escaped next character
                    let next = text.index(after: i)
                    if next < end { i = text.index(after: next); continue }
                }
                if ch == "{" { depth += 1 }
                if ch == "}" {
                    depth -= 1
                    if depth == 0 { return i }
                }
                if i < end { i = text.index(after: i) }
            }
            return nil
        }

        // Parse optional bracket group like [ ... ] starting at idx if present.
        func skipOptionalBracket(in text: String, from idx: String.Index) -> String.Index {
            guard idx < text.endIndex, text[idx] == "[" else { return idx }
            var i = idx
            let end = text.endIndex
            var depth = 0
            while i < end {
                let ch = text[i]
                if ch == "\\" {
                    let n = text.index(after: i)
                    if n < end { i = text.index(after: n); continue }
                }
                if ch == "[" { depth += 1 }
                if ch == "]" {
                    depth -= 1
                    if depth == 0 { return text.index(after: i) }
                }
                i = text.index(after: i)
            }
            return idx // malformed; do not advance
        }

        func replaceFirstSingleArgMacro(name: String, in text: String) -> (String, Bool) {
            guard let range = text.range(of: "\\" + name) else { return (text, false) }
            var i = range.upperBound
            // Skip whitespace
            while i < text.endIndex, text[i].isWhitespace { i = text.index(after: i) }
            guard i < text.endIndex, text[i] == "{" else { return (text, false) }
            guard let close = findMatchingBrace(in: text, from: i) else { return (text, false) }
            let inner = text[text.index(after: i)..<close]
            let before = text[..<range.lowerBound]
            let after = text[text.index(after: close)..<text.endIndex]
            return (String(before) + String(inner) + String(after), true)
        }

        func replaceFirstFramebox(in text: String) -> (String, Bool) {
            guard let range = text.range(of: "\\framebox") else { return (text, false) }
            var i = range.upperBound
            // Skip whitespace
            while i < text.endIndex, text[i].isWhitespace { i = text.index(after: i) }
            // Optional [ ... ] width
            i = skipOptionalBracket(in: text, from: i)
            // Optional [ ... ] position
            i = skipOptionalBracket(in: text, from: i)
            // Required { ... } content
            guard i < text.endIndex, text[i] == "{" else { return (text, false) }
            guard let close = findMatchingBrace(in: text, from: i) else { return (text, false) }
            let inner = text[text.index(after: i)..<close]
            let before = text[..<range.lowerBound]
            let after = text[text.index(after: close)..<text.endIndex]
            return (String(before) + String(inner) + String(after), true)
        }

        func replaceFirstColorbox(in text: String) -> (String, Bool) {
            guard let range = text.range(of: "\\colorbox") else { return (text, false) }
            var i = range.upperBound
            while i < text.endIndex, text[i].isWhitespace { i = text.index(after: i) }
            // {color}
            guard i < text.endIndex, text[i] == "{" else { return (text, false) }
            guard let colorClose = findMatchingBrace(in: text, from: i) else { return (text, false) }
            var j = text.index(after: colorClose)
            while j < text.endIndex, text[j].isWhitespace { j = text.index(after: j) }
            guard j < text.endIndex, text[j] == "{" else { return (text, false) }
            guard let textClose = findMatchingBrace(in: text, from: j) else { return (text, false) }
            let inner = text[text.index(after: j)..<textClose]
            let before = text[..<range.lowerBound]
            let after = text[text.index(after: textClose)..<text.endIndex]
            return (String(before) + String(inner) + String(after), true)
        }

        func replaceFirstFColorbox(in text: String) -> (String, Bool) {
            guard let range = text.range(of: "\\fcolorbox") else { return (text, false) }
            var i = range.upperBound
            while i < text.endIndex, text[i].isWhitespace { i = text.index(after: i) }
            // {border}
            guard i < text.endIndex, text[i] == "{" else { return (text, false) }
            guard let borderClose = findMatchingBrace(in: text, from: i) else { return (text, false) }
            var j = text.index(after: borderClose)
            while j < text.endIndex, text[j].isWhitespace { j = text.index(after: j) }
            // {bg}
            guard j < text.endIndex, text[j] == "{" else { return (text, false) }
            guard let bgClose = findMatchingBrace(in: text, from: j) else { return (text, false) }
            var k = text.index(after: bgClose)
            while k < text.endIndex, text[k].isWhitespace { k = text.index(after: k) }
            // {text}
            guard k < text.endIndex, text[k] == "{" else { return (text, false) }
            guard let textClose = findMatchingBrace(in: text, from: k) else { return (text, false) }
            let inner = text[text.index(after: k)..<textClose]
            let before = text[..<range.lowerBound]
            let after = text[text.index(after: textClose)..<text.endIndex]
            return (String(before) + String(inner) + String(after), true)
        }

        while true {
            var changed = false
            // Single-arg boxers
            for name in ["boxed", "fbox"] {
                let (t, did) = replaceFirstSingleArgMacro(name: name, in: s)
                if did { s = t; changed = true }
            }
            // framebox with optional args
            do {
                let (t, did) = replaceFirstFramebox(in: s)
                if did { s = t; changed = true }
            }
            // colorbox and fcolorbox (keep only text argument)
            do {
                let (t, did) = replaceFirstColorbox(in: s)
                if did { s = t; changed = true }
            }
            do {
                let (t, did) = replaceFirstFColorbox(in: s)
                if did { s = t; changed = true }
            }
            if !changed { break }
        }
        return s
    }

    public static func tokenize(_ input: String) -> [MathToken] {
        guard !input.isEmpty else { return [] }
        var tokens: [MathToken] = []
        let end = input.endIndex
        var cursor = input.startIndex
        var textStart = cursor

        func isEscaped(_ idx: String.Index) -> Bool {
            if idx == input.startIndex { return false }
            var backslashes = 0
            var j = input.index(before: idx)
            while true {
                if input[j] == "\\" { backslashes += 1 } else { break }
                if j == input.startIndex { break }
                j = input.index(before: j)
            }
            return backslashes % 2 == 1
        }

        func flushText(upTo idx: String.Index) {
            if idx > textStart {
                tokens.append(.text(String(input[textStart..<idx])))
            }
        }

        while cursor < end {
            let ch = input[cursor]

            // Block $$ ... $$
            if ch == "$" && !isEscaped(cursor) {
                let next = input.index(after: cursor)
                if next < end && input[next] == "$" && !isEscaped(next) {
                    var i = input.index(after: next)
                    var close: String.Index?
                    while i < end {
                        if input[i] == "$" && !isEscaped(i) {
                            let i2 = input.index(after: i)
                            if i2 < end && input[i2] == "$" && !isEscaped(i2) { close = i; break }
                        }
                        i = input.index(after: i)
                    }
                    if let k = close {
                        flushText(upTo: cursor)
                        let contentStart = input.index(after: next)
                        let rawContent = input[contentStart..<k]
                        let trimmed = String(rawContent).trimmingCharacters(in: .whitespacesAndNewlines)
                        tokens.append(.block(stripBoxing(trimmed)))
                        cursor = input.index(after: input.index(after: k))
                        textStart = cursor
                        continue
                    } else {
                        // Incomplete $$ ... at end of input — treat remainder as incomplete LaTeX
                        flushText(upTo: cursor)
                        tokens.append(.incomplete(String(input[cursor..<end])))
                        cursor = end
                        textStart = cursor
                        break
                    }
                }
            }

            // Inline $ ... $
            if ch == "$" && !isEscaped(cursor) {
                func isAlphaNumeric(_ c: Character) -> Bool {
                    c.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
                }
                func isDigit(_ c: Character) -> Bool {
                    c.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
                }

                let prevChar: Character? = (cursor > input.startIndex) ? input[input.index(before: cursor)] : nil
                let prevIsAlphaNum = prevChar.map { isAlphaNumeric($0) } ?? false
                let nextIndex = input.index(after: cursor)

                // Find matching closing "$"
                var i = nextIndex
                var close: String.Index?
                while i < end {
                    if input[i] == "$" && !isEscaped(i) { close = i; break }
                    i = input.index(after: i)
                }

                guard let closingIndex = close else {
                    // No closing "$" — treat as a literal dollar sign (likely currency)
                    cursor = nextIndex
                    continue
                }

                // Slice out the candidate LaTeX content for additional heuristics.
                let contentRange = input.index(after: cursor)..<closingIndex
                let rawContent = String(input[contentRange])
                let trimmedContent = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)

                // If previous char is alphanumeric (e.g., "US$"), keep treating as literal.
                if prevIsAlphaNum {
                    cursor = nextIndex
                    continue
                }

                let firstNonSpaceChar = trimmedContent.first
                let beginsWithDigit = firstNonSpaceChar.map { isDigit($0) } ?? false

                if beginsWithDigit {
                    let containsMathOperator = rawContent.contains { "+-=×÷*/·^_%".contains($0) }
                    let containsLatexCommand = rawContent.contains("\\")
                    let hasInternalWhitespace = rawContent.contains { $0.isWhitespace }
                    let alnumOnly = !trimmedContent.isEmpty && trimmedContent.allSatisfy { isAlphaNumeric($0) }
                    let endsWithMathyChar: Bool = {
                        guard let last = trimmedContent.last else { return false }
                        if isDigit(last) { return true }
                        let trailingSet: Set<Character> = [")", "]", "}", ",", ".", ":", ";", "%", "!"]
                        return trailingSet.contains(last)
                    }()

                    let looksLikePlainCurrency = !containsMathOperator && !containsLatexCommand && !endsWithMathyChar && !(alnumOnly && !hasInternalWhitespace)
                    if looksLikePlainCurrency {
                        cursor = nextIndex
                        continue
                    }
                }

                flushText(upTo: cursor)
                let content = input[input.index(after: cursor)..<closingIndex]
                tokens.append(.inline(stripBoxing(String(content))))
                cursor = input.index(after: closingIndex)
                textStart = cursor
                continue
            }

            // Block \[ ... \] or inline \( ... \)
            if ch == "\\" {
                let remain = input[cursor..<end]
                if remain.hasPrefix("\\[") {
                    var i = input.index(cursor, offsetBy: 2)
                    var close: String.Index?
                    while i < end {
                        if input[i] == "\\" {
                            let n = input.index(after: i)
                            if n < end && input[n] == "]" { close = i; break }
                        }
                        i = input.index(after: i)
                    }
                    if let k = close {
                        flushText(upTo: cursor)
                        let contentStart = input.index(cursor, offsetBy: 2)
                        let content = input[contentStart..<k]
                        let trimmed = String(content).trimmingCharacters(in: .whitespacesAndNewlines)
                        tokens.append(.block(stripBoxing(trimmed)))
                        cursor = input.index(after: input.index(after: k))
                        textStart = cursor
                        continue
                    } else {
                        // Incomplete \[ ... at end of input — treat remainder as incomplete LaTeX
                        flushText(upTo: cursor)
                        tokens.append(.incomplete(String(input[cursor..<end])))
                        cursor = end
                        textStart = cursor
                        break
                    }
                } else if remain.hasPrefix("\\(") {
                    var i = input.index(cursor, offsetBy: 2)
                    var close: String.Index?
                    while i < end {
                        if input[i] == "\\" {
                            let n = input.index(after: i)
                            if n < end && input[n] == ")" { close = i; break }
                        }
                        i = input.index(after: i)
                    }
                    if let k = close {
                        flushText(upTo: cursor)
                        let contentStart = input.index(cursor, offsetBy: 2)
                        let content = input[contentStart..<k]
                        tokens.append(.inline(stripBoxing(String(content))))
                        cursor = input.index(after: input.index(after: k))
                        textStart = cursor
                        continue
                    } else {
                        // Incomplete \( ... at end of input — treat remainder as incomplete LaTeX
                        flushText(upTo: cursor)
                        tokens.append(.incomplete(String(input[cursor..<end])))
                        cursor = end
                        textStart = cursor
                        break
                    }
                }
            }

            cursor = input.index(after: cursor)
        }

        flushText(upTo: end)
        return tokens
    }

    // Helper to compute text length already captured so we can slice remaining prefix when building tokens incrementally.
    // We only subtract lengths of consecutive leading .text tokens since we push prefixes eagerly.
    private static func tokenTextLength<T>(_: T) -> Int { 0 }
}
