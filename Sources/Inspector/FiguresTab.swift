import SwiftUI
import UIKit

struct FiguresTab: View {
    let cacheIndex: CacheIndex
    @State private var figures: [FigureItem] = []
    @State private var selection: FigureItem?

    private let grid = [GridItem(.adaptive(minimum: 140), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: grid, spacing: 16) {
                    ForEach(figures) { figure in
                        Button {
                            selection = figure
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                thumbnail(for: figure)
                                Text(figure.name)
                                    .font(.footnote)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(figure.createdAt, style: .date)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
                        }
                    }
                }
                .padding()
                if figures.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No figures yet")
                            .font(.headline)
                        Text("Run python.execute with matplotlib to populate this grid.")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 80)
                }
            }
            .navigationTitle("Figures")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: refresh) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
            .task { await refreshAsync() }
            .sheet(item: $selection) { item in
                NavigationStack {
                    ImageDetailView(figure: item)
                }
            }
        }
    }

    private func thumbnail(for item: FigureItem) -> some View {
        Group {
            if let image = UIImage(contentsOfFile: item.url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 120)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
                .frame(height: 120)
            }
        }
    }

    private func refresh() {
        Task { await refreshAsync() }
    }

    private func refreshAsync() async {
        let items = await cacheIndex.listFigures()
        await MainActor.run {
            figures = items
        }
    }
}
