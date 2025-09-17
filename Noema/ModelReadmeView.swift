// ModelReadmeView.swift
import SwiftUI

/// Displays README markdown content.
struct ModelReadmeView: View {
    let markdown: String
    var body: some View {
        ScrollView {
            if let attr = try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .full)) {
                Text(attr)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            } else {
                Text(markdown)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
    }
}
