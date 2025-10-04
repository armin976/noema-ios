import SwiftUI

struct RemoteBackendFormView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (RemoteBackendDraft) async throws -> Void

    @State private var draft = RemoteBackendDraft()
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?
    @State private var chatPathEdited = false
    @State private var modelsPathEdited = false
    @State private var updatingDefaults = false
    @State private var lastEndpointType: RemoteBackend.EndpointType = .openAI

    private enum Field: Hashable {
        case name, baseURL, chatPath, modelsPath, auth
        case customModel(Int)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Field requirements will depend on your specific backend deployment.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                }
                Section("Backend") {
                    TextField("Name", text: $draft.name)
                        .focused($focusedField, equals: .name)
                        .textInputAutocapitalization(.words)
                    TextField("Base URL", text: $draft.baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .focused($focusedField, equals: .baseURL)
                    if let warning = loopbackWarningText {
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .labelStyle(.titleAndIcon)
                    }
                }

                Section("Endpoint Type") {
                    Picker("Endpoint", selection: $draft.endpointType) {
                        ForEach(RemoteBackend.EndpointType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Endpoints") {
                    TextField(draft.endpointType.defaultChatPath, text: $draft.chatPath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .focused($focusedField, equals: .chatPath)
                    TextField(draft.endpointType.defaultModelsPath, text: $draft.modelsPath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .focused($focusedField, equals: .modelsPath)
                }

                if draft.endpointType == .ollama {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label {
                                Text("When connecting from another device, point the base URL to your computer (for example http://192.168.0.10:11434) and start Ollama with `OLLAMA_HOST=0.0.0.0` so it accepts remote clients.")
                            } icon: {
                                Image(systemName: "info.circle")
                            }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .labelStyle(.titleAndIcon)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Authentication") {
                    TextField("Auth header (optional)", text: $draft.authHeader, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .focused($focusedField, equals: .auth)
                }

                Section("Model Identifiers") {
                    ForEach(Array(draft.customModelIDs.enumerated()), id: \.offset) { index, _ in
                        HStack(alignment: .top, spacing: 8) {
                            TextField("Model identifier", text: customModelBinding(at: index), axis: .vertical)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .focused($focusedField, equals: .customModel(index))
                            if draft.customModelIDs.count > 1 {
                                Button {
                                    removeCustomModelField(at: index)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Remove identifier")
                            }
                        }
                    }
                    Button {
                        addCustomModelField()
                    } label: {
                        Label("Add Identifier", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                    Text("Specify your model identifiers, or reload your custom models later.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Custom Backend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .task {
                draft.chatPath = draft.endpointType.defaultChatPath
                draft.modelsPath = draft.endpointType.defaultModelsPath
                chatPathEdited = false
                modelsPathEdited = false
                lastEndpointType = draft.endpointType
            }
            .onChange(of: draft.endpointType) { newValue in
                let previousType = lastEndpointType
                updatingDefaults = true
                let trimmedChat = draft.chatPath.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !chatPathEdited || trimmedChat == previousType.defaultChatPath.lowercased() {
                    draft.chatPath = newValue.defaultChatPath
                    chatPathEdited = false
                }
                let trimmedModels = draft.modelsPath.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !modelsPathEdited || trimmedModels == previousType.defaultModelsPath.lowercased() {
                    draft.modelsPath = newValue.defaultModelsPath
                    modelsPathEdited = false
                }
                updatingDefaults = false
                lastEndpointType = newValue
            }
            .onChange(of: draft.chatPath) { _ in
                if !updatingDefaults { chatPathEdited = true }
            }
            .onChange(of: draft.modelsPath) { _ in
                if !updatingDefaults { modelsPathEdited = true }
            }
            .alert("Unable to Save", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draft.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var loopbackWarningText: String? {
        guard draft.usesLoopbackHost else { return nil }
        var message = "Connections to localhost may not work from other devices. Replace it with your machine's LAN IP address to allow remote access."
        if draft.endpointType == .ollama {
            message += " Launch Ollama with `OLLAMA_HOST=0.0.0.0` so it can accept remote clients."
        }
        return message
    }

    private func save() async {
        guard !isSaving else { return }
        focusedField = nil
        isSaving = true
        do {
            try await onSave(draft)
            dismiss()
        } catch {
            if let backendError = error as? RemoteBackendError {
                errorMessage = backendError.errorDescription ?? "Unknown error"
            } else {
                errorMessage = error.localizedDescription
            }
        }
        isSaving = false
    }

    private func customModelBinding(at index: Int) -> Binding<String> {
        Binding<String> {
            guard draft.customModelIDs.indices.contains(index) else { return "" }
            return draft.customModelIDs[index]
        } set: { newValue in
            while draft.customModelIDs.count <= index {
                draft.customModelIDs.append("")
            }
            if draft.customModelIDs[index] != newValue {
                draft.customModelIDs[index] = newValue
            }
        }
    }

    private func addCustomModelField() {
        draft.appendCustomModelSlot()
        focusedField = .customModel(max(0, draft.customModelIDs.count - 1))
    }

    private func removeCustomModelField(at index: Int) {
        draft.removeCustomModel(at: index)
        let newCount = draft.customModelIDs.count
        if let currentFocus = focusedField, case .customModel(let focusedIndex) = currentFocus {
            if focusedIndex == index {
                focusedField = .customModel(min(index, max(0, newCount - 1)))
            } else if focusedIndex > index {
                focusedField = .customModel(focusedIndex - 1)
            }
        }
    }
}
