import Foundation

@MainActor
extension AppModelManager {
    func remoteBackend(withID id: RemoteBackend.ID) -> RemoteBackend? {
        remoteBackends.first { $0.id == id }
    }

    func refreshRemoteBackends(offGrid: Bool) {
        guard !offGrid else { return }
        for backend in remoteBackends {
            Task { [weak self] in
                await self?.fetchRemoteModels(for: backend.id)
            }
        }
    }

    func addRemoteBackend(from draft: RemoteBackendDraft) async throws {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw RemoteBackendError.validationFailed("Please provide a backend name.")
        }
        if remoteBackends.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            throw RemoteBackendError.validationFailed("A backend with this name already exists.")
        }
        let backend = try RemoteBackend(from: draft)
        remoteBackends.append(backend)
        remoteBackends.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        persistRemoteBackends()
        await fetchRemoteModels(for: backend.id)
    }

    func deleteRemoteBackend(id: RemoteBackend.ID) {
        if let index = remoteBackends.firstIndex(where: { $0.id == id }) {
            remoteBackends.remove(at: index)
            persistRemoteBackends()
        }
        remoteBackendsFetching.remove(id)
        if activeRemoteSession?.backendID == id {
            activeRemoteSession = nil
        }
    }

    func updateRemoteBackend(id: RemoteBackend.ID, using draft: RemoteBackendDraft) throws {
        guard let index = remoteBackends.firstIndex(where: { $0.id == id }) else {
            throw RemoteBackendError.validationFailed("Backend not found.")
        }
        let existing = remoteBackends[index]
        let updated = try existing.updating(from: draft)
        remoteBackends[index] = updated
        remoteBackends.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        persistRemoteBackends()
        if activeRemoteSession?.backendID == id {
            activeRemoteSession = ActiveRemoteSession(
                backendID: updated.id,
                backendName: updated.name,
                modelID: activeRemoteSession?.modelID ?? "",
                modelName: activeRemoteSession?.modelName ?? "",
                endpointType: updated.endpointType
            )
        }
    }

    func fetchRemoteModels(for backendID: RemoteBackend.ID) async {
        guard let backend = remoteBackends.first(where: { $0.id == backendID }) else { return }
        if remoteBackendsFetching.contains(backendID) { return }
        remoteBackendsFetching.insert(backendID)
        defer { remoteBackendsFetching.remove(backendID) }
        do {
            let result = try await RemoteBackendAPI.fetchModels(for: backend)
            try? await Task.sleep(nanoseconds: 250_000_000)
            let timestamp = Date()
            let summary = RemoteBackend.ConnectionSummary.success(
                statusCode: result.statusCode,
                reason: result.reason,
                timestamp: timestamp
            )
            updateRemoteBackend(
                backendID: backendID,
                with: result.models,
                error: nil,
                summary: summary
            )
        } catch {
            if error is CancellationError {
                return
            }
            let errorDescription: String
            let summary: RemoteBackend.ConnectionSummary
            let timestamp = Date()
            if let backendError = error as? RemoteBackendError {
                if let backend = remoteBackends.first(where: { $0.id == backendID }) {
                    if backend.endpointType == .ollama,
                       case .validationFailed(let message) = backendError,
                       message.contains("OLLAMA_HOST") {
                        Task { @MainActor in
                            await logger.log("[RemoteBackendAPI] ⚠️ Ollama advisory presented to user")
                        }
                    }
                }
                switch backendError {
                case .unexpectedStatus(let code, _):
                    let reason = RemoteBackend.normalizedStatusReason(for: code)
                    errorDescription = RemoteBackend.statusErrorDescription(for: code, reason: reason)
                    summary = .failure(statusCode: code, reason: reason, timestamp: timestamp)
                case .validationFailed(let message):
                    errorDescription = message
                    summary = .failure(message: message, timestamp: timestamp)
                default:
                    let description = backendError.errorDescription ?? "Unknown error"
                    errorDescription = description
                    summary = .failure(message: description, timestamp: timestamp)
                }
            } else {
                errorDescription = error.localizedDescription
                summary = .failure(message: errorDescription, timestamp: timestamp)
            }
            updateRemoteBackend(
                backendID: backendID,
                with: nil,
                error: errorDescription,
                summary: summary
            )
        }
    }

    private func updateRemoteBackend(
        backendID: RemoteBackend.ID,
        with models: [RemoteModel]?,
        error: String?,
        summary: RemoteBackend.ConnectionSummary?
    ) {
        guard let index = remoteBackends.firstIndex(where: { $0.id == backendID }) else { return }
        var backend = remoteBackends[index]
        if let models {
            let deduped = dedupe(models: models, backend: backend)
            backend.cachedModels = deduped
            backend.lastFetched = summary?.timestamp ?? Date()
            backend.lastError = nil
        }
        if let error {
            backend.lastError = error
        }
        if let summary {
            backend.lastConnectionSummary = summary
        }
        remoteBackends[index] = backend
        persistRemoteBackends()
    }

    private func dedupe(models: [RemoteModel], backend: RemoteBackend) -> [RemoteModel] {
        var seen: Set<String> = []
        var output: [RemoteModel] = []
        for model in models {
            if seen.insert(model.id).inserted {
                output.append(model)
            }
        }
        for custom in backend.customModelIDs {
            if seen.insert(custom).inserted {
                output.append(RemoteModel.makeCustom(id: custom))
            }
        }
        output.sort { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return output
    }

    private func persistRemoteBackends() {
        RemoteBackendsStore.save(remoteBackends)
    }
}
