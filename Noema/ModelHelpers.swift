// ModelHelpers.swift
import Foundation

extension String {
    /// Detects if a model name indicates it's a reasoning model
    var isReasoningModel: Bool {
        let lowercased = self.lowercased()
        let reasoningPatterns = [
            "o1-", "o1_",
            "deepseek-r1", "deepseek_r1",
            "qwq", "qwen-qwq", "qwen_qwq",
            "reasoning", "reasoner",
            "step-by-step", "stepbystep",
            "chain-of-thought", "chainofthought", "cot"
        ]
        
        return reasoningPatterns.contains { pattern in
            lowercased.contains(pattern)
        }
    }
}

extension LocalModel {
    /// Indicates if this is a reasoning model based on its name or ID
    var isReasoningModel: Bool {
        return name.isReasoningModel || modelID.isReasoningModel
    }
}

extension ModelRecord {
    /// Indicates if this is a reasoning model based on its name or ID
    var isReasoningModel: Bool {
        return displayName.isReasoningModel || id.isReasoningModel
    }
}