// IndexingNotificationView.swift
import SwiftUI
import UIKit

struct IndexingNotificationView: View {
    @ObservedObject var datasetManager: DatasetManager
    @EnvironmentObject var chatVM: ChatVM
    @State private var showCompletion = false
    @State private var hideNotification = false
    @State private var lastCompletedID: String?
    @State private var isExpanded = true
    @State private var didStartEmbedding = false
    @State private var showCancelConfirm = false
    @State private var showBatteryConfirm = false
    private let stageSequence: [DatasetProcessingStage] = [.extracting, .compressing, .embedding]
    
    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        if let id = datasetManager.indexingDatasetID {
            if let ds = datasetManager.datasets.first(where: { $0.datasetID == id }) {
                if let status = datasetManager.processingStatus[id] {
                    let needsConfirm = (status.stage == .embedding && status.progress <= 0.0001 && !didStartEmbedding)
                    if hideNotification && !needsConfirm {
                        EmptyView()
                    } else {
                        viewBody(id: id, ds: ds, status: status)
                    }
                } else { EmptyView() }
            } else { EmptyView() }
        } else { EmptyView() }
    }

    @ViewBuilder
    private func viewBody(id: String, ds: LocalDataset, status: DatasetProcessingStatus) -> some View {
        VStack(spacing: 8) {
            // Compact step indicator
            HStack(spacing: 8) {
                ForEach(stageSequence.indices, id: \.self) { index in
                    let stage = stageSequence[index]
                    Circle()
                        .fill(stageColor(stage, current: status.stage, isCompleted: showCompletion))
                        .frame(width: 12, height: 12)
                        .scaleEffect(showCompletion ? 1.2 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6).delay(Double(index) * 0.1), value: showCompletion)
                    if index < 2 {
                        Rectangle()
                            .fill(stageLineColor(index, current: status.stage, isCompleted: showCompletion))
                            .frame(width: 16, height: 1)
                            .animation(.easeInOut(duration: 0.3), value: status.stage)
                    }
                }
            }
            // Progress details or completion message
            if showCompletion {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                        .transition(.scale.combined(with: .opacity))
                    Text("Done!")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                    Text("Dataset ready to use")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                HStack(spacing: 8) {
                    Text("\(stageVerb(status.stage)) \(ds.name)")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if status.stage == .failed {
                        Text(isExpanded ? (status.message ?? stageLabel(.failed)) : (status.message ?? shortStageLabel(.failed)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(isExpanded ? stageLabel(status.stage) : shortStageLabel(status.stage))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if isExpanded {
                        Text("\(Int(status.progress * 100))% · \(etaString(status.etaSeconds))")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                // Confirmation gate for embedding step
                if status.stage == .embedding && status.progress <= 0.0001 && !didStartEmbedding {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Button {
                                if isPluggedIn() {
                                    didStartEmbedding = true
                                    Task {
                                        await chatVM.unload()
                                        self.datasetManager.startEmbeddingForID(ds.datasetID)
                                    }
                                } else {
                                    showBatteryConfirm = true
                                }
                            } label: {
                                Text("Confirm and Start Embedding")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.15))
                                    .foregroundColor(.blue)
                                    .cornerRadius(8)
                            }
                            .confirmationDialog("Proceed on battery power?", isPresented: $showBatteryConfirm, titleVisibility: .visible) {
                                Button("Proceed") {
                                    didStartEmbedding = true
                                    Task {
                                        await chatVM.unload()
                                        self.datasetManager.startEmbeddingForID(ds.datasetID)
                                    }
                                }
                                Button("Cancel", role: .cancel) {}
                            } message: {
                                Text("Embedding is resource intensive. For best performance, plug in your phone. Do you want to proceed on battery?")
                            }
                            Button {
                                showCancelConfirm = true
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                            .confirmationDialog("Cancel Embedding?", isPresented: $showCancelConfirm, titleVisibility: .visible) {
                                Button("Cancel Embedding", role: .destructive) {
                                    didStartEmbedding = false
                                    hideNotification = false
                                    datasetManager.processingStatus[ds.datasetID] = nil
                                    datasetManager.indexingDatasetID = nil
                                }
                                Button("Continue", role: .cancel) {}
                            } message: { Text("You can restart this process in the dataset settings any time.") }
                        }
                        Text("For best performance, please plug in your phone until this completes.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            // Compact progress bar (hidden when completed)
            if !showCompletion {
                ModernProgressView(value: status.progress, tint: .blue, height: 3)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: UIDevice.current.userInterfaceIdiom == .pad ? 460 : .infinity)
        .background(
            RoundedRectangle(cornerRadius: UIDevice.current.userInterfaceIdiom == .pad ? 16 : 12)
                .fill(.thinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
        .contextMenu {
            Button(role: .destructive) {
                withAnimation(.easeInOut(duration: 0.3)) { hideNotification = true }
            } label: { Label("Dismiss", systemImage: "xmark.circle") }
        }
        .opacity(1.0)
        .padding(.horizontal, UIDevice.current.userInterfaceIdiom == .pad ? 0 : 16)
        .opacity(isExpanded ? 1 : 0)
        .animation(.easeInOut(duration: 0.25), value: isExpanded)
        .overlay(alignment: .topLeading) {
            Button(action: { withAnimation(.easeInOut(duration: 0.25)) { isExpanded = true } }) {
                ZStack {
                    Circle().fill(Color.blue.opacity(0.9)).frame(width: 28, height: 28)
                    Text("\(Int(status.progress * 100))")
                        .font(.system(size: 11)).bold().monospacedDigit()
                        .foregroundColor(.white)
                }
            }
            .padding(6)
            .opacity(isExpanded ? 0 : 1)
            .animation(.easeInOut(duration: 0.25), value: isExpanded)
        }
        .onChange(of: status.stage) { newStage in
            if newStage == .embedding {
                if status.progress <= 0.0001 {
                    withAnimation(.spring()) {
                        hideNotification = false
                        isExpanded = true
                    }
                }
            }
        }
        .onChange(of: id) { newID in
            if newID != lastCompletedID {
                hideNotification = false
                showCompletion = false
                isExpanded = true
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.25), value: hideNotification)
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.25)) {
                isExpanded = false
            }
        }
    }
    
    private func stageVerb(_ stage: DatasetProcessingStage) -> String {
        switch stage {
        case .extracting: return "Extracting"
        case .compressing: return "Compressing"
        case .embedding: return "Embedding"
        case .completed: return "Indexed"
        case .failed: return "Failed"
        }
    }

    private func stageColor(_ stage: DatasetProcessingStage, current: DatasetProcessingStage, isCompleted: Bool) -> Color {
        if isCompleted {
            return .green
        }
        
        switch (stage, current) {
        case (.extracting, .extracting), (.compressing, .compressing), (.embedding, .embedding):
            return .blue
        case (.extracting, .compressing), (.extracting, .embedding), (.compressing, .embedding):
            return .green
        default:
            return .gray.opacity(0.3)
        }
    }
    
    private func stageLineColor(_ index: Int, current: DatasetProcessingStage, isCompleted: Bool) -> Color {
        if isCompleted {
            return .green
        }
        
        switch (index, current) {
        case (0, .compressing), (0, .embedding), (1, .embedding):
            return .green
        default:
            return .gray.opacity(0.3)
        }
    }
    
    private func stageLabel(_ stage: DatasetProcessingStage) -> String {
        switch stage {
        case .extracting: return "Extracting"
        case .compressing: return "Compressing"
        case .embedding: return "Embedding"
        case .completed: return "Ready"
        case .failed: return "Failed"
        }
    }

    private func shortStageLabel(_ stage: DatasetProcessingStage) -> String {
        switch stage {
        case .extracting: return "Extract"
        case .compressing: return "Compress"
        case .embedding: return "Embed"
        case .completed: return "Done"
        case .failed: return "Error"
        }
    }

    private func etaString(_ etaSeconds: Double?) -> String {
        if let e = etaSeconds, e > 0 {
            return String(format: "~%dm %02ds", Int(e)/60, Int(e)%60)
        }
        return "…"
    }
}

@MainActor
private func isPluggedIn() -> Bool {
    UIDevice.current.isBatteryMonitoringEnabled = true
    let state = UIDevice.current.batteryState
    return state == .charging || state == .full
}