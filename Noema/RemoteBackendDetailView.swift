import SwiftUI
import Foundation
import Combine

struct RemoteBackendDetailView: View {
    let backendID: RemoteBackend.ID

    @EnvironmentObject var modelManager: AppModelManager
    @EnvironmentObject var vm: ChatVM
    @EnvironmentObject var tabRouter: TabRouter
    @Environment(\.dismiss) private var dismiss
    @AppStorage("offGrid") private var offGrid = false

    @State private var actionMessage: RemoteBackendActionMessage?
    @State private var isEditing = false
    @State private var editedDraft: RemoteBackendDraft?
    @State private var hasDraftChanges = false
    @State private var isPersistingDraft = false
    @State private var activatingModelID: String?
    @State private var activationTask: Task<Void, Never>?
    @State private var activationToken: UUID?
    @State private var refreshTask: Task<Void, Never>?
    @State private var refreshToken: UUID?
    @State private var isShowingConnectionSummary = false
    @State private var isAuthExpanded = false
    @State private var authExpansionBackendID: RemoteBackend.ID?
    @FocusState private var focusedField: EditableField?

    private enum EditableField: Hashable {
        case name, baseURL, chatPath, modelsPath, auth
        case customModel(Int)
    }

    private var backend: RemoteBackend? {
        modelManager.remoteBackend(withID: backendID)
    }

    private var activeRemoteModelID: String? {
        guard let session = modelManager.activeRemoteSession,
              session.backendID == backendID else { return nil }
        return session.modelID
    }

    var body: some View {
        Group {
            if let backend {
                List {
                    connectionSection(for: backend)
                    modelsSection(for: backend)
                    serverTypeSection(for: backend)
                    authenticationSection(for: backend)
                    modelIdentifiersSection(for: backend)
                }
                .navigationTitle(backend.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent(for: backend) }
                .refreshable { await refreshModelsIfPossible() }
                .onAppear { syncAuthExpansion(with: backend) }
                .onChange(of: backend.id) { _ in syncAuthExpansion(with: backend) }
                .onChange(of: backend.authHeader ?? "") { newValue in
                    if !newValue.isEmpty {
                        isAuthExpanded = true
                    }
                }
                .onChange(of: isEditing) { editing in
                    if editing {
                        isAuthExpanded = true
                    }
                }
            } else {
                ContentUnavailableView("Backend not found", systemImage: "exclamationmark.triangle")
            }
        }
        .alert(item: $actionMessage) { message in
            Alert(
                title: Text(message.isError ? "Error" : "Success"),
                message: Text(message.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func connectionSection(for backend: RemoteBackend) -> some View {
        Section("Connection") {
            connectionStatusRow(for: backend)
            editableRow(
                title: "Name",
                systemImage: "textformat",
                value: backend.name,
                field: .name,
                backend: backend
            ) { binding in
                TextField("Backend Name", text: binding)
                    .textInputAutocapitalization(.words)
                    .focused($focusedField, equals: .name)
            }
            editableRow(
                title: "Base URL",
                systemImage: "link",
                value: backend.baseURLString,
                field: .baseURL,
                backend: backend
            ) { binding in
                TextField("https://example.com", text: binding)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .focused($focusedField, equals: .baseURL)
            }
            editableRow(
                title: "Chat Path",
                systemImage: "bubble.left.and.text.bubble.right",
                value: backend.chatPath,
                field: .chatPath,
                backend: backend
            ) { binding in
                TextField((editedDraft?.endpointType ?? backend.endpointType).defaultChatPath, text: binding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .focused($focusedField, equals: .chatPath)
            }
            editableRow(
                title: "Models Path",
                systemImage: "tray.and.arrow.down",
                value: backend.modelsPath,
                field: .modelsPath,
                backend: backend
            ) { binding in
                TextField((editedDraft?.endpointType ?? backend.endpointType).defaultModelsPath, text: binding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .focused($focusedField, equals: .modelsPath)
            }
            if backend.usesLoopbackHost {
                Label(loopbackWarningText(for: backend), systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            if offGrid {
                Label("Off-Grid mode blocks remote connections.", systemImage: "wifi.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func serverTypeSection(for backend: RemoteBackend) -> some View {
        Section("Endpoint Type") {
            if isEditing, let binding = draftBinding(for: \RemoteBackendDraft.endpointType, backend: backend) {
                Picker("Endpoint", selection: binding) {
                    ForEach(RemoteBackend.EndpointType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)
            } else {
                LabeledContent("Type") {
                    Text(backend.endpointType.displayName)
                        .font(.callout)
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    @ViewBuilder
    private func authenticationSection(for backend: RemoteBackend) -> some View {
        Section {
            DisclosureGroup(isExpanded: $isAuthExpanded) {
                VStack(alignment: .leading, spacing: 6) {
                    if isEditing, let binding = draftBinding(for: \RemoteBackendDraft.authHeader, backend: backend) {
                        editingFieldContainer {
                            TextField("Bearer ...", text: binding, axis: .vertical)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .focused($focusedField, equals: .auth)
                        }
                    } else {
                        let value = backend.authHeader?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        if value.isEmpty {
                            Text("Not provided")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .italic()
                        } else {
                            Text(value)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.top, 6)
            } label: {
                Label("Authentication", systemImage: "key")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func modelIdentifiersSection(for backend: RemoteBackend) -> some View {
        Section("Model Identifiers") {
            if isEditing {
                let draft = editedDraft ?? backendDraftSnapshot(from: backend)
                ForEach(Array(draft.customModelIDs.enumerated()), id: \.offset) { index, _ in
                    HStack(alignment: .top, spacing: 8) {
                        editingFieldContainer {
                            TextField("Model identifier", text: customModelBinding(for: index, backend: backend), axis: .vertical)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .focused($focusedField, equals: .customModel(index))
                        }
                        if draft.customModelIDs.count > 1 {
                            Button {
                                removeCustomModel(at: index, backend: backend)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove identifier")
                        }
                    }
                }
                Button {
                    addCustomModel(for: backend)
                } label: {
                    Label("Add Identifier", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
                .padding(.top, 4)
            } else {
                if backend.customModelIDs.isEmpty {
                    Text("Using server catalog")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    ForEach(backend.customModelIDs, id: \.self) { identifier in
                        Text(identifier)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    }
                }
            }
            Text("Specify identifiers for models that are not listed by the server. Leave blank to rely on the server's catalog.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func modelsSection(for backend: RemoteBackend) -> some View {
        Section("Models") {
            let models = backend.cachedModels.filter { !$0.isEmbedding }
            if models.isEmpty {
                VStack(spacing: 8) {
                    Text(offGrid ? "Remote access is disabled." : "No compatible models available")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if !offGrid {
                        Button {
                            triggerManualRefresh()
                        } label: {
                            Label("Reload Models", systemImage: "arrow.clockwise")
                        }
                        .disabled(refreshTask != nil)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                ForEach(models, id: \.id) { model in
                    RemoteModelRow(
                        model: model,
                        endpointType: backend.endpointType,
                        availability: modelAvailability(for: backend),
                        isActivating: activatingModelID == model.id,
                        isActive: activeRemoteModelID == model.id,
                        useAction: { use(model: model, in: backend) }
                    )
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func toolbarContent(for backend: RemoteBackend) -> some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            if isEditing {
                Button {
                    Task { await finishEditing(for: backend) }
                } label: {
                    if isPersistingDraft {
                        ProgressView()
                    } else {
                        Text("Done")
                    }
                }
                .disabled(isPersistingDraft)
            } else {
                if let task = activationTask, !task.isCancelled {
                    Button {
                        cancelActivation()
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .accessibilityLabel("Cancel remote load")
                }
                if let task = refreshTask, !task.isCancelled {
                    Button {
                        cancelRefresh()
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .accessibilityLabel("Cancel reload")
                    ProgressView()
                } else if modelManager.remoteBackendsFetching.contains(backendID) {
                    ProgressView()
                } else if !offGrid {
                    Button { triggerManualRefresh() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Reload models")
                    .disabled(refreshTask != nil)
                }

                Menu {
                    Button {
                        startEditing(with: backend)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        deleteBackend()
                    } label: {
                        Label("Delete Backend", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    // MARK: - Helpers

    private func connectionStatusRow(for backend: RemoteBackend) -> some View {
        let status = connectionStatus(for: backend)
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isShowingConnectionSummary.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Label("Connection Status", systemImage: status.symbol)
                        .font(.callout)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(status.text)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(status.color.opacity(0.15), in: Capsule())
                        .foregroundColor(status.color)
                    Image(systemName: isShowingConnectionSummary ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 2)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Connection Status: \(status.text)"))
            .accessibilityHint(Text("Shows the last server response."))

            if isShowingConnectionSummary {
                connectionSummaryDetails(for: backend, statusColor: status.color)
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onChange(of: backend.lastConnectionSummary) { summary in
            if summary == nil {
                isShowingConnectionSummary = false
            }
        }
    }

    @ViewBuilder
    private func connectionSummaryDetails(for backend: RemoteBackend, statusColor: Color) -> some View {
        if let summary = backend.lastConnectionSummary {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: connectionSummaryIcon(for: summary))
                        .font(.caption)
                        .foregroundColor(statusColor)
                    Text(summary.displayLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let extra = additionalSummaryMessage(for: summary) {
                    Text(extra)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ConnectionSummaryTimestampView(timestamp: summary.timestamp)
            }
            .padding(.leading, 4)
        } else {
            Text("No connection responses recorded yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
        }
    }

    private func connectionSummaryIcon(for summary: RemoteBackend.ConnectionSummary) -> String {
        switch summary.kind {
        case .success:
            return "checkmark.seal"
        case .failure:
            return summary.statusCode == nil ? "wifi.slash" : "exclamationmark.triangle"
        }
    }

    private func additionalSummaryMessage(for summary: RemoteBackend.ConnectionSummary) -> String? {
        guard let message = summary.message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty else {
            return nil
        }
        return message == summary.displayLine ? nil : message
    }

    private func editableRow<Content: View>(
        title: String,
        systemImage: String,
        value: String,
        field: EditableField,
        backend: RemoteBackend,
        emptyPlaceholder: String? = nil,
        content: (Binding<String>) -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            if isEditing, let binding = draftBinding(for: keyPath(for: field), backend: backend) {
                editingFieldContainer {
                    content(binding)
                }
            } else {
                if value.isEmpty {
                    Text(emptyPlaceholder ?? "None")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    Text(value)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func editingFieldContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .font(.callout)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.secondary.opacity(0.25))
            )
    }

    private func draftBinding(for keyPath: WritableKeyPath<RemoteBackendDraft, String>, backend: RemoteBackend) -> Binding<String>? {
        Binding<String> {
            (editedDraft ?? backendDraftSnapshot(from: backend))[keyPath: keyPath]
        } set: { newValue in
            if editedDraft == nil { editedDraft = RemoteBackendDraft(from: backend) }
            guard editedDraft?[keyPath: keyPath] != newValue else { return }
            editedDraft?[keyPath: keyPath] = newValue
            hasDraftChanges = true
        }
    }

    private func draftBinding(for keyPath: WritableKeyPath<RemoteBackendDraft, RemoteBackend.EndpointType>, backend: RemoteBackend) -> Binding<RemoteBackend.EndpointType>? {
        Binding<RemoteBackend.EndpointType> {
            (editedDraft ?? RemoteBackendDraft(from: backend))[keyPath: keyPath]
        } set: { newValue in
            var snapshot = editedDraft ?? RemoteBackendDraft(from: backend)
            let previousType = snapshot[keyPath: keyPath]
            guard previousType != newValue else { return }
            if editedDraft == nil {
                editedDraft = snapshot
            }
            // If the user hasn't customized the paths, swap them to the new defaults
            if snapshot.chatPath.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == previousType.defaultChatPath.lowercased() {
                editedDraft?.chatPath = newValue.defaultChatPath
            }
            if snapshot.modelsPath.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == previousType.defaultModelsPath.lowercased() {
                editedDraft?.modelsPath = newValue.defaultModelsPath
            }
            editedDraft?[keyPath: keyPath] = newValue
            hasDraftChanges = true
        }
    }

    private func customModelBinding(for index: Int, backend: RemoteBackend) -> Binding<String> {
        Binding<String> {
            let snapshot = editedDraft ?? RemoteBackendDraft(from: backend)
            guard snapshot.customModelIDs.indices.contains(index) else { return "" }
            return snapshot.customModelIDs[index]
        } set: { newValue in
            var snapshot = editedDraft ?? RemoteBackendDraft(from: backend)
            while snapshot.customModelIDs.count <= index {
                snapshot.customModelIDs.append("")
            }
            if snapshot.customModelIDs[index] != newValue {
                snapshot.customModelIDs[index] = newValue
                editedDraft = snapshot
                hasDraftChanges = true
            }
        }
    }

    private func addCustomModel(for backend: RemoteBackend) {
        var snapshot = editedDraft ?? RemoteBackendDraft(from: backend)
        snapshot.appendCustomModelSlot()
        editedDraft = snapshot
        hasDraftChanges = true
        focusedField = .customModel(max(0, snapshot.customModelIDs.count - 1))
    }

    private func removeCustomModel(at index: Int, backend: RemoteBackend) {
        var snapshot = editedDraft ?? RemoteBackendDraft(from: backend)
        snapshot.removeCustomModel(at: index)
        editedDraft = snapshot
        hasDraftChanges = true
        if let current = focusedField, case .customModel(let focusedIndex) = current {
            if focusedIndex == index {
                focusedField = .customModel(min(index, max(0, snapshot.customModelIDs.count - 1)))
            } else if focusedIndex > index {
                focusedField = .customModel(focusedIndex - 1)
            }
        }
    }

    private func keyPath(for field: EditableField) -> WritableKeyPath<RemoteBackendDraft, String> {
        switch field {
        case .name: return \RemoteBackendDraft.name
        case .baseURL: return \RemoteBackendDraft.baseURL
        case .chatPath: return \RemoteBackendDraft.chatPath
        case .modelsPath: return \RemoteBackendDraft.modelsPath
        case .auth: return \RemoteBackendDraft.authHeader
        case .customModel:
            fatalError("Custom model fields use a dedicated binding")
        }
    }

    private func backendDraftSnapshot(from backend: RemoteBackend) -> RemoteBackendDraft {
        RemoteBackendDraft(from: backend)
    }

    private func connectionStatus(for backend: RemoteBackend) -> (text: String, color: Color, symbol: String) {
        if offGrid {
            return ("Connection blocked", .orange, "wifi.slash")
        }
        if modelManager.remoteBackendsFetching.contains(backendID) {
            return ("Trying to connect", .yellow, "clock.arrow.2.circlepath")
        }
        if let error = backend.lastError, !error.isEmpty {
            return ("Disconnected", .red, "exclamationmark.octagon")
        }
        if backend.lastFetched != nil {
            return ("Connected", .green, "checkmark.circle")
        }
        return ("Never connected", .secondary, "questionmark.circle")
    }

    private func startEditing(with backend: RemoteBackend) {
        editedDraft = RemoteBackendDraft(from: backend)
        hasDraftChanges = false
        isEditing = true
    }

    private func deleteBackend() {
        modelManager.deleteRemoteBackend(id: backendID)
        dismiss()
    }

    private func use(model: RemoteModel, in backend: RemoteBackend) {
        let availability = modelAvailability(for: backend)
        switch availability {
        case .offGrid:
            actionMessage = RemoteBackendActionMessage(message: "Remote access is disabled in Off-Grid mode.", isError: true)
            return
        case .unreachable(let message):
            actionMessage = RemoteBackendActionMessage(message: message, isError: true)
            return
        case .available:
            break
        }
        activationTask?.cancel()
        let token = UUID()
        activationToken = token
        activatingModelID = model.id
        let task = Task {
            defer {
                Task { @MainActor in
                    if activationToken == token {
                        activationTask = nil
                        activationToken = nil
                        if activatingModelID == model.id {
                            activatingModelID = nil
                        }
                    }
                }
            }
            do {
                try await vm.activateRemoteSession(backend: backend, model: model)
                await MainActor.run {
                    tabRouter.selection = .chat
                }
                let trimmedPrompt = await MainActor.run { vm.prompt.trimmingCharacters(in: .whitespacesAndNewlines) }
                if !trimmedPrompt.isEmpty {
                    await vm.send()
                }
            } catch is CancellationError {
                await vm.deactivateRemoteSession()
            } catch {
                let message: String
                if let backendError = error as? RemoteBackendError {
                    message = backendError.errorDescription ?? "Unknown error"
                } else {
                    message = error.localizedDescription
                }
                actionMessage = RemoteBackendActionMessage(message: message, isError: true)
            }
        }
        activationTask = task
    }

    private func modelAvailability(for backend: RemoteBackend) -> RemoteModelRow.Availability {
        if offGrid {
            return .offGrid
        }
        if let summary = backend.lastConnectionSummary, summary.kind == .failure {
            return .unreachable(message: connectionFailureExplanation(for: backend))
        }
        if let error = backend.lastError?.trimmingCharacters(in: .whitespacesAndNewlines), !error.isEmpty {
            return .unreachable(message: error)
        }
        return .available
    }

    private func connectionFailureExplanation(for backend: RemoteBackend) -> String {
        guard let summary = backend.lastConnectionSummary else {
            if let error = backend.lastError?.trimmingCharacters(in: .whitespacesAndNewlines), !error.isEmpty {
                return error
            }
            return "Unable to reach the remote server."
        }
        let base = summary.displayLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let extra = additionalSummaryMessage(for: summary)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let details = [base, extra].compactMap { value -> String? in
            guard let value = value, !value.isEmpty else { return nil }
            return value
        }
        if !details.isEmpty {
            return details.joined(separator: "\n")
        }
        if let error = backend.lastError?.trimmingCharacters(in: .whitespacesAndNewlines), !error.isEmpty {
            return error
        }
        return "Unable to reach the remote server."
    }

    private func cancelActivation() {
        activationTask?.cancel()
        activationTask = nil
        activationToken = nil
        activatingModelID = nil
        Task { await vm.deactivateRemoteSession() }
    }

    private func triggerManualRefresh() {
        Task { await refreshModelsIfPossible(forceRestart: true) }
    }

    @MainActor
    private func cancelRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        refreshToken = nil
    }

    @MainActor
    private func refreshModelsIfPossible(forceRestart: Bool = false) async {
        guard !offGrid else { return }
        if !forceRestart, let existing = refreshTask {
            await existing.value
            return
        }
        refreshTask?.cancel()
        let token = UUID()
        refreshToken = token
        let task = Task { @MainActor in
            await modelManager.fetchRemoteModels(for: backendID)
        }
        refreshTask = task
        await task.value
        if refreshToken == token {
            refreshTask = nil
            refreshToken = nil
        }
    }

    @MainActor
    private func finishEditing(for backend: RemoteBackend) async {
        focusedField = nil
        guard hasDraftChanges, let draft = editedDraft else {
            isEditing = false
            editedDraft = nil
            return
        }
        isPersistingDraft = true
        defer { isPersistingDraft = false }
        do {
            try modelManager.updateRemoteBackend(id: backendID, using: draft)
            isEditing = false
            editedDraft = nil
            hasDraftChanges = false
            if let session = modelManager.activeRemoteSession,
               session.backendID == backendID {
                try await vm.refreshActiveRemoteBackendIfNeeded(updatedBackendID: backendID, activeModelID: session.modelID)
            }
            if !offGrid {
                await refreshModelsIfPossible(forceRestart: true)
            }
        } catch {
            let message: String
            if let backendError = error as? RemoteBackendError {
                message = backendError.errorDescription ?? "Unknown error"
            } else {
                message = error.localizedDescription
            }
            actionMessage = RemoteBackendActionMessage(message: message, isError: true)
        }
    }

    private func syncAuthExpansion(with backend: RemoteBackend) {
        if authExpansionBackendID != backend.id {
            isAuthExpanded = backend.hasAuth
            authExpansionBackendID = backend.id
        }
    }
}

extension RemoteBackendDetailView {
    private func loopbackWarningText(for backend: RemoteBackend) -> String {
        var message = "Connections to localhost may not work from other devices. Replace it with your machine's LAN IP address to allow remote access."
        if backend.endpointType == .ollama {
            message += " Launch Ollama with `OLLAMA_HOST=0.0.0.0` so it can accept remote clients."
        }
        return message
    }
}

private struct RemoteBackendActionMessage: Identifiable {
    let id = UUID()
    let message: String
    let isError: Bool
}

private struct ConnectionSummaryTimestampView: View {
    let timestamp: Date

    @State private var now: Date = Date()
    @State private var timerCancellable: AnyCancellable?
    @State private var currentInterval: TimeInterval = 1

    var body: some View {
        Text(relativeText)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .monospacedDigit()
            .onAppear {
                now = Date()
                startTimer()
            }
            .onDisappear { stopTimer() }
            .onChange(of: timestamp) { _ in
                now = Date()
                startTimer()
            }
    }

    private var relativeText: String {
        let elapsed = max(0, now.timeIntervalSince(timestamp))
        if elapsed < 5 {
            return "Recorded a few seconds ago"
        }
        if elapsed < 60 {
            let seconds = max(1, Int(elapsed.rounded(.down)))
            return seconds == 1 ? "Recorded 1 second ago" : "Recorded \(seconds) seconds ago"
        }
        if elapsed < 3_600 {
            let minutes = max(1, Int(elapsed / 60))
            return minutes == 1 ? "Recorded 1 minute ago" : "Recorded \(minutes) minutes ago"
        }
        if elapsed < 86_400 {
            let hours = max(1, Int(elapsed / 3_600))
            return hours == 1 ? "Recorded 1 hour ago" : "Recorded \(hours) hours ago"
        }
        let days = max(1, Int(elapsed / 86_400))
        return days == 1 ? "Recorded 1 day ago" : "Recorded \(days) days ago"
    }

    private func desiredInterval(for date: Date) -> TimeInterval {
        let elapsed = date.timeIntervalSince(timestamp)
        return elapsed >= 60 ? 60 : 1
    }

    private func startTimer() {
        stopTimer()
        let interval = max(1, desiredInterval(for: now))
        currentInterval = interval
        timerCancellable = Timer.publish(every: interval,
                                         tolerance: interval == 60 ? 5 : 0.1,
                                         on: .main,
                                         in: .common)
            .autoconnect()
            .sink { date in
                now = date
                adjustTimerIfNeeded()
            }
    }

    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    private func adjustTimerIfNeeded() {
        let desired = max(1, desiredInterval(for: now))
        guard desired != currentInterval else { return }
        currentInterval = desired
        startTimer()
    }
}

struct RemoteModelRow: View {
    enum Availability {
        case available
        case offGrid
        case unreachable(message: String)
    }

    let model: RemoteModel
    let endpointType: RemoteBackend.EndpointType
    let availability: Availability
    let isActivating: Bool
    let isActive: Bool
    let useAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .font(.headline)
                        .fontWeight(.semibold)
                    if model.isCustom {
                        chip(text: "Custom", color: .gray)
                    }
                }
                if shouldShowAuthor, let author = sanitizedAuthor {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(model.id)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                badgesRow
                if let parent = model.parentModel, !parent.isEmpty {
                    Label("Parent: \(parent)", systemImage: "arrow.merge")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .textSelection(.enabled)
                }
                if shouldShowDigest, let digest = model.digest, !digest.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "number")
                        Text("Digest:")
                        Text(digest)
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                }
                if let updated = model.modifiedAtDisplayString {
                    Label("Updated \(updated)", systemImage: "clock.arrow.circlepath")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let state = model.state, !state.isEmpty {
                    Label("State: \(state)", systemImage: "bolt.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let ctx = model.maxContextLength {
                    Label("Max context: \(ctx)", systemImage: "text.alignleft")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            trailingControl
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var trailingControl: some View {
        switch availability {
        case .offGrid:
            Label("Offline", systemImage: "wifi.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .unreachable(let message):
            VStack(alignment: .trailing, spacing: 4) {
                Label("Unavailable", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !message.isEmpty {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        case .available:
            if isActive {
                Label("Using", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundColor(.green)
            } else {
                Button(action: useAction) {
                    if isActivating {
                        ProgressView()
                    } else {
                        Text("Use")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isActivating)
            }
        }
    }

    @ViewBuilder
    private var badgesRow: some View {
        HStack(spacing: 6) {
            if let quant = model.quantization, !quant.isEmpty {
                Text(quant)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                    .foregroundColor(Color.accentColor)
            }
            if let format = model.compatibilityFormat {
                Text(format.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(format.tagGradient)
                    .clipShape(Capsule())
                    .foregroundColor(.white)
            }
            ForEach(model.displayFamilies, id: \.self) { family in
                chip(text: family, color: .teal)
            }
            if shouldShowExtendedChips, let parameter = model.formattedParameterCount {
                chip(text: parameter, color: .orange)
            }
            if shouldShowExtendedChips, let size = model.formattedFileSize {
                chip(text: size, color: .blue)
            }
        }
    }

    private func chip(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundColor(color)
    }

    private var isOllama: Bool {
        endpointType == .ollama
    }

    private var sanitizedAuthor: String? {
        let trimmed = model.author.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        return trimmed
    }

    private var shouldShowAuthor: Bool {
        guard sanitizedAuthor != nil else { return false }
        return !isOllama
    }

    private var shouldShowDigest: Bool {
        !isOllama
    }

    private var shouldShowExtendedChips: Bool {
        !isOllama
    }
}
