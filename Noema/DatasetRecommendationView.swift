// DatasetRecommendationView.swift
import SwiftUI

struct DatasetRecommendationView: View {
    let datasetName: String
    let totalSizeBytes: Int64
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    
    private var recommendation: DatasetRecommendationSystem.Recommendation {
        DatasetRecommendationSystem.recommendation(for: totalSizeBytes, locale: locale)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Header with icon and category
                    VStack(spacing: 16) {
                        Image(systemName: recommendation.sizeCategory.iconName)
                            .font(.system(size: 72))
                            .foregroundStyle(Color(recommendation.sizeCategory.iconColor).gradient)
                            .shadow(color: Color(recommendation.sizeCategory.iconColor).opacity(0.3), radius: 10, x: 0, y: 5)
                        
                        VStack(spacing: 8) {
                            Text(recommendation.sizeCategory.title(locale: locale))
                                .font(.system(.largeTitle, design: .serif))
                                .fontWeight(.bold)
                                .multilineTextAlignment(.center)
                            
                            Text(recommendation.sizeCategory.description(locale: locale))
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.top, 20)
                    .padding(.horizontal)
                    
                    // Performance metrics
                    HStack(spacing: 16) {
                        MetricCard(
                            icon: "clock.fill",
                            title: LocalizedStringKey("Est. Time"),
                            value: DatasetRecommendationSystem.formatTime(recommendation.estimatedEmbeddingTime, locale: locale),
                            color: .blue
                        )
                        
                        MetricCard(
                            icon: "memorychip.fill",
                            title: LocalizedStringKey("Peak RAM"),
                            value: DatasetRecommendationSystem.formatRAM(recommendation.estimatedRAMUsage, locale: locale),
                            color: .purple
                        )
                        
                        MetricCard(
                            icon: "doc.fill",
                            title: LocalizedStringKey("Size"),
                            value: {
                                let formatter = ByteCountFormatter()
                                formatter.countStyle = .file
                                return formatter.string(fromByteCount: totalSizeBytes)
                            }(),
                            color: .gray
                        )
                    }
                    .padding(.horizontal)
                    
                    // Suggestion & Note
                    VStack(spacing: 16) {
                        InfoCard(
                            icon: "lightbulb.fill",
                            title: LocalizedStringKey("Recommendation"),
                            content: recommendation.suggestion,
                            color: .orange
                        )
                        
                        InfoCard(
                            icon: "info.circle.fill",
                            title: LocalizedStringKey("Performance Note"),
                            content: recommendation.performanceNote,
                            color: .blue
                        )
                    }
                    .padding(.horizontal)
                    
                    // System requirements reminder
                    VStack(alignment: .leading, spacing: 12) {
                        Text(LocalizedStringKey("Things to keep in mind"))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            RequirementRow(text: LocalizedStringKey("Close other applications to free up RAM"))
                            RequirementRow(text: LocalizedStringKey("Embedding happens locally on your device"))
                            RequirementRow(text: LocalizedStringKey("Larger datasets take exponentially more time"))
                            RequirementRow(text: LocalizedStringKey("You can pause and resume downloads if needed"))
                        }
                    }
                    .padding(20)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(16)
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .navigationTitle(LocalizedStringKey("Dataset Requirements"))
#if os(iOS) || os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            #if !os(macOS)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(LocalizedStringKey("Got it")) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            #endif
            #if os(macOS)
            .overlay(alignment: .bottom) {
                VStack(spacing: 0) {
                    Divider()
                    HStack {
                        Spacer()
                        Button(LocalizedStringKey("Got it")) { dismiss() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(.ultraThinMaterial)
                }
            }
            #endif
        }
    }
}

private struct MetricCard: View {
    let icon: String
    let title: LocalizedStringKey
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color.gradient)
                .frame(height: 24)
            
            VStack(spacing: 4) {
                Text(value)
                    .font(.headline)
                    .fontWeight(.bold)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(16)
    }
}

private struct InfoCard: View {
    let icon: String
    let title: LocalizedStringKey
    let content: String
    let color: Color
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .padding(10)
                .background(color.opacity(0.1))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                
                Text(content)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
            
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(16)
    }
}

private struct RequirementRow: View {
    let text: LocalizedStringKey
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(.secondary)
                .padding(.top, 7)
            
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    DatasetRecommendationView(
        datasetName: "Sample Textbook",
        totalSizeBytes: 104_857_600 // 100 MB
    )
    .frame(width: 500, height: 700)
}
