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

    static func general(currentFormat: ModelFormat? = nil, isVisionCapable: Bool = false, hasAttachedImages: Bool = false) -> String {
        var text = sanitize(SystemPreset.general.text)
        // Vision guidance: if the active model is vision-capable, add concise
        // instructions to avoid invented image details, whether or not images
        // are attached.
        if isVisionCapable {
            if hasAttachedImages {
                text += "\n\nVision: One or more images are attached. Use them to answer the question. Describe only what is actually present. If unsure, say you are unsure. Do not invent details."
            } else {
                text += "\n\nIMPORTANT: No image is provided unless explicitly attached. Answer as a text-only assistant. Do not infer, imagine, or describe any images."
            }
        }
        if WebToolGate.isAvailable(currentFormat: currentFormat) {
            // Keep this instruction string aligned with ChatVM.systemPromptText
            let instr = "**WEB SEARCH (ARMED)**: Use the web search tool ONLY if the query needs fresh/current info; otherwise answer directly.\n\n**CALL FORMAT (JSON or XML)**:\n- JSON (respond with this object only; no backticks, no prose):\n{\n  \"tool_name\": \"noema.web.retrieve\",\n  \"arguments\": {\n    \"query\": \"...\",\n    \"count\": 3,\n    \"safesearch\": \"moderate\"\n  }\n}\n\n- XML (for models like Qwen; the JSON object above goes inside <tool_call>):\n<tool_call>\n{\n  \"name\": \"noema.web.retrieve\",\n  \"arguments\": {\n    \"query\": \"...\",\n    \"count\": 3,\n    \"safesearch\": \"moderate\"\n  }\n}\n</tool_call>\n\nRules:\n- Default to count 3; the maximum allowed is 5 and larger requests will be reduced to 5.\n- Decide first; only call if needed.\n- Make exactly one tool call and WAIT for the result.\n- Do NOT emit tool calls inside <think> or chain-of-thought. If you include a <think> section, always close it with </think> and place any <tool_call> (or JSON tool object) only AFTER the final </think>.\n- Do NOT output tool results yourself and NEVER put results inside <tool_call>; that tag wraps the call JSON only.\n- Do NOT use code fences (```); emit only the JSON or the <tool_call> wrapper.\n- Do not mix formats; choose JSON or XML, not both.\n- After results, answer with concise citations like [1], [2]."
            text += "\n\n" + instr
        }
        return text
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
}
