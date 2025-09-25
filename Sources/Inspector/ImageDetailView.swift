import SwiftUI
import UIKit

struct ImageDetailView: View {
    let figure: FigureItem
    @State private var showingShare = false

    var body: some View {
        VStack(spacing: 16) {
            if let image = UIImage(contentsOfFile: figure.url.path) {
                ScrollView([.vertical, .horizontal]) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding()
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "xmark.octagon")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Unable to load image")
                        .font(.headline)
                }
                .padding()
            }
            Spacer()
        }
        .navigationTitle(figure.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingShare = true
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                Button {
                    FileRevealer.shared.reveal(figure.url)
                } label: {
                    Label("Reveal in Files", systemImage: "folder")
                }
            }
        }
        .sheet(isPresented: $showingShare) {
            ActivityView(activityItems: [figure.url])
        }
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
