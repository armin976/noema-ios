import SwiftUI

struct DatasetImportNamePromptView: View {
    @Binding var datasetName: String
    let onCancel: () -> Void
    let onImport: () async -> Void

    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(LocalizedStringKey("Dataset name"), text: $datasetName)
                        .focused($isNameFocused)
#if os(iOS) || os(visionOS)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(true)
#endif
                } header: {
                    Text(LocalizedStringKey("Name your dataset"))
                }
            }
            .navigationTitle(LocalizedStringKey("Import Dataset"))
#if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LocalizedStringKey("Cancel")) { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(LocalizedStringKey("Import")) {
                        Task { await onImport() }
                    }
                    .disabled(datasetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                // Defer focus to avoid "attempt to present while already presenting" warnings on iOS.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isNameFocused = true
                }
            }
        }
    }
}
