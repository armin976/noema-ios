// DatasetRecommendationView.swift
import SwiftUI

struct DatasetRecommendationView: View {
    let datasetName: String
    let totalSizeBytes: Int64
    @Environment(\.dismiss) private var dismiss
    
    private var recommendation: DatasetRecommendationSystem.Recommendation {
        DatasetRecommendationSystem.recommendation(for: totalSizeBytes)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header with icon and category
                    VStack(spacing: 12) {
                        Image(systemName: recommendation.sizeCategory.iconName)
                            .font(.system(size: 60))
                            .foregroundColor(Color(recommendation.sizeCategory.iconColor))
                        
                        Text(recommendation.sizeCategory.rawValue)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text(recommendation.sizeCategory.description)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top)
                    
                    // Performance metrics
                    VStack(spacing: 16) {
                        MetricRow(
                            icon: "clock.fill",
                            title: "Estimated Embedding Time",
                            value: DatasetRecommendationSystem.formatTime(recommendation.estimatedEmbeddingTime),
                            color: .blue
                        )
                        
                        MetricRow(
                            icon: "memorychip.fill",
                            title: "Peak RAM Usage",
                            value: DatasetRecommendationSystem.formatRAM(recommendation.estimatedRAMUsage),
                            color: .purple
                        )
                        
                        MetricRow(
                            icon: "doc.fill",
                            title: "Dataset Size",
                            value: ByteCountFormatter.string(fromByteCount: totalSizeBytes, countStyle: .file),
                            color: .gray
                        )
                    }
                    .padding(.horizontal)
                    
                    // Performance note
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Performance Note", systemImage: "info.circle.fill")
                            .font(.headline)
                            .foregroundColor(.blue)
                        
                        Text(recommendation.performanceNote)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // Suggestion
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Recommendation", systemImage: "lightbulb.fill")
                            .font(.headline)
                            .foregroundColor(.orange)
                        
                        Text(recommendation.suggestion)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // System requirements reminder
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Remember:")
                            .font(.caption)
                            .fontWeight(.semibold)
                        
                        Text("• Close other applications to free up RAM")
                            .font(.caption)
                        Text("• Embedding happens locally on your device")
                            .font(.caption)
                        Text("• Larger datasets take exponentially more time")
                            .font(.caption)
                        Text("• You can pause and resume downloads if needed")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .padding()
                    .padding(.bottom)
                }
            }
            .navigationTitle("Dataset Requirements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Got it") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

private struct MetricRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text(value)
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
}

// MARK: - Preview

#Preview {
    DatasetRecommendationView(
        datasetName: "Sample Textbook",
        totalSizeBytes: 104_857_600 // 100 MB
    )
}