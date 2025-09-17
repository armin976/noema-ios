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
                        let content = input[contentStart..<k]
                        tokens.append(.block(String(content)))
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
                // Heuristics: treat $ as currency or literal unless it clearly opens LaTeX
                // 1) If previous character is alphanumeric (e.g., "US$"), do NOT open math
                // 2) If next non-space character is a digit (e.g., "$50"), do NOT open math
                // 3) If no matching closing "$" exists later, treat this "$" as literal

                func isAlphaNumeric(_ c: Character) -> Bool {
                    return c.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
                }
                func isWhitespace(_ c: Character) -> Bool {
                    return c.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
                }

                let prevChar: Character? = (cursor > input.startIndex) ? input[input.index(before: cursor)] : nil
                let nextIndex = input.index(after: cursor)
                var nextNonSpaceIndex = nextIndex
                while nextNonSpaceIndex < end && isWhitespace(input[nextNonSpaceIndex]) {
                    nextNonSpaceIndex = input.index(after: nextNonSpaceIndex)
                }
                let nextNonSpaceChar: Character? = (nextNonSpaceIndex < end) ? input[nextNonSpaceIndex] : nil

                let prevIsAlphaNum = prevChar.map { isAlphaNumeric($0) } ?? false
                let nextIsDigit = nextNonSpaceChar.map { $0.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) } } ?? false

                // If it's obviously not an opener, treat "$" as literal text
                if prevIsAlphaNum || nextIsDigit {
                    cursor = input.index(after: cursor)
                    continue
                }

                // Try to find a matching closing "$"
                var i = input.index(after: cursor)
                var close: String.Index?
                while i < end {
                    if input[i] == "$" && !isEscaped(i) { close = i; break }
                    i = input.index(after: i)
                }
                if let k = close {
                    flushText(upTo: cursor)
                    let content = input[input.index(after: cursor)..<k]
                    tokens.append(.inline(String(content)))
                    cursor = input.index(after: k)
                    textStart = cursor
                    continue
                } else {
                    // No closing "$" — treat this as a literal dollar sign (likely currency)
                    cursor = input.index(after: cursor)
                    continue
                }
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
                        tokens.append(.block(String(content)))
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
                        tokens.append(.inline(String(content)))
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

