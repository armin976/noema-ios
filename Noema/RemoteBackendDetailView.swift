#if os(iOS) || os(visionOS) || os(macOS)
import SwiftUI
import Foundation
import Combine
import RelayKit
#if os(macOS)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

struct RemoteBackendDetailView: View {
    let backendID: RemoteBackend.ID

    @EnvironmentObject var modelManager: AppModelManager
    @EnvironmentObject var vm: ChatVM
    @EnvironmentObject var tabRouter: TabRouter
    @Environment(\.dismiss) private var dismiss
#if os(macOS)
    @Environment(\.macModalDismiss) private var macModalDismiss
    @EnvironmentObject private var macModalPresenter: MacModalPresenter
#endif
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
    @State private var localSSID: String?
#if os(iOS) || os(visionOS)
    @State private var showLANOverrideConfirmation = false
#endif
    @FocusState private var focusedField: EditableField?

    private enum EditableField: Hashable {
        case name, baseURL, hostID, chatPath, modelsPath, auth
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
                detailContent(for: backend)
            } else {
                if #available(iOS 17.0, macOS 14.0, visionOS 1.0, *) {
                    ContentUnavailableView("Backend not found", systemImage: "exclamationmark.triangle")
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text(LocalizedStringKey("Backend not found"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .alert(item: $actionMessage) { message in
            Alert(
                title: Text(message.isError ? LocalizedStringKey("Error") : LocalizedStringKey("Success")),
                message: Text(message.message),
                dismissButton: .default(Text(LocalizedStringKey("OK")))
            )
        }
    }

    @ViewBuilder
    private func detailContent(for backend: RemoteBackend) -> some View {
        detailBaseContent(for: backend)
            .navigationTitle(backend.name)
#if !os(macOS)
            .toolbar { toolbarContent(for: backend) }
#endif
            .onAppear {
                syncAuthExpansion(with: backend)
#if os(macOS)
                updateMacModalTitle(using: backend)
#endif
            }
            .onChange(of: backend.id) { _ in
                syncAuthExpansion(with: backend)
#if os(macOS)
                updateMacModalTitle(using: backend)
#endif
            }
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
#if os(iOS) || os(visionOS)
            .task {
                await refreshLocalSSID()
            }
#if canImport(UIKit)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                Task { await refreshLocalSSID() }
            }
#endif
#endif
#if os(macOS)
            .onChange(of: backend.name) { _ in
                updateMacModalTitle(using: backend)
            }
            .onChange(of: editedDraft?.name ?? "") { _ in
                updateMacModalTitle(using: backend)
            }
#endif
    }

    @ViewBuilder
    private func detailBaseContent(for backend: RemoteBackend) -> some View {
#if os(macOS)
        ScrollView {
            // Inline action row to avoid spawning a window toolbar on macOS
            LazyVStack(alignment: .leading, spacing: 24) {
                connectionSection(for: backend)
                modelsSection(for: backend)
                serverTypeSection(for: backend)
                authenticationSection(for: backend)
                modelIdentifiersSection(for: backend)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .refreshable { @MainActor in
            await refreshModelsIfPossible()
        }
        // Keep action buttons visually aligned with the header close control
        .overlay(alignment: .topTrailing) {
            macInlineActions(for: backend)
                .padding(.top, 14)
                .padding(.trailing, 22)
        }
#else
        List {
            connectionSection(for: backend)
            modelsSection(for: backend)
            serverTypeSection(for: backend)
            authenticationSection(for: backend)
            modelIdentifiersSection(for: backend)
        }
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { @MainActor in
            await refreshModelsIfPossible()
        }
        // Present primary actions at the bottom instead of in the chrome
#if os(iOS) || os(visionOS)
        .safeAreaInset(edge: .bottom) {
            bottomActionBar(for: backend)
        }
#endif
#endif
    }

    // MARK: - Sections

    @ViewBuilder
    private func connectionSection(for backend: RemoteBackend) -> some View {
#if os(macOS)
        MacSection(LocalizedStringKey("Connection")) {
            VStack(alignment: .leading, spacing: 16) {
                connectionSectionContent(for: backend)
            }
        }
#else
        Section(LocalizedStringKey("Connection")) {
            connectionSectionContent(for: backend)
        }
#endif
    }

    @ViewBuilder
    private func connectionSectionContent(for backend: RemoteBackend) -> some View {
        let status = connectionStatus(for: backend)
        connectionStatusRow(for: backend, cachedStatus: status)
#if os(iOS) || os(visionOS)
        if let summary = connectionModeSummary(for: backend, isConnected: status.isConnected) {
            connectionModeBanner(for: summary, backend: backend)
                .padding(.top, 8)
        }
        relayContainerRow(for: backend)
#endif
#if !(os(iOS) || os(visionOS))
        let endpoints = restEndpointItems(for: backend)
        if !endpoints.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(LocalizedStringKey("REST Endpoints"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(endpoints) { item in
                    endpointRow(for: item)
                }
            }
            .padding(.top, 6)
        }
#endif
        editableRow(
            title: LocalizedStringKey("Name"),
            systemImage: "textformat",
            value: backend.name,
            field: .name,
            backend: backend
        ) { binding in
            TextField(LocalizedStringKey("Backend Name"), text: binding)
                .platformAutocapitalization(.words)
                .focused($focusedField, equals: .name)
        }
        editableRow(
            title: backend.isCloudRelay ? LocalizedStringKey("Container") : LocalizedStringKey("Base URL"),
            systemImage: backend.isCloudRelay ? "icloud" : "link",
            value: backend.baseURLString,
            field: .baseURL,
            backend: backend
        ) { binding in
            baseURLEditingField(binding: binding, backend: backend)
        }
        if backend.isCloudRelay {
            editableRow(
                title: LocalizedStringKey("Host Device ID"),
                systemImage: "laptopcomputer.and.iphone",
                value: backend.relayHostDeviceID ?? "",
                field: .hostID,
                backend: backend,
                emptyPlaceholder: String(localized: "Not set")
            ) { binding in
                TextField(LocalizedStringKey("Host device ID"), text: binding)
                    .platformAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .focused($focusedField, equals: .hostID)
            }
            Label(LocalizedStringKey("Messages are synced through CloudKit and processed by the macOS relay server."), systemImage: "arrow.triangle.2.circlepath")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        } else {
            editableRow(
                title: LocalizedStringKey("Chat Path"),
                systemImage: "bubble.left.and.text.bubble.right",
                value: backend.chatPath,
                field: .chatPath,
                backend: backend
            ) { binding in
                TextField((editedDraft?.endpointType ?? backend.endpointType).defaultChatPath, text: binding)
                    .platformAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .focused($focusedField, equals: .chatPath)
            }
            editableRow(
                title: LocalizedStringKey("Models Path"),
                systemImage: "tray.and.arrow.down",
                value: backend.modelsPath,
                field: .modelsPath,
                backend: backend
            ) { binding in
                TextField((editedDraft?.endpointType ?? backend.endpointType).defaultModelsPath, text: binding)
                    .platformAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .focused($focusedField, equals: .modelsPath)
            }
        }
        if backend.usesLoopbackHost {
            Label(loopbackWarningText(for: backend), systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        if offGrid {
            Label(LocalizedStringKey("Off-Grid mode blocks remote connections."), systemImage: "wifi.slash")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    private struct EndpointItem: Identifiable {
        let id = UUID()
        let title: String
        let value: String
        let icon: String
    }

    private func restEndpointItems(for backend: RemoteBackend) -> [EndpointItem] {
        var items: [EndpointItem] = []
        switch backend.endpointType {
        case .noemaRelay:
            if let base = backend.relayLANBaseURL?.absoluteString {
                items.append(EndpointItem(title: String(localized: "LAN Base"), value: base, icon: "wifi.router"))
            }
            if let chat = backend.relayLANChatEndpointURL?.absoluteString {
                items.append(EndpointItem(title: String(localized: "LAN Chat"), value: chat, icon: "bubble.left.and.bubble.right"))
            }
            if let models = backend.relayLANModelsEndpointURL?.absoluteString {
                items.append(EndpointItem(title: String(localized: "LAN Models"), value: models, icon: "square.stack.3d.up"))
            }
            if let responses = backend.relayAbsoluteURL(for: "/api/v0/responses")?.absoluteString {
                items.append(EndpointItem(title: String(localized: "LAN Responses"), value: responses, icon: "arrow.uturn.forward"))
            }
        case .cloudRelay:
            let container = backend.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            if !container.isEmpty {
                items.append(EndpointItem(title: String(localized: "CloudKit Container"), value: container, icon: "icloud"))
            }
        default:
            if let chat = backend.chatEndpointURL?.absoluteString {
                items.append(EndpointItem(title: String(localized: "Chat Endpoint"), value: chat, icon: "bubble.left.and.bubble.right"))
            }
            if backend.endpointType == .openAI,
               let completions = backend.absoluteURL(for: "/v1/completions")?.absoluteString {
                items.append(EndpointItem(title: String(localized: "Completions Endpoint"), value: completions, icon: "text.quote"))
            }
            if let models = backend.modelsEndpointURL?.absoluteString {
                items.append(EndpointItem(title: String(localized: "Models Endpoint"), value: models, icon: "square.stack.3d.up"))
            }
        }
        return items
    }

    @ViewBuilder
    private func endpointRow(for item: EndpointItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: item.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(item.value)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.primary)
            }
        }
    }

    @ViewBuilder
    private func serverTypeSection(for backend: RemoteBackend) -> some View {
        #if os(macOS)
        MacSection(LocalizedStringKey("Endpoint Type")) {
            VStack(alignment: .leading, spacing: 12) {
                serverTypeSectionContent(for: backend)
            }
        }
        #else
        Section(LocalizedStringKey("Endpoint Type")) {
            serverTypeSectionContent(for: backend)
        }
        #endif
    }

    @ViewBuilder
    private func serverTypeSectionContent(for backend: RemoteBackend) -> some View {
        if isEditing, let binding = draftBinding(for: \RemoteBackendDraft.endpointType, backend: backend) {
            #if os(macOS)
            Picker("Endpoint", selection: binding) {
                ForEach(RemoteBackend.EndpointType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)
            #else
            EndpointTypeSelectionBoxes(selection: binding)
            #endif
        } else {
            LabeledContent(LocalizedStringKey("Type")) {
                Text(backend.endpointType.displayName)
                    .font(.callout)
                    .foregroundStyle(.primary)
            }
        }
    }

    @ViewBuilder
    private func authenticationSection(for backend: RemoteBackend) -> some View {
        if backend.isCloudRelay {
            EmptyView()
        } else {
            #if os(macOS)
            MacSection(LocalizedStringKey("Authentication")) {
                authenticationSectionContent(for: backend)
            }
            #else
            Section {
                authenticationSectionContent(for: backend)
            }
            #endif
        }
    }

    @ViewBuilder
    private func authenticationSectionContent(for backend: RemoteBackend) -> some View {
        DisclosureGroup(isExpanded: $isAuthExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                if isEditing, let binding = draftBinding(for: \RemoteBackendDraft.authHeader, backend: backend) {
                    editingFieldContainer {
                        TextField(LocalizedStringKey("Bearer ..."), text: binding, axis: .vertical)
                            .platformAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .focused($focusedField, equals: .auth)
                    }
                } else {
                    let value = backend.authHeader?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if value.isEmpty {
                        Text(LocalizedStringKey("Not provided"))
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
            Label(LocalizedStringKey("Authentication"), systemImage: "key")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func modelIdentifiersSection(for backend: RemoteBackend) -> some View {
        #if os(macOS)
        MacSection(LocalizedStringKey("Model Identifiers")) {
            VStack(alignment: .leading, spacing: 12) {
                modelIdentifiersSectionContent(for: backend)
            }
        }
        #else
        Section(LocalizedStringKey("Model Identifiers")) {
            modelIdentifiersSectionContent(for: backend)
        }
        #endif
    }

    @ViewBuilder
    private func modelIdentifiersSectionContent(for backend: RemoteBackend) -> some View {
        if isEditing {
            let draft = editedDraft ?? backendDraftSnapshot(from: backend)
            ForEach(Array(draft.customModelIDs.enumerated()), id: \.offset) { index, _ in
                HStack(alignment: .top, spacing: 8) {
                    editingFieldContainer {
                        TextField(LocalizedStringKey("Model identifier"), text: customModelBinding(for: index, backend: backend), axis: .vertical)
                            .platformAutocapitalization(.never)
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
                Label(LocalizedStringKey("Add Identifier"), systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
            .padding(.top, 4)
        } else {
            if backend.customModelIDs.isEmpty {
                Text(LocalizedStringKey("Using server catalog"))
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
        Text(LocalizedStringKey("Specify identifiers for models that are not listed by the server. Leave blank to rely on the server's catalog."))
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func modelsSection(for backend: RemoteBackend) -> some View {
        #if os(macOS)
        MacSection(LocalizedStringKey("Models")) {
            VStack(alignment: .leading, spacing: 16) {
                modelsSectionContent(for: backend)
            }
        }
        #else
        Section(LocalizedStringKey("Models")) {
            modelsSectionContent(for: backend)
        }
        #endif
    }

    @ViewBuilder
    private func modelsSectionContent(for backend: RemoteBackend) -> some View {
        let models = backend.cachedModels.filter { !$0.isEmbedding }
        let decoratedModels = models.enumerated().map { index, model in
            (index: index, model: model, isLoaded: model.isLoadedOnBackend)
        }
        let sortedModels = decoratedModels.sorted { lhs, rhs in
            if lhs.isLoaded != rhs.isLoaded {
                return lhs.isLoaded && !rhs.isLoaded
            }
            return lhs.index < rhs.index
        }
        if backend.isCloudRelay {
            Text(LocalizedStringKey("Responses are generated by the macOS relay server. Configure the provider (LM Studio or Ollama) on the Mac app."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
        } else if backend.endpointType == .noemaRelay {
            Text(LocalizedStringKey("Models shown here are exposed by the Mac relay. Manage sources in the Relay tab on macOS to share more models."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
        }
        if sortedModels.isEmpty {
            VStack(spacing: 8) {
                Text(offGrid ? LocalizedStringKey("Remote access is disabled.") : LocalizedStringKey("No compatible models available"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if !offGrid {
                    Button {
                        triggerManualRefresh()
                    } label: {
                        Label(LocalizedStringKey("Reload Models"), systemImage: "arrow.clockwise")
                    }
                    .disabled(refreshTask != nil)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        } else {
            ForEach(sortedModels, id: \.model.id) { entry in
                RemoteModelRow(
                    model: entry.model,
                    endpointType: backend.endpointType,
                    availability: modelAvailability(for: backend),
                    isActivating: activatingModelID == entry.model.id,
                    isActive: activeRemoteModelID == entry.model.id,
                    isBackendLoaded: entry.isLoaded,
                    useAction: { use(model: entry.model, in: backend) }
                )
            }
        }
    }

#if os(macOS)
    private struct MacSection<Content: View>: View {
        let title: LocalizedStringKey
        let content: Content

        init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
            self.title = title
            self.content = content()
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(FontTheme.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .textCase(.uppercase)
                    .padding(.leading, 4)
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(AppTheme.cardFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AppTheme.cardStroke, lineWidth: 1)
                    )
            }
        }
    }
#endif

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func toolbarContent(for backend: RemoteBackend) -> some ToolbarContent {
#if os(macOS)
        ToolbarItemGroup(placement: .automatic) {
            Button(LocalizedStringKey("Close")) { close() }
            trailingToolbarItems(for: backend)
        }
#else
        ToolbarItem(placement: .cancellationAction) {
            Button(LocalizedStringKey("Close")) { close() }
        }
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            trailingToolbarItems(for: backend)
        }
#endif
    }

    @ViewBuilder
    private func trailingToolbarItems(for backend: RemoteBackend) -> some View {
        #if os(macOS)
        macInlineActions(for: backend)
        #else
        touchToolbarActions(for: backend)
        #endif
    }

#if os(macOS)
    @ViewBuilder
    private func macInlineActions(for backend: RemoteBackend) -> some View {
        HStack(spacing: 8) {
            if isEditing {
                Button(LocalizedStringKey("Cancel")) {
                    cancelEditingChanges()
                }
                .controlSize(.small)
                .buttonStyle(.bordered)

                Button {
                    Task { await finishEditing(for: backend) }
                } label: {
                    if isPersistingDraft {
                        ProgressView()
                    } else {
                        Text(LocalizedStringKey("Save"))
                    }
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled(isPersistingDraft)
            } else {
                if let task = activationTask, !task.isCancelled {
                    Button {
                        cancelActivation()
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Cancel remote load")
                }
                if let task = refreshTask, !task.isCancelled {
                    Button {
                        cancelRefresh()
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Cancel reload")
                    ProgressView()
                } else if modelManager.remoteBackendsFetching.contains(backendID) {
                    ProgressView()
                } else if !offGrid {
                    Button {
                        triggerManualRefresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Reload models")
                    .disabled(refreshTask != nil)
                }

                Divider()
                    .frame(height: 16)
                    .padding(.horizontal, 2)

                Button {
                    startEditing(with: backend)
                } label: {
                    Label(LocalizedStringKey("Edit"), systemImage: "pencil")
                        .labelStyle(.iconOnly)
                }
                .controlSize(.small)
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    deleteBackend()
                } label: {
                    Label(LocalizedStringKey("Delete"), systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 4)
    }
#else
    @ViewBuilder
    private func touchToolbarActions(for backend: RemoteBackend) -> some View {
        if isEditing {
            Button {
                Task { await finishEditing(for: backend) }
            } label: {
                if isPersistingDraft {
                    ProgressView()
                } else {
                    Text(LocalizedStringKey("Done"))
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
                    Label(LocalizedStringKey("Edit"), systemImage: "pencil")
                }

                Button(role: .destructive) {
                    deleteBackend()
                } label: {
                    Label(LocalizedStringKey("Delete Backend"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
#endif

#if os(iOS) || os(visionOS)
    // MARK: - Bottom Action Bar (iOS / visionOS)

    @ViewBuilder
    private func bottomActionBar(for backend: RemoteBackend) -> some View {
        VStack(spacing: 8) {
            Divider()
            if isEditing {
                HStack(spacing: 12) {
                    Button(role: .cancel) {
                        cancelEditingChanges()
                    } label: {
                        Text("Cancel")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task { await finishEditing(for: backend) }
                    } label: {
                        if isPersistingDraft {
                            HStack(spacing: 6) {
                                ProgressView()
                                Text("Saving…")
                            }
                        } else {
                            Label("Save Changes", systemImage: "checkmark")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isPersistingDraft)
                }
                .frame(maxWidth: .infinity)
            } else {
                Button {
                    startEditing(with: backend)
                } label: {
                    Label("Edit Remote Endpoint", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(.thinMaterial)
    }
#endif

    private func cancelEditingChanges() {
        focusedField = nil
        editedDraft = nil
        hasDraftChanges = false
        isEditing = false
    }

    // MARK: - Helpers

    private func connectionStatusRow(for backend: RemoteBackend, cachedStatus: (text: String, color: Color, symbol: String, isConnected: Bool)? = nil) -> some View {
        let status = cachedStatus ?? connectionStatus(for: backend)
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

            if status.isConnected, let active = activeTransportIndicator(for: backend) {
                HStack(spacing: 8) {
                    Image(systemName: active.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(active.color)
                    Text(active.text)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(active.color)
                    if active.streaming {
                        Label("Streaming", systemImage: "waveform")
                            .labelStyle(.iconOnly)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(active.color)
                            .accessibilityLabel("Token streaming enabled")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(active.color.opacity(0.12), in: Capsule())
                .accessibilityLabel(Text("Active connection via \(active.text)"))
            }

            if let lanIndicator = lanIndicator(for: backend) {
                HStack(spacing: 8) {
                    Image(systemName: lanIndicator.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(lanIndicator.color)
                    Text(lanIndicator.text)
                        .font(.caption2)
                        .foregroundStyle(lanIndicator.color)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(lanIndicator.color.opacity(0.12), in: Capsule())
                .accessibilityLabel(Text(lanIndicator.accessibilityLabel))
            }

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

    private func activeTransportIndicator(for backend: RemoteBackend) -> (symbol: String, text: String, color: Color, streaming: Bool)? {
        guard let session = modelManager.activeRemoteSession,
              session.backendID == backend.id else { return nil }
        switch session.transport {
        case .cloudRelay:
            return ("icloud", "Cloud Relay", .teal, session.streamingEnabled)
        case .lan:
            // Present a neutral LAN label without transport medium/SSID details
            let label = "Local Network"
            return ("wifi.router", label, .green, session.streamingEnabled)
        case .direct:
            return ("bolt.horizontal", "Direct", .blue, session.streamingEnabled)
        }
    }

#if os(iOS) || os(visionOS)
    private struct ConnectionModeSummary {
        let title: String
        let subtitle: String
        let icon: String
        let tint: Color
        let lanURL: String?
        let relaySSID: String?
        let allowOverride: Bool
        let matchingNote: String
    }

    private func connectionModeSummary(for backend: RemoteBackend, isConnected: Bool) -> ConnectionModeSummary? {
        guard backend.endpointType == .noemaRelay else { return nil }
        if offGrid {
            return ConnectionModeSummary(
                title: "Remote connections blocked",
                subtitle: "Off-Grid mode keeps both LAN and Cloud Relay offline until you disable it.",
                icon: "wifi.slash",
                tint: .orange,
                lanURL: nil,
                relaySSID: nil,
                allowOverride: false,
                matchingNote: "Turn off Off-Grid to let the app compare Wi‑Fi names and switch to LAN automatically."
            )
        }
        let lanURL = backend.relayLANURLString?.trimmingCharacters(in: .whitespacesAndNewlines)
        let relaySSID = backend.relayWiFiSSID?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let session = modelManager.activeRemoteSession,
           session.backendID == backend.id {
            switch session.transport {
            case .lan:
                return ConnectionModeSummary(
                    title: "Local Network active",
                    subtitle: "Streaming on the Local Network. We'll fall back to Cloud Relay if the network changes.",
                    icon: "wifi.router",
                    tint: .green,
                    lanURL: lanURL,
                    relaySSID: relaySSID,
                    allowOverride: false,
                    matchingNote: ""
                )
            case .cloudRelay:
                // Keep this simple: connection selection is automatic.
                return ConnectionModeSummary(
                    title: "Connected via Cloud Relay",
                    subtitle: "Noema will switch to Local Network automatically when it’s faster and available.",
                    icon: "icloud",
                    tint: .teal,
                    lanURL: nil,
                    relaySSID: nil,
                    allowOverride: false,
                    matchingNote: ""
                )
            case .direct:
                return ConnectionModeSummary(
                    title: "Direct connection",
                    subtitle: "Streaming through the configured REST endpoint for this backend.",
                    icon: "bolt.horizontal",
                    tint: .blue,
                    lanURL: nil,
                    relaySSID: nil,
                    allowOverride: false,
                    matchingNote: ""
                )
            }
        }

        // Simplify pre-connection guidance: users just pick a model and
        // Noema will choose the best path (LAN when available, otherwise Cloud Relay).
        return ConnectionModeSummary(
            title: "Connection handled automatically",
            subtitle: "Select a model. Noema will choose the fastest path to your relay (Local Network when available, otherwise Cloud Relay).",
            icon: "sparkles",
            tint: .blue,
            lanURL: nil,
            relaySSID: nil,
            allowOverride: false,
            matchingNote: ""
        )
    }

    @ViewBuilder
    private func connectionModeBanner(for summary: ConnectionModeSummary, backend: RemoteBackend) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: summary.icon)
                    .font(.headline.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(summary.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(summary.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if let lanURL = summary.lanURL, !lanURL.isEmpty {
                Text(lanURL)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }

            if let ssid = summary.relaySSID, !ssid.isEmpty {
                Label("Relay Wi‑Fi: \(ssid)", systemImage: "wifi")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !summary.matchingNote.isEmpty {
                Text(summary.matchingNote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if summary.allowOverride {
                Button {
                    showLANOverrideConfirmation = true
                } label: {
                    Text("Force Local Network")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(summary.tint)

                Text("Forces chat traffic through the last LAN host even if Wi‑Fi names don't match yet.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(summary.tint.opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .confirmationDialog("Force Local Network?", isPresented: $showLANOverrideConfirmation) {
            Button("Force Local Network", role: .destructive) {
                forceLANOverride(for: backend)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("We'll route new conversations through \(summary.lanURL ?? "the last LAN host") even if Wi‑Fi names differ. You can switch back by reloading the backend.")
        }
    }

    @ViewBuilder
    private func relayContainerRow(for backend: RemoteBackend) -> some View {
#if os(iOS)
        EmptyView()
#else
        if backend.endpointType != .noemaRelay {
            EmptyView()
        } else {
            let container = backend.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            if container.isEmpty {
                EmptyView()
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "icloud")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cloud Relay Container")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(container)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .foregroundStyle(.primary)
                    }
                }
                .padding(.top, 6)
            }
        }
#endif
    }
#endif

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

#if os(iOS) || os(visionOS)
    private func forceLANOverride(for backend: RemoteBackend) {
        guard backend.endpointType == .noemaRelay else { return }
        // If a chat session is active for this backend, push the override through
        // the live RemoteChatService so the transport toggles immediately.
        if let session = modelManager.activeRemoteSession, session.backendID == backend.id {
            vm.forceLANOverride(reason: "user-force-lan")
            vm.requestImmediateLANCheck(reason: "user-force-lan")
            actionMessage = RemoteBackendActionMessage(message: "Switching to Local Network…", isError: false)
            return
        }
        // Otherwise, request a LAN metadata refresh via Cloud Relay so the
        // banner and connection details update, then evaluate adoption.
        Task { @MainActor in
            actionMessage = RemoteBackendActionMessage(message: "Checking Local Network for this relay…", isError: false)
        }
        Task {
            await modelManager.requestRelayLANRefresh(for: backendID,
                                                      reason: "user-force-lan",
                                                      force: true)
            await modelManager.fetchRemoteModels(for: backendID)
            await evaluateLANAdoptionAfterRefresh()
        }
    }
#endif

    private func editableRow<Content: View>(
        title: LocalizedStringKey,
        systemImage: String,
        value: String,
        field: EditableField,
        backend: RemoteBackend,
        emptyPlaceholder: String? = nil,
        @ViewBuilder content: (Binding<String>) -> Content
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
        #if os(macOS)
        content()
            .font(.callout)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .padding(.vertical, 2)
        #else
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
        #endif
    }

    @ViewBuilder
    private func baseURLEditingField(binding: Binding<String>, backend: RemoteBackend) -> some View {
        HStack(spacing: 8) {
            Group {
                if backend.isCloudRelay {
                    TextField("iCloud.arminproducts.Noema", text: binding)
                        .platformAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .focused($focusedField, equals: .baseURL)
                } else {
                    TextField("https://example.com", text: binding)
                        .platformKeyboardType(.url)
                        .platformAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .focused($focusedField, equals: .baseURL)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(binding.wrappedValue.isEmpty ? "Paste" : "Clear & Paste") {
                pasteBaseURL(into: binding, clearExisting: !binding.wrappedValue.isEmpty)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(.footnote.weight(.semibold))
        }
    }

    private func pasteBaseURL(into binding: Binding<String>, clearExisting: Bool) {
        if clearExisting {
            binding.wrappedValue = ""
        }
        if let pasted = currentPasteboardString()?.trimmingCharacters(in: .whitespacesAndNewlines), !pasted.isEmpty {
            binding.wrappedValue = pasted
        } else if clearExisting {
            binding.wrappedValue = ""
        }
        focusedField = .baseURL
    }

    private func currentPasteboardString() -> String? {
#if canImport(UIKit)
        UIPasteboard.general.string
#elseif os(macOS)
        if let item = NSPasteboard.general.pasteboardItems?.first,
           let value = item.string(forType: .string) {
            return value
        }
        return NSPasteboard.general.string(forType: .string)
#else
        nil
#endif
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
        case .hostID: return \RemoteBackendDraft.relayHostDeviceID
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

    private func connectionStatus(for backend: RemoteBackend) -> (text: String, color: Color, symbol: String, isConnected: Bool) {
        if offGrid {
            return ("Connection blocked", .orange, "wifi.slash", false)
        }
        if modelManager.remoteBackendsFetching.contains(backendID) {
            return ("Trying to connect", .yellow, "clock.arrow.2.circlepath", false)
        }
        if let error = backend.lastError, !error.isEmpty {
            return ("Disconnected", .red, "exclamationmark.octagon", false)
        }
        if backend.lastFetched != nil {
            return ("Connected", .green, "checkmark.circle", true)
        }
        return ("Never connected", .secondary, "questionmark.circle", false)
    }

#if os(iOS) || os(visionOS)
    private func lanIndicator(for backend: RemoteBackend) -> (text: String, color: Color, symbol: String, accessibilityLabel: String)? {
        // Hide pre-connection "reachable"/"ready" badges. Only surface a
        // lightweight indicator when LAN is actually in use.
        guard backend.endpointType == .noemaRelay else { return nil }
        guard let session = modelManager.activeRemoteSession,
              session.backendID == backend.id else { return nil }
        guard case .lan = session.transport else { return nil }

        let local = localSSID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = local.flatMap { "Local Network in use (\($0))" } ?? "Local Network in use"
        return (text, .green, "arrow.triangle.2.circlepath.circle.fill", "Streaming on the Local Area Network")
    }
#else
    private func lanIndicator(for backend: RemoteBackend) -> (text: String, color: Color, symbol: String, accessibilityLabel: String)? {
        // macOS: only show an indicator when LAN is actively being used.
        guard backend.endpointType == .noemaRelay else { return nil }
        guard let session = modelManager.activeRemoteSession,
              session.backendID == backend.id else { return nil }
        guard case .lan = session.transport else { return nil }
        let text = "Local Network in use"
        return (text, .green, "arrow.triangle.2.circlepath.circle.fill", "Streaming on the Local Area Network")
    }
#endif

    private func startEditing(with backend: RemoteBackend) {
        editedDraft = RemoteBackendDraft(from: backend)
        hasDraftChanges = false
        isEditing = true
    }

    private func deleteBackend() {
        modelManager.deleteRemoteBackend(id: backendID)
        close()
    }

#if os(iOS) || os(visionOS)
    private func requestLANStatusRefreshIfNeeded() async {
        guard let backend = modelManager.remoteBackend(withID: backendID),
              backend.endpointType == .noemaRelay else { return }
        await modelManager.requestRelayLANRefresh(for: backendID,
                                                  reason: "detail-view",
                                                  force: true)
    }

    @MainActor
    private func evaluateLANAdoptionAfterRefresh() async {
        guard let updatedBackend = modelManager.remoteBackend(withID: backendID) else { return }
        guard updatedBackend.endpointType == .noemaRelay else { return }

        var lanURLString = updatedBackend.relayLANURLString?.trimmingCharacters(in: .whitespacesAndNewlines)
        var hostSSID = updatedBackend.relayWiFiSSID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let localSSIDRaw = await WiFiSSIDProvider.shared.currentSSID()
        let localSSIDTrimmed = localSSIDRaw?.trimmingCharacters(in: .whitespacesAndNewlines)

        let interfaceDescription = updatedBackend.relayLANInterface?.rawValue ?? "nil"
        await logger.log("[RemoteBackendDetail] [LAN] Reloaded metadata for '\(updatedBackend.name)' – hostSSID=\(hostSSID ?? "nil"), lanURL=\(lanURLString ?? "nil"), localSSID=\(localSSIDTrimmed ?? "nil"), interface=\(interfaceDescription)")

        if lanURLString?.isEmpty ?? true {
            await logger.log("[RemoteBackendDetail] [LAN] No LAN URL advertised for '\(updatedBackend.name)' after reload; retrying once after delay.")
            try? await Task.sleep(nanoseconds: 400_000_000)
            await modelManager.fetchRemoteModels(for: backendID)
            guard let retryBackend = modelManager.remoteBackend(withID: backendID) else { return }
            lanURLString = retryBackend.relayLANURLString?.trimmingCharacters(in: .whitespacesAndNewlines)
            hostSSID = retryBackend.relayWiFiSSID?.trimmingCharacters(in: .whitespacesAndNewlines)
            let retryInterface = retryBackend.relayLANInterface?.rawValue ?? "nil"
            await logger.log("[RemoteBackendDetail] [LAN] Retry metadata for '\(retryBackend.name)' – hostSSID=\(hostSSID ?? "nil"), lanURL=\(lanURLString ?? "nil"), interface=\(retryInterface)")
            if lanURLString?.isEmpty ?? true {
                await logger.log("[RemoteBackendDetail] [LAN] No LAN URL advertised for '\(retryBackend.name)' after retry.")
                return
            }
        }

        guard let lanURLString else { return }

        let ssidMatches: Bool = {
            guard let hostSSID, !hostSSID.isEmpty,
                  let localSSIDTrimmed, !localSSIDTrimmed.isEmpty else {
                return false
            }
            return LANSubnet.ssidsMatch(hostSSID, localSSIDTrimmed)
        }()

        var shouldAdoptLAN = ssidMatches

        // If the Mac is on Ethernet (no SSID), detect same subnet as an alternative signal.
        if !shouldAdoptLAN,
           hostSSID?.isEmpty != false,
           let host = updatedBackend.relayLANChatEndpointURL?.host,
           LANSubnet.isSameSubnet(host: host) {
            shouldAdoptLAN = true
            await logger.log("[RemoteBackendDetail] [LAN] Same-subnet match for '\(updatedBackend.name)' (host=\(host)); adopting LAN.")
        }

        if !shouldAdoptLAN {
            let reachable = await probeLANReachability(for: updatedBackend)
            if reachable {
                shouldAdoptLAN = true
                await logger.log("[RemoteBackendDetail] [LAN] LAN endpoint reachable for '\(updatedBackend.name)' despite SSID mismatch; proceeding with LAN adoption.")
            } else {
                await logger.log("[RemoteBackendDetail] [LAN] LAN endpoint not reachable for '\(updatedBackend.name)'; staying on Cloud Relay.")
            }
        } else {
            await logger.log("[RemoteBackendDetail] [LAN] Local SSID matches host (\(hostSSID ?? "<unknown>")); adopting LAN for '\(updatedBackend.name)'.")
        }

        if shouldAdoptLAN {
            if let localSSIDTrimmed, !localSSIDTrimmed.isEmpty {
                localSSID = localSSIDTrimmed
            }
            if let activeID = activeRemoteModelID {
                do {
                    try await vm.refreshActiveRemoteBackendIfNeeded(updatedBackendID: backendID, activeModelID: activeID)
                    await logger.log("[RemoteBackendDetail] [LAN] Active remote session refreshed with latest LAN metadata for '\(updatedBackend.name)'.")
                } catch {
                    await logger.log("[RemoteBackendDetail] [LAN] Failed to refresh active session for '\(updatedBackend.name)': \(error.localizedDescription)")
                }
            }
        }
#if os(iOS) || os(visionOS)
        vm.requestImmediateLANCheck(reason: "metadata-update")
#endif
    }

    private func probeLANReachability(for backend: RemoteBackend) async -> Bool {
        // Try GET /v1/health first (no auth), fall back to HEAD on chat.
        if let healthURL = backend.relayLANHealthEndpointURL {
            var req = URLRequest(url: healthURL)
            req.httpMethod = "GET"
            req.timeoutInterval = 3
            let cfg = URLSessionConfiguration.ephemeral
            cfg.timeoutIntervalForRequest = 3
            cfg.timeoutIntervalForResource = 3
            cfg.waitsForConnectivity = false
            let session = URLSession(configuration: cfg)
            defer { session.invalidateAndCancel() }
            do {
                let (_, resp) = try await session.data(for: req)
                if let http = resp as? HTTPURLResponse { return (200...299).contains(http.statusCode) }
            } catch { /* fall through */ }
        }

        guard let url = backend.relayLANChatEndpointURL else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 4
        if let auth = backend.relayAuthorizationHeader {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 4
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200...499).contains(http.statusCode)
        } catch {
            await logger.log("[RemoteBackendDetail] [LAN] LAN probe failed for '\(backend.name)': \(error.localizedDescription)")
            return false
        }
    }

    private func refreshLocalSSID() async {
        let ssid = await WiFiSSIDProvider.shared.currentSSID()
        await MainActor.run {
            localSSID = ssid
        }
    }
#endif

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
        if backend.endpointType.isRelay {
            if let status = backend.relayHostStatus,
               let message = relayHostStatusMessage(for: backend, status: status) {
                return .unreachable(message: message)
            }
            // Avoid flicker: if we're already connected once (have lastFetched),
            // keep models available while a background fetch runs.
            if backend.lastFetched == nil,
               modelManager.remoteBackendsFetching.contains(backend.id) {
                return .unreachable(message: relayPendingConnectionMessage(for: backend, activelyConnecting: true))
            }
            if backend.lastFetched == nil {
                return .unreachable(message: relayPendingConnectionMessage(for: backend, activelyConnecting: false))
            }
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

    private func relayPendingConnectionMessage(for backend: RemoteBackend, activelyConnecting: Bool) -> String {
        let prefix: String
        switch backend.endpointType {
        case .noemaRelay:
            prefix = activelyConnecting ? "Connecting to your Mac relay…" : "Waiting for the Mac relay to finish connecting."
        case .cloudRelay:
            prefix = activelyConnecting ? "Connecting to Cloud Relay…" : "Waiting for Cloud Relay to finish connecting."
        default:
            prefix = activelyConnecting ? "Connecting to relay…" : "Waiting for relay connection."
        }
        return prefix + " Keep the relay app running on your Mac until the status indicator turns green."
    }

    private func relayHostStatusMessage(for backend: RemoteBackend, status: RelayHostStatus) -> String? {
        switch status {
        case .running:
            return nil
        case .loading:
            return relayPendingConnectionMessage(for: backend, activelyConnecting: true)
        case .idle:
            if backend.endpointType == .noemaRelay {
                return "Mac relay is offline. Start it on your Mac to use these models."
            }
            return "Relay is offline. Start it from the Mac app to use these models."
        case .error:
            return "The relay reported an error. Check the Mac relay status before trying again."
        }
    }

    private func cancelActivation() {
        activationTask?.cancel()
        activationTask = nil
        activationToken = nil
        activatingModelID = nil
        Task { await vm.deactivateRemoteSession() }
    }

    private func triggerManualRefresh() {
        Task { await refreshModelsIfPossible(forceRestart: true, includeLANRefresh: true) }
    }

    @MainActor
    private func cancelRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        refreshToken = nil
    }

    @MainActor
    private func refreshModelsIfPossible(forceRestart: Bool = false,
                                         includeLANRefresh: Bool = false) async {
        guard !offGrid else { return }
        if !forceRestart, let existing = refreshTask {
            await existing.value
            return
        }
        refreshTask?.cancel()
        let token = UUID()
        refreshToken = token
#if os(iOS) || os(visionOS)
        if includeLANRefresh {
            if let target = modelManager.remoteBackend(withID: backendID)?.name {
                await logger.log("[RemoteBackendDetail] [LAN] Requesting Cloud Relay metadata refresh for '\(target)'.")
            } else {
                await logger.log("[RemoteBackendDetail] [LAN] Requesting Cloud Relay metadata refresh for backend \(backendID).")
            }
            await requestLANStatusRefreshIfNeeded()
        }
#endif
        let task = Task { @MainActor in
            await modelManager.fetchRemoteModels(for: backendID)
        }
        refreshTask = task
        await task.value
        if refreshToken == token {
            refreshTask = nil
            refreshToken = nil
#if os(iOS) || os(visionOS)
            await evaluateLANAdoptionAfterRefresh()
#endif
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

#if os(macOS)
    @MainActor
    private func updateMacModalTitle(using backend: RemoteBackend) {
        let title = macModalTitle(for: backend)
        macModalPresenter.update(title: title)
    }

    private func macModalTitle(for backend: RemoteBackend) -> String {
        if let draftName = editedDraft?.name.trimmingCharacters(in: .whitespacesAndNewlines), !draftName.isEmpty {
            return draftName
        }
        let backendName = backend.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return backendName.isEmpty ? "Remote Endpoint" : backendName
    }
#endif

    private func close() {
#if os(macOS)
        macModalDismiss()
#else
        dismiss()
#endif
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
    let isBackendLoaded: Bool
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
                if isBackendLoaded {
                    Label("Loaded on server", systemImage: "bolt.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.green)
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
            ForEach(familyBadges, id: \.self) { family in
                chip(text: family, color: .teal)
            }
            if shouldShowExtendedChips, let parameter = model.formattedParameterCount {
                chip(text: parameter, color: .orange)
            }
            if shouldShowExtendedChips, endpointType.isRelay == false, let size = model.formattedFileSize {
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

    private var familyBadges: [String] {
        guard endpointType.isRelay else { return model.displayFamilies }
        let quantLower = model.quantization?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let identifierLower = model.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return model.displayFamilies.filter { family in
            let trimmed = family.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            let lower = trimmed.lowercased()
            if lower == identifierLower { return false }
            if let quantLower, lower == quantLower { return false }
            if lower == "tools" { return false }
            return true
        }
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

#endif
