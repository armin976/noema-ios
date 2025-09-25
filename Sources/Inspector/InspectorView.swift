import SwiftUI

public struct InspectorView: View {
    private let datasetStore: DatasetIndexStore
    private let cacheIndex: CacheIndex

    public init(datasetStore: DatasetIndexStore = DatasetIndexStore(),
                cacheIndex: CacheIndex = CacheIndex()) {
        self.datasetStore = datasetStore
        self.cacheIndex = cacheIndex
    }

    public var body: some View {
        TabView {
            DatasetsTab(store: datasetStore)
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
