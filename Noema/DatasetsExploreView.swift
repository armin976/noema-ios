// DatasetsExploreView.swift
import SwiftUI
import Foundation
import UniformTypeIdentifiers
import PDFKit

struct DatasetsExploreView: View {
    @EnvironmentObject var tabRouter: TabRouter
    @EnvironmentObject var downloadController: DownloadController
    @EnvironmentObject var datasetManager: DatasetManager
    @EnvironmentObject var walkthrough: GuidedWalkthroughManager
    @StateObject private var vm: DatasetsExploreViewModel
    @State private var selected: DatasetDetails?
    @State private var loadingDetail = false
    @State private var showSlowHint = false
    @State private var detailTask: Task<Void, Never>? = nil
    @State private var hintTask: Task<Void, Never>? = nil
    @AppStorage("huggingFaceToken") private var huggingFaceToken = ""

    // Import flow state
    @State private var showImporter = false
    @State private var pendingPickedURLs: [URL] = []
    @State private var showNameSheet = false
    @State private var datasetName: String = ""
    @State private var importedDataset: LocalDataset?
    @State private var askStartIndexing = false
    @State private var datasetToIndex: LocalDataset?

    init() {
        let token = UserDefaults.standard.string(forKey: "huggingFaceToken") ?? ""
        let hf = CombinedDatasetRegistry(
            primary: HuggingFaceDatasetRegistry(token: token),
            extras: [ManualDatasetRegistry(entries: CuratedDatasets.hf)]
        )
        let otl = OpenTextbookLibraryDatasetRegistry()
        _vm = StateObject(wrappedValue: DatasetsExploreViewModel(hfRegistry: hf, otlRegistry: otl))
    }

    var body: some View { contentView }

    @ViewBuilder
    private var contentView: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 20)], spacing: 20) {
                        if vm.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                            Text("Search for any subject you're interested in.")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                        } else {
                            Section {
                                ForEach(vm.searchResults, content: recordCard)
                                if vm.canLoadMore {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                        .onAppear { vm.loadNextPage() }
                                }
                            } header: {
                                Text("Results")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal)
                            }
                        }
                    }
                    .padding()
                }
                .searchable(text: $vm.searchText)
                .guideHighlight(.exploreDatasetList)
                .onSubmit(of: .search) { vm.triggerSearch() }
                .onChange(of: huggingFaceToken, perform: updateRegistry)
            } else {
                List {
                    if vm.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("Search for any subject you're interested in.")
                            .foregroundStyle(.secondary)
                    } else {
                        Section("Results") {
                            ForEach(vm.searchResults, content: recordRow)
                            if vm.canLoadMore {
                                ProgressView().onAppear { vm.loadNextPage() }
                            }
                        }
                    }
                }
                .searchable(text: $vm.searchText)
                .onSubmit(of: .search) { vm.triggerSearch() }
                // Title provided by parent container
                .onChange(of: huggingFaceToken, perform: updateRegistry)
                .guideHighlight(.exploreDatasetList)
            }
        }
        .sheet(item: $selected, content: detailSheet)
        .sheet(item: $importedDataset) { ds in
            LocalDatasetDetailView(dataset: ds)
                .environmentObject(datasetManager)
        }
        .overlay(alignment: .center) { loadingOverlay }
        .overlay(alignment: .center) { Group { if vm.isLoadingSearch { ProgressView() } } }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: allowedUTTypes(),
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                // Filter out non-allowed just in case
                let filtered = urls.filter { allowedExtensions().contains($0.pathExtension.lowercased()) }
                guard !filtered.isEmpty else { return }
                pendingPickedURLs = filtered
                datasetName = suggestName(from: filtered) ?? "Imported Dataset"
                showNameSheet = true
            case .failure:
                break
            }
        }
        .sheet(isPresented: $showNameSheet) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Name your dataset")
                        .font(.headline)
                    TextField("Dataset name", text: $datasetName)
                        .textFieldStyle(.roundedBorder)
                    Spacer()
                    HStack {
                        Button("Cancel") { showNameSheet = false }
                        Spacer()
                        Button("Import") { Task { await performImport() } }
                            .buttonStyle(.borderedProminent)
                            .disabled(datasetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding()
                .navigationTitle("Import Dataset")
            }
            .presentationDetents([.fraction(0.35)])
        }
        .confirmationDialog("Start indexing now?", isPresented: $askStartIndexing, titleVisibility: .visible) {
            Button("Start") {
                if let ds = datasetToIndex {
                    datasetManager.startIndexing(dataset: ds)
                }
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text("We'll extract text and prepare embeddings. You can also start later from the dataset details.")
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showImporter = true
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .guideHighlight(.exploreImportButton)
            }
        }
    }

    @ViewBuilder
    private func recordRow(_ record: DatasetRecord) -> some View {
        Button { startOpen(record) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.displayName)
                if !record.publisher.isEmpty {
                    Text(record.publisher)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let summary = record.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    @ViewBuilder
    private func recordCard(_ record: DatasetRecord) -> some View {
        Button { startOpen(record) } label: {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Image(systemName: "doc.text.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                    Spacer()
                    if record.installed {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
                
                // Title and publisher
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    
                    if !record.publisher.isEmpty {
                        Text(record.publisher)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Summary
                if let summary = record.summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer(minLength: 0)
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: 150)
            .background(Color(.secondarySystemGroupedBackground))
            .adaptiveCornerRadius(.medium)
            .overlay(
                RoundedRectangle(cornerRadius: UIConstants.cornerRadius)
                    .stroke(Color(.separator), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func detailSheet(_ detail: DatasetDetails) -> some View {
        DatasetDetailView(detail: detail)
            .environmentObject(downloadController)
    }

    @MainActor
    private func open(_ record: DatasetRecord) async {
        loadingDetail = true
        if let d = await vm.details(for: record.id) {
            if Task.isCancelled { loadingDetail = false; return }
            selected = d
        }
        loadingDetail = false
        showSlowHint = false
        hintTask?.cancel(); hintTask = nil
    }

    private func startOpen(_ record: DatasetRecord) {
        detailTask?.cancel()
        hintTask?.cancel()
        showSlowHint = false
        loadingDetail = true
        // Schedule slow-hint after delay if still loading
        hintTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.0))
            if !Task.isCancelled && loadingDetail {
                withAnimation(.snappy) { showSlowHint = true }
            }
        }
        detailTask = Task { [record, self] in
            await self.open(record)
        }
    }

    private func cancelLoading() {
        detailTask?.cancel(); detailTask = nil
        hintTask?.cancel(); hintTask = nil
        withAnimation(.snappy) {
            showSlowHint = false
            loadingDetail = false
        }
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        if loadingDetail {
            ZStack {
                Color.black.opacity(0.05).ignoresSafeArea()
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(1.1)
                    if showSlowHint {
                        HStack(spacing: 8) {
                            Text("This dataset is taking a while to load, still working…")
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Button("Cancel") { cancelLoading() }
                                .buttonStyle(.bordered)
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .glassifyIfAvailable(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                )
                .shadow(radius: 8)
                .padding()
                .transition(.scale.combined(with: .opacity))
            }
            .animation(.snappy, value: showSlowHint)
        }
    }
    
    private func updateRegistry(_ token: String) {
        let hf = CombinedDatasetRegistry(primary: HuggingFaceDatasetRegistry(token: token),
                                         extras: [ManualDatasetRegistry(entries: CuratedDatasets.hf)])
        vm.updateHFRegistry(hf)
        Task { await vm.loadCurated() }
    }

    // MARK: - Import helpers
    private func allowedExtensions() -> Set<String> { ["pdf", "epub", "txt"] }
    private func allowedUTTypes() -> [UTType] {
        var types: [UTType] = [.pdf, .plainText]
        if let epub = UTType(filenameExtension: "epub") { types.append(epub) }
        return types
    }
    private func suggestName(from urls: [URL]) -> String? {
        // Prefer first PDF title metadata
        if let pdfURL = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) {
            if let doc = PDFDocument(url: pdfURL), let title = doc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return title
            }
        }
        // Fallback to first epub/txt filename
        if let u = urls.first {
            return u.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "[_-]+", with: " ", options: .regularExpression)
        }
        return nil
    }
    private func performImport() async {
        let name = datasetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pendingPickedURLs.isEmpty, !name.isEmpty else { return }
        if let ds = await datasetManager.importDocuments(from: pendingPickedURLs, suggestedName: name) {
            importedDataset = ds
            datasetToIndex = ds
            askStartIndexing = true
        }
        // Reset state
        pendingPickedURLs.removeAll()
        showNameSheet = false
    }
}

extension View {
    @ViewBuilder
    func glassifyIfAvailable<S: Shape>(in shape: S) -> some View {
        #if os(visionOS)
        self.background(.regularMaterial, in: shape)
        #else
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self
        }
        #endif
    }
}
