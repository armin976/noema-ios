import SwiftUI

public struct InspectorView: View {
    private let datasetStore: DatasetIndexStore
    private let cacheIndex: CacheIndex
    private let pythonExecutor: InspectorPythonExecutionHandling?

    public init(datasetStore: DatasetIndexStore = DatasetIndexStore(),
                cacheIndex: CacheIndex = CacheIndex(),
                pythonExecutor: InspectorPythonExecutionHandling? = nil) {
        self.datasetStore = datasetStore
        self.cacheIndex = cacheIndex
        self.pythonExecutor = pythonExecutor
    }

    public var body: some View {
        TabView {
            DatasetsTab(store: datasetStore, pythonExecutor: pythonExecutor)
                .tabItem {
                    Label("Datasets", systemImage: "externaldrive")
                }
            FiguresTab(cacheIndex: cacheIndex)
                .tabItem {
                    Label("Figures", systemImage: "photo.on.rectangle.angled")
                }
        }
    }
}
