// SystemPreset.swift
import Foundation

/// Predefined system prompt presets. Exactly one may be active at a time.
enum SystemPreset: String, CaseIterable, Identifiable {
    case general
    case rag

    var id: String { rawValue }

    /// Text associated with each preset.
    var text: String {
        switch self {
        case .general:
            return "You are a concise, helpful assistant. Use clear markdown with headings and bullet lists where appropriate, and separate paragraphs with blank lines. Do not include step-by-step or 'Step N:' enumerations in the final answer. If information is missing, ask a brief clarifying question."
        case .rag:
            return "You are a retrieval-focused assistant. Prioritize the provided context and cite sources inline (e.g., [1], [2]) for claims grounded in that context. You may also use your general knowledge when it helps answer the question; do not fabricate citations for non-context knowledge. Use clear markdown with headings and bullet lists, separated by blank lines. Do not include step-by-step or 'Step N:' enumerations in the final answer."
        }
    }

    var displayName: String {
        switch self {
        case .general: return "General"
        case .rag: return "RAG"
        }
    }
}
