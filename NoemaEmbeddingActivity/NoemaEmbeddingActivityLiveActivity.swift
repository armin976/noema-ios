// NoemaEmbeddingActivityLiveActivity.swift
//
//  NoemaEmbeddingActivityLiveActivity.swift
//  NoemaEmbeddingActivity
//
//  Created by Armin Stamate on 13/08/2025.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct NoemaEmbeddingActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DatasetIndexingAttributes.self) { context in
            VStack(alignment: .leading, spacing: 6) {
                Text(context.attributes.name)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    ProgressView(value: max(0, min(1, context.state.progress)))
                        .progressViewStyle(.linear)
                    Text("\(Int(context.state.progress * 100))%")
                        .font(.caption)
                        .monospacedDigit()
                }

                Text(statusLine(stage: context.state.stage, message: context.state.message))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 8)
            .activityBackgroundTint(.black.opacity(0.12))
            .activitySystemActionForegroundColor(.accentColor)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("\(Int(context.state.progress * 100))%")
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(shortStageLabel(context.state.stage))
                        .font(.caption)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.name)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let m = context.state.message, !m.isEmpty {
                        Text(m)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            } compactLeading: {
                Text("\(Int(context.state.progress * 100))")
                    .font(.caption2)
                    .monospacedDigit()
            } compactTrailing: {
                Text(shortStageSymbol(context.state.stage))
                    .font(.caption2)
            } minimal: {
                Text(minimalGlyph(for: context.state.stage))
            }
        }
    }

    private func statusLine(stage: DatasetProcessingStage, message: String?) -> String {
        if let m = message, !m.isEmpty { return m }
        return stageLabel(stage)
    }

    private func stageLabel(_ s: DatasetProcessingStage) -> String {
        switch s {
        case .extracting: return "Extracting"
        case .compressing: return "Compressing"
        case .embedding: return "Embedding"
        case .completed: return "Ready"
        case .failed: return "Failed"
        }
    }

    private func shortStageLabel(_ s: DatasetProcessingStage) -> String {
        switch s {
        case .extracting: return "Extract"
        case .compressing: return "Compress"
        case .embedding: return "Embed"
        case .completed: return "Done"
        case .failed: return "Error"
        }
    }

    private func shortStageSymbol(_ s: DatasetProcessingStage) -> String {
        switch s {
        case .extracting: return "E"
        case .compressing: return "C"
        case .embedding: return "M"
        case .completed: return "✓"
        case .failed: return "!"
        }
    }

    private func minimalGlyph(for s: DatasetProcessingStage) -> String {
        switch s {
        case .extracting: return "⇩"
        case .compressing: return "⧉"
        case .embedding: return "∑"
        case .completed: return "✓"
        case .failed: return "!"
        }
    }
}

extension DatasetIndexingAttributes {
    fileprivate static var preview: DatasetIndexingAttributes {
        DatasetIndexingAttributes(datasetID: "HF/the-ds", name: "Sample Dataset")
    }
}

extension DatasetIndexingAttributes.ContentState {
    fileprivate static var extracting: DatasetIndexingAttributes.ContentState {
        DatasetIndexingAttributes.ContentState(datasetID: "HF/the-ds", name: "Sample Dataset", stage: .extracting, progress: 0.1, message: "Extracting…")
    }
    fileprivate static var embedding: DatasetIndexingAttributes.ContentState {
        DatasetIndexingAttributes.ContentState(datasetID: "HF/the-ds", name: "Sample Dataset", stage: .embedding, progress: 0.5, message: "Embedding…")
    }
    fileprivate static var completed: DatasetIndexingAttributes.ContentState {
        DatasetIndexingAttributes.ContentState(datasetID: "HF/the-ds", name: "Sample Dataset", stage: .completed, progress: 1.0, message: "Ready")
    }
}

#Preview("Notification", as: .content, using: DatasetIndexingAttributes.preview) {
   NoemaEmbeddingActivityLiveActivity()
} contentStates: {
    DatasetIndexingAttributes.ContentState.extracting
    DatasetIndexingAttributes.ContentState.embedding
    DatasetIndexingAttributes.ContentState.completed
}
