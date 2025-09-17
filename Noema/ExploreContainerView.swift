// ExploreContainerView.swift
import SwiftUI

enum ExploreSection: String, CaseIterable {
    case models, datasets
}

enum ModelTypeFilter: String, CaseIterable {
    case all = "All"
    case text = "Text"
    case vision = "Vision"
    
    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .text: return "text.quote"
        case .vision: return "eye"
        }
    }
    
    var color: Color {
        switch self {
        case .all: return .blue
        case .text: return .green
        case .vision: return .purple
        }
    }
}

@MainActor
class ModelTypeFilterManager: ObservableObject {
    @Published var filter: ModelTypeFilter
    
    init(filter: ModelTypeFilter) {
        self.filter = filter
    }
    
    func shouldIncludeModel(_ record: ModelRecord) -> Bool {
        // Always hide models from specific creators
        let hiddenCreators = ["MaziyarPanahi"]
        if hiddenCreators.contains(where: { $0.caseInsensitiveCompare(record.publisher) == .orderedSame }) {
            return false
        }
        
        switch filter {
        case .all:
            return true
        case .text:
            // Exclude vision models
            return !isVisionModel(record)
        case .vision:
            // Only include vision models
            return isVisionModel(record)
        }
    }
    
    private func isVisionModel(_ record: ModelRecord) -> Bool {
        // Check pipeline_tag first
        if let pipelineTag = record.pipeline_tag?.lowercased(),
           pipelineTag == "image-text-to-text" {
            return true
        }
        
        // Check tags
        if let tags = record.tags?.map({ $0.lowercased() }),
           tags.contains("image-text-to-text") {
            return true
        }
        
        return false
    }
}

struct ExploreContainerView: View {
    @EnvironmentObject var tabRouter: TabRouter
    @AppStorage("exploreSection") private var exploreSectionRaw = ExploreSection.models.rawValue
    @AppStorage("modelTypeFilter") private var modelTypeFilterRaw = ModelTypeFilter.all.rawValue
    @StateObject private var filterManager = ModelTypeFilterManager(filter: .all)
    
    private var exploreSection: ExploreSection {
        get { ExploreSection(rawValue: exploreSectionRaw) ?? .models }
        set { exploreSectionRaw = newValue.rawValue }
    }
    
    private var modelTypeFilter: ModelTypeFilter {
        get { ModelTypeFilter(rawValue: modelTypeFilterRaw) ?? .all }
        set { modelTypeFilterRaw = newValue.rawValue }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                switch exploreSection {
                case .models:
                    ExploreView()
                        .environmentObject(filterManager)
                case .datasets:
                    DatasetsExploreView()
                }
                
                // Floating model type filter toggle (hidden while multimodal UI is disabled)
                if UIConstants.showMultimodalUI && exploreSection == .models {
                    VStack {
                        Spacer()
                        HStack {
                            ModelTypeFilterToggle(selection: modelTypeFilter) { newFilter in
                                withAnimation(.snappy) { 
                                    modelTypeFilterRaw = newFilter.rawValue
                                    filterManager.filter = newFilter
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, UIConstants.defaultPadding)
                        .padding(.bottom, 60) // Adjusted from 50 to 60 for better spacing
                    }
                }
            }
        }
        .navigationTitle("Explore")
        .safeAreaInset(edge: .bottom) {
            if tabRouter.selection == .explore {
                ExploreSwitchBar(selection: exploreSection) { newVal in
                    withAnimation(.snappy) { exploreSectionRaw = newVal.rawValue }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityElement(children: .contain)
            }
        }
        .onAppear {
            // Sync the filter manager with the stored value, or reset to All when multimodal UI is hidden
            if UIConstants.showMultimodalUI {
                filterManager.filter = modelTypeFilter
            } else {
                filterManager.filter = .all
                modelTypeFilterRaw = ModelTypeFilter.all.rawValue
            }
        }
        .onChange(of: modelTypeFilterRaw) { _, newValue in
            if let newFilter = ModelTypeFilter(rawValue: newValue) {
                filterManager.filter = newFilter
            }
        }
    }
}

struct ModelTypeFilterToggle: View {
    let selection: ModelTypeFilter
    var onChange: (ModelTypeFilter) -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(ModelTypeFilter.allCases, id: \.self) { filter in
                Button(action: { onChange(filter) }) {
                    HStack(spacing: 4) {
                        Image(systemName: filter.icon)
                            .font(.caption2)
                        Text(filter.rawValue)
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selection == filter ? filter.color : Color(.systemGray5))
                    )
                    .foregroundColor(selection == filter ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

struct ExploreSwitchBar: View {
    let selection: ExploreSection
    var onChange: (ExploreSection) -> Void

    var body: some View {
        let segmentRadius: CGFloat = UIConstants.cornerRadius
        let padding: CGFloat = 6

        HStack(spacing: 0) {
            Picker("", selection: Binding(get: { selection }, set: { onChange($0) })) {
                Text("Models").tag(ExploreSection.models)
                Text("Datasets").tag(ExploreSection.datasets)
            }
            .pickerStyle(.segmented)
        }
        .padding(padding)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: segmentRadius + padding, style: .continuous)
        )
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .padding(.horizontal, UIConstants.defaultPadding)
        .padding(.bottom, 8)
    }
}
