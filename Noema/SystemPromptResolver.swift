// SystemPromptResolver.swift
import Foundation

/// Centralized resolver for the active system prompt text so every backend and
/// tool path stays in sync with the same guidance and web-search instructions.
enum SystemPromptResolver {
    /// Returns the general system prompt text with optional web tool guidance
    /// appended when the web search tool is available/armed.
    static func general(currentFormat: ModelFormat? = nil) -> String {
        // Backwards-compatible overload used by existing call sites; no vision hints.
        return general(currentFormat: currentFormat, isVisionCapable: false, hasAttachedImages: false)
    }

    static func general(
        currentFormat: ModelFormat? = nil,
        isVisionCapable: Bool = false,
        hasAttachedImages: Bool = false,
        attachedImageCount: Int? = nil,
        includeThinkRestriction: Bool = true,
        webGuidanceOverride: Bool? = nil
    ) -> String {
        var text = sanitize(SystemPreset.general.text)
        text += "\n\n" + currentDateTimeLine()
        // Vision guidance: if the active model is vision-capable, add concise
        // instructions to avoid invented image details, whether or not images
        // are attached.
        if isVisionCapable {
            if hasAttachedImages {
                if let count = attachedImageCount {
                    let plural = count == 1 ? "image" : "images"
                    text += "\n\nVision: \(count) \(plural) attached. Use them to answer the question. Describe only what is actually present. If unsure, say you are unsure. Do not invent details."
                } else {
                    text += "\n\nVision: One or more images are attached. Use them to answer the question. Describe only what is actually present. If unsure, say you are unsure. Do not invent details."
                }
            } else {
                text += "\n\nIMPORTANT: No image is provided unless explicitly attached. Answer as a text-only assistant. Do not infer, imagine, or describe any images."
            }
        }
        let shouldIncludeWebGuidance = webGuidanceOverride ?? WebToolGate.isAvailable(currentFormat: currentFormat)
        if shouldIncludeWebGuidance {
            // Keep this instruction string aligned with ChatVM.systemPromptText via shared helper.
            appendWebSearchGuidance(to: &text, includeThinkRestriction: includeThinkRestriction)
        }
        return text
    }

    static func currentDateTimeLine() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "MMMM d, yyyy 'at' HH:mm zzz"
        let now = Date()
        return "Current date and time: \(formatter.string(from: now)). Treat this timestamp as authoritative even if it conflicts with your internal knowledge."
    }

    /// Removes accidental anti-reasoning directives while preserving the
    /// intended guidance text.
    static func sanitize(_ s: String) -> String {
        var t = s
        let patterns = ["/nothink", "\\bnothink\\b", "no-think", "no think"]
        for p in patterns {
            if let rx = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) {
                let range = NSRange(location: 0, length: (t as NSString).length)
                t = rx.stringByReplacingMatches(in: t, options: [], range: range, withTemplate: "")
            } else {
                t = t.replacingOccurrences(of: p, with: "", options: .caseInsensitive)
            }
        }
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Shared web-search guidance so system prompts remain consistent across clients.
    static func webSearchGuidance(includeThinkRestriction: Bool) -> String {
        let header = """
**WEB SEARCH (ARMED)**: Use the web search tool ONLY if the query needs fresh/current info; otherwise answer directly.

**CALL FORMAT (respond exactly as shown; no extra text):**
<tool_call>
{
  \"name\": \"noema.web.retrieve\",
  \"arguments\": {
    \"query\": \"...\",
    \"count\": 3,
    \"safesearch\": \"moderate\"
  }
}
</tool_call>

Rules:
"""

        var rules: [String] = [
            "- Default to count 3; use 5 only for very diverse queries (larger requests are reduced to 5).",
            "- Decide first; only call if needed.",
            "- Make exactly one tool call and WAIT for the result."
        ]

        if includeThinkRestriction {
            rules.append("- You may mention tools inside <think>, but finish reasoning and close the tag before emitting the <tool_call> tag that actually triggers the call.")
        }

        rules.append(contentsOf: [
            "- Do NOT use code fences (```); emit only the <tool_call> wrapper shown above.",
            "- When web search results arrive, treat them as the authoritative/latest information. Base your answer on them even if they conflict with your prior knowledge and do NOT question their legitimacy.",
            "- After results, answer with concise citations like [1], [2]."
        ])

        let rulesText = rules.joined(separator: "\n")
        return header + "\n" + rulesText
    }

    /// Appends the shared web-search guidance only when it has not already been
    /// added to the prompt string. Returns `true` when the guidance was appended
    /// and `false` when the existing text already contained it.
    @discardableResult
    static func appendWebSearchGuidance(to text: inout String, includeThinkRestriction: Bool) -> Bool {
        let guidance = webSearchGuidance(includeThinkRestriction: includeThinkRestriction)
        guard !text.contains(guidance) else { return false }
        text += "\n\n" + guidance
        return true
    }
}
