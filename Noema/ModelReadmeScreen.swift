// ModelReadmeScreen.swift
import SwiftUI
import Combine

/// Screen showing the README for a model.
struct ModelReadmeScreen: View {
    let repoID: String
    let token: String?
    var summaryUpdate: (String) -> Void = { _ in }
    @StateObject private var loader: ModelReadmeLoader

    init(repoID: String, token: String? = nil, summaryUpdate: @escaping (String) -> Void = { _ in }) {
        self.repoID = repoID
        self.token = token
        self.summaryUpdate = summaryUpdate
        _loader = StateObject(wrappedValue: ModelReadmeLoader(repo: repoID, token: token))
    }

    var body: some View {
        ScrollView {
            if let md = loader.markdown {
                ModelReadmeView(markdown: md)
            } else if loader.isLoading {
                ProgressView().padding()
            } else {
                VStack {
                    Text("Failed to load README")
                    Button("Retry") { loader.load(force: true) }
                }.padding()
            }
        }
        .navigationTitle(repoID)
        .onAppear { loader.load() }
        .onDisappear {
            loader.clearMarkdown()
            loader.cancel()
        }
        .onReceive(loader.$fallbackSummary.compactMap { $0 }) { summary in
            summaryUpdate(summary)
        }
    }
}
