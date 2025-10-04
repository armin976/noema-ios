import Foundation

struct RemoteBackend: Identifiable, Codable, Equatable {
    typealias ID = UUID

    enum EndpointType: String, Codable, CaseIterable, Identifiable {
        case openAI
        case lmStudio
        case ollama

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .openAI: return "OpenAI API"
            case .lmStudio: return "LM Studio"
            case .ollama: return "Ollama"
            }
        }

        var defaultChatPath: String {
            switch self {
            case .openAI: return "/v1/chat/completions"
            case .lmStudio: return "/api/v0/chat/completions"
            case .ollama: return "/api/chat"
            }
        }

        var defaultModelsPath: String {
            switch self {
            case .openAI: return "/v1/models"
            case .lmStudio: return "/api/v0/models"
            case .ollama: return "/api/tags"
            }
        }
    }

    struct ConnectionSummary: Codable, Equatable {
        enum Kind: String, Codable {
            case success
            case failure
        }

        var kind: Kind
        var statusCode: Int?
        var reason: String?
        var message: String?
        var timestamp: Date

        var displayLine: String {
            if let code = statusCode {
                let normalizedReason = (reason ?? RemoteBackend.normalizedStatusReason(for: code))?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if normalizedReason.isEmpty {
                    return "HTTP \(code)"
                }
                return "HTTP \(code) \(normalizedReason)"
            }
            if let message, !message.isEmpty {
                return message
            }
            return kind == .success ? "Connection successful" : "No response recorded"
        }

        static func success(statusCode: Int, reason: String?, timestamp: Date = Date()) -> ConnectionSummary {
            ConnectionSummary(kind: .success,
                              statusCode: statusCode,
                              reason: reason,
                              message: nil,
                              timestamp: timestamp)
        }

        static func failure(statusCode: Int, reason: String?, timestamp: Date = Date()) -> ConnectionSummary {
            ConnectionSummary(kind: .failure,
                              statusCode: statusCode,
                              reason: reason,
                              message: nil,
                              timestamp: timestamp)
        }

        static func failure(message: String, timestamp: Date = Date()) -> ConnectionSummary {
            ConnectionSummary(kind: .failure,
                              statusCode: nil,
                              reason: nil,
                              message: message,
                              timestamp: timestamp)
        }
    }

    var id: UUID
    var name: String
    var baseURLString: String
    var chatPath: String
    var modelsPath: String
    var authHeader: String?
    var customModelIDs: [String]
    var endpointType: EndpointType
    var cachedModels: [RemoteModel]
    var lastFetched: Date?
    var lastError: String?
    var lastConnectionSummary: ConnectionSummary?

    init(id: UUID = UUID(),
         name: String,
         baseURLString: String,
         chatPath: String,
         modelsPath: String,
         authHeader: String? = nil,
         customModelIDs: [String] = [],
         endpointType: EndpointType,
         cachedModels: [RemoteModel] = [],
         lastFetched: Date? = nil,
         lastError: String? = nil,
         lastConnectionSummary: ConnectionSummary? = nil) {
        self.id = id
        self.name = name
        self.baseURLString = baseURLString
        self.chatPath = chatPath
        self.modelsPath = modelsPath
        self.authHeader = authHeader
        self.customModelIDs = RemoteBackend.normalize(customModelIDs)
        self.endpointType = endpointType
        self.cachedModels = cachedModels
        self.lastFetched = lastFetched
        self.lastError = lastError
        self.lastConnectionSummary = lastConnectionSummary
    }

    init(from draft: RemoteBackendDraft) throws {
        guard let baseURL = draft.validatedBaseURL() else {
            throw RemoteBackendError.invalidBaseURL
        }
        self.init(
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURLString: baseURL.absoluteString,
            chatPath: RemoteBackend.normalize(path: draft.chatPath,
                                             fallback: draft.endpointType.defaultChatPath),
            modelsPath: RemoteBackend.normalize(path: draft.modelsPath,
                                               fallback: draft.endpointType.defaultModelsPath),
            authHeader: draft.authHeader.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draft.authHeader.trimmingCharacters(in: .whitespacesAndNewlines),
            customModelIDs: draft.sanitizedCustomModelIDs,
            endpointType: draft.endpointType
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, baseURLString, chatPath, modelsPath, authHeader, customModelID, customModelIDs, endpointType, cachedModels, lastFetched, lastError, lastConnectionSummary
        // Legacy
        case legacyIsLMStudio = "isLMStudio"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        baseURLString = try container.decode(String.self, forKey: .baseURLString)
        chatPath = try container.decode(String.self, forKey: .chatPath)
        modelsPath = try container.decode(String.self, forKey: .modelsPath)
        authHeader = try container.decodeIfPresent(String.self, forKey: .authHeader)
        if let identifiers = try container.decodeIfPresent([String].self, forKey: .customModelIDs) {
            customModelIDs = RemoteBackend.normalize(identifiers)
        } else if let legacyIdentifier = try container.decodeIfPresent(String.self, forKey: .customModelID) {
            customModelIDs = RemoteBackend.normalize([legacyIdentifier])
        } else {
            customModelIDs = []
        }
        if let type = try container.decodeIfPresent(EndpointType.self, forKey: .endpointType) {
            endpointType = type
        } else if let legacy = try container.decodeIfPresent(Bool.self, forKey: .legacyIsLMStudio) {
            endpointType = legacy ? .lmStudio : .openAI
        } else {
            endpointType = .openAI
        }
        cachedModels = try container.decodeIfPresent([RemoteModel].self, forKey: .cachedModels) ?? []
        lastFetched = try container.decodeIfPresent(Date.self, forKey: .lastFetched)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        lastConnectionSummary = try container.decodeIfPresent(ConnectionSummary.self, forKey: .lastConnectionSummary)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(baseURLString, forKey: .baseURLString)
        try container.encode(chatPath, forKey: .chatPath)
        try container.encode(modelsPath, forKey: .modelsPath)
        try container.encodeIfPresent(authHeader, forKey: .authHeader)
        if !customModelIDs.isEmpty {
            try container.encode(customModelIDs, forKey: .customModelIDs)
        }
        try container.encode(endpointType, forKey: .endpointType)
        try container.encode(cachedModels, forKey: .cachedModels)
        try container.encodeIfPresent(lastFetched, forKey: .lastFetched)
        try container.encodeIfPresent(lastError, forKey: .lastError)
        try container.encodeIfPresent(lastConnectionSummary, forKey: .lastConnectionSummary)
    }

    static func normalize(_ identifiers: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for raw in identifiers {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed).inserted {
                ordered.append(trimmed)
            }
        }
        return ordered
    }

    var isLMStudio: Bool { endpointType == .lmStudio }
    var isOpenAI: Bool { endpointType == .openAI }
    var isOllama: Bool { endpointType == .ollama }

    var baseURL: URL? {
        URL(string: baseURLString)
    }

    var normalizedChatPath: String {
        RemoteBackend.normalize(path: chatPath, fallback: endpointType.defaultChatPath)
    }

    var normalizedModelsPath: String {
        RemoteBackend.normalize(path: modelsPath, fallback: endpointType.defaultModelsPath)
    }

    var modelsEndpointURL: URL? {
        absoluteURL(for: normalizedModelsPath)
    }

    var chatEndpointURL: URL? {
        absoluteURL(for: normalizedChatPath)
    }

    var hasAuth: Bool { (authHeader?.isEmpty ?? true) == false }

    var hasCustomModels: Bool { !customModelIDs.isEmpty }

    var displayBaseHost: String {
        baseURL?.host ?? baseURLString
    }

    var usesLoopbackHost: Bool {
        guard let host = baseURL?.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    func absoluteURL(for path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return baseURL
        }
        if let absolute = URL(string: trimmed), absolute.scheme != nil {
            return absolute
        }
        guard let baseURL else { return nil }
        let prefixed = trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
        return URL(string: prefixed, relativeTo: baseURL)?.absoluteURL
    }

    func loadPathCandidates(for modelID: String) -> [String] {
        let encodedID = modelID.addingPercentEncoding(withAllowedCharacters: .remoteModelIDAllowed) ?? modelID
        var candidates: [String] = []
        if isLMStudio {
            candidates.append("/api/v0/models/\(encodedID)/load")
        }
        let modelsPath = normalizedModelsPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !modelsPath.isEmpty {
            let trimmed = modelsPath.hasSuffix("/") ? String(modelsPath.dropLast()) : modelsPath
            candidates.append("\(trimmed)/\(encodedID)/load")
            candidates.append("\(trimmed)/load")
        } else if isOpenAI {
            candidates.append("/v1/models/\(encodedID)/load")
            candidates.append("/v1/models/load")
        } else if isOllama {
            candidates.append("/api/generate")
        }
        return Array(LinkedHashSet(candidates))
    }

    static func normalizedStatusReason(for statusCode: Int) -> String? {
        let localized = HTTPURLResponse.localizedString(forStatusCode: statusCode)
        let trimmed = localized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased() == "ok" {
            return "OK"
        }
        let words = trimmed.split(separator: " ").map { word -> String in
            word.split(separator: "-").map { segment in
                segment.capitalized
            }.joined(separator: "-")
        }
        return words.joined(separator: " ")
    }

    static func statusErrorDescription(for statusCode: Int, reason: String?) -> String {
        if let reason, !reason.isEmpty {
            return "Server responded with status code \(statusCode) (\(reason))."
        }
        return "Server responded with status code \(statusCode)."
    }

    private static func normalize(path: String, fallback: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return fallback }
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return trimmed
        }
        return trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
    }
}

struct RemoteModel: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var author: String
    var owner: String?
    var type: String?
    var publisher: String?
    var architecture: String?
    var compatibilityType: String?
    var quantization: String?
    var state: String?
    var maxContextLength: Int?
    var isCustom: Bool
    var families: [String]?
    var parameterSize: String?
    var fileSizeBytes: Int?
    var digest: String?
    var parentModel: String?
    var modifiedAt: Date?
    var modifiedAtRaw: String?

    init(id: String,
         name: String,
         author: String,
         owner: String? = nil,
         type: String? = nil,
         publisher: String? = nil,
         architecture: String? = nil,
         compatibilityType: String? = nil,
         quantization: String? = nil,
         state: String? = nil,
         maxContextLength: Int? = nil,
         isCustom: Bool = false,
         families: [String]? = nil,
         parameterSize: String? = nil,
         fileSizeBytes: Int? = nil,
         digest: String? = nil,
         parentModel: String? = nil,
         modifiedAt: Date? = nil,
         modifiedAtRaw: String? = nil) {
        self.id = id
        self.name = name
        self.author = author
        self.owner = owner
        self.type = type
        self.publisher = publisher
        self.architecture = architecture
        self.compatibilityType = compatibilityType
        self.quantization = quantization
        self.state = state
        self.maxContextLength = maxContextLength
        self.isCustom = isCustom
        self.families = families
        self.parameterSize = parameterSize
        self.fileSizeBytes = fileSizeBytes
        self.digest = digest
        self.parentModel = parentModel
        self.modifiedAt = modifiedAt
        self.modifiedAtRaw = modifiedAtRaw
    }

    static func make(from openAIModel: OpenAIModel) -> RemoteModel {
        let (name, author) = RemoteModel.parseNameAndAuthor(from: openAIModel.id, fallbackAuthor: openAIModel.ownedBy)
        return RemoteModel(
            id: openAIModel.id,
            name: name,
            author: author,
            owner: openAIModel.ownedBy,
            isCustom: false
        )
    }

    static func make(from lmStudioModel: LMStudioModel) -> RemoteModel {
        let (name, author) = RemoteModel.parseNameAndAuthor(from: lmStudioModel.id, fallbackAuthor: lmStudioModel.publisher)
        return RemoteModel(
            id: lmStudioModel.id,
            name: name,
            author: author,
            owner: lmStudioModel.publisher,
            type: lmStudioModel.type,
            publisher: lmStudioModel.publisher,
            architecture: lmStudioModel.arch,
            compatibilityType: lmStudioModel.compatibilityType,
            quantization: lmStudioModel.quantization,
            state: lmStudioModel.state,
            maxContextLength: lmStudioModel.maxContextLength,
            isCustom: false
        )
    }

    static func makeCustom(id: String) -> RemoteModel {
        let (name, author) = parseNameAndAuthor(from: id, fallbackAuthor: nil)
        return RemoteModel(id: id, name: name, author: author, owner: nil, isCustom: true)
    }

    static func make(from ollamaModel: OllamaTagsResponse.Model) -> RemoteModel {
        let identifier = ollamaModel.model.isEmpty ? ollamaModel.name : ollamaModel.model
        let (name, author) = parseNameAndAuthor(from: identifier, fallbackAuthor: nil)
        let format = ollamaModel.details?.format
        let compatibility = format?.isEmpty == false ? format : nil
        let architecture = ollamaModel.details?.family?.isEmpty == false ? ollamaModel.details?.family : nil
        let families = ollamaModel.details?.families?.isEmpty == false ? ollamaModel.details?.families : nil
        let quantization = ollamaModel.details?.quantizationLevel?.isEmpty == false ? ollamaModel.details?.quantizationLevel : nil
        let parameterSize = ollamaModel.details?.parameterSize?.isEmpty == false ? ollamaModel.details?.parameterSize : nil
        let parentModel = ollamaModel.details?.parentModel?.isEmpty == false ? ollamaModel.details?.parentModel : nil
        let modifiedAtDate = ollamaModel.modifiedAt.flatMap(RemoteModel.parseOllamaDate)
        return RemoteModel(
            id: identifier,
            name: name,
            author: author,
            owner: nil,
            type: "ollama",
            publisher: "Ollama",
            architecture: architecture,
            compatibilityType: compatibility,
            quantization: quantization,
            state: nil,
            maxContextLength: nil,
            isCustom: false,
            families: families,
            parameterSize: parameterSize,
            fileSizeBytes: ollamaModel.size,
            digest: ollamaModel.digest,
            parentModel: parentModel,
            modifiedAt: modifiedAtDate,
            modifiedAtRaw: ollamaModel.modifiedAt
        )
    }

    private static func parseNameAndAuthor(from identifier: String, fallbackAuthor: String?) -> (name: String, author: String) {
        let trimmedID = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fallback = fallbackAuthor, !fallback.isEmpty {
            return (trimmedID.components(separatedBy: "/").last ?? trimmedID, fallback)
        }
        if let slashIndex = trimmedID.lastIndex(of: "/") {
            let name = String(trimmedID[trimmedID.index(after: slashIndex)...])
            let author = String(trimmedID[..<slashIndex])
            return (name, author)
        }
        return (trimmedID, "Unknown")
    }
}

extension RemoteModel {
    var isEmbedding: Bool {
        let loweredID = id.lowercased()
        let loweredName = name.lowercased()
        if loweredID.contains("embedding") || loweredID.contains("embed") { return true }
        if loweredName.contains("embedding") || loweredName.contains("embed") { return true }
        if let type = type?.lowercased(), type.contains("embedding") { return true }
        return false
    }

    var compatibilityFormat: ModelFormat? {
        guard let compat = compatibilityType?.lowercased() else { return nil }
        switch compat {
        case "gguf":
            return .gguf
        case "mlx":
            return .mlx
        default:
            return nil
        }
    }

    var displayFamilies: [String] {
        var output: [String] = []
        if let architecture, !architecture.isEmpty {
            output.append(architecture)
        }
        if let families {
            for family in families where !family.isEmpty {
                if !output.contains(where: { $0.caseInsensitiveCompare(family) == .orderedSame }) {
                    output.append(family)
                }
            }
        }
        return output
    }

    var formattedParameterCount: String? {
        guard let parameterSize = parameterSize?.trimmingCharacters(in: .whitespacesAndNewlines), !parameterSize.isEmpty else {
            return nil
        }
        if parameterSize.lowercased().contains("param") {
            return parameterSize
        }
        return "\(parameterSize) params"
    }

    var formattedFileSize: String? {
        guard let fileSizeBytes, fileSizeBytes > 0 else { return nil }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(fileSizeBytes))
    }

    var modifiedAtRelativeDescription: String? {
        guard let modifiedAt else { return nil }
        return RemoteModel.makeRelativeDateFormatter().localizedString(for: modifiedAt, relativeTo: Date())
    }

    var modifiedAtDisplayString: String? {
        if let relative = modifiedAtRelativeDescription {
            return relative
        }
        if let modifiedAtRaw, !modifiedAtRaw.isEmpty {
            return modifiedAtRaw
        }
        return nil
    }

    static func parseOllamaDate(_ raw: String) -> Date? {
        let primaryFormatter = makeOllamaDateFormatter()
        let fallbackFormatter = makeOllamaFallbackDateFormatter()

        if let date = primaryFormatter.date(from: raw) {
            return date
        }
        if let trimmedSix = trimFractionalSeconds(in: raw, maxDigits: 6), let date = primaryFormatter.date(from: trimmedSix) {
            return date
        }
        if let trimmedThree = trimFractionalSeconds(in: raw, maxDigits: 3), let date = primaryFormatter.date(from: trimmedThree) {
            return date
        }
        if let trimmedNone = trimFractionalSeconds(in: raw, maxDigits: 0) {
            if let date = primaryFormatter.date(from: trimmedNone) {
                return date
            }
            return fallbackFormatter.date(from: trimmedNone)
        }
        return fallbackFormatter.date(from: raw)
    }

    private static func trimFractionalSeconds(in raw: String, maxDigits: Int) -> String? {
        guard let dotIndex = raw.firstIndex(of: ".") else { return nil }
        let fractionStart = raw.index(after: dotIndex)
        guard fractionStart < raw.endIndex else { return nil }
        let remainder = raw[fractionStart...]
        guard let zoneIndex = remainder.firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) else { return nil }
        let timezoneStart = zoneIndex
        let fraction = raw[fractionStart..<timezoneStart]
        if maxDigits == 0 {
            return String(raw[..<dotIndex]) + String(raw[timezoneStart...])
        }
        let limited = String(fraction.prefix(maxDigits))
        var padded = limited
        if padded.count < maxDigits {
            padded = padded.padding(toLength: maxDigits, withPad: "0", startingAt: 0)
        }
        return String(raw[..<dotIndex]) + "." + padded + String(raw[timezoneStart...])
    }

    private static func makeRelativeDateFormatter() -> RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }

    private static func makeOllamaDateFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func makeOllamaFallbackDateFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}

struct OpenAIModelsResponse: Decodable {
    let data: [OpenAIModel]
}

struct OpenAIModel: Decodable {
    let id: String
    let object: String
    let ownedBy: String?

    enum CodingKeys: String, CodingKey {
        case id
        case object
        case ownedBy = "owned_by"
    }
}

struct LMStudioModelsResponse: Decodable {
    let data: [LMStudioModel]
}

struct LMStudioModel: Decodable {
    let id: String
    let object: String?
    let type: String?
    let publisher: String?
    let arch: String?
    let compatibilityType: String?
    let quantization: String?
    let state: String?
    let maxContextLength: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case object
        case type
        case publisher
        case arch
        case compatibilityType
        case quantization
        case state
        case maxContextLength
    }
}

struct OllamaTagsResponse: Decodable {
    struct Model: Decodable {
        let name: String
        let model: String
        let modifiedAt: String?
        let size: Int?
        let digest: String?
        let details: Details?

        struct Details: Decodable {
            let parentModel: String?
            let format: String?
            let family: String?
            let families: [String]?
            let parameterSize: String?
            let quantizationLevel: String?
        }
    }

    let models: [Model]
}

enum RemoteBackendError: LocalizedError {
    case invalidBaseURL
    case invalidEndpoint
    case invalidResponse
    case unexpectedStatus(Int, String)
    case decodingFailed
    case validationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "The base URL looks invalid. Please include the host (e.g. http://127.0.0.1:1234)."
        case .invalidEndpoint:
            return "Could not build the remote endpoint URL."
        case .invalidResponse:
            return "The server returned an unexpected response."
        case .unexpectedStatus(let code, let body):
            if body.isEmpty {
                return "Server responded with status code \(code)."
            }
            return "Server responded with status code \(code): \(body)"
        case .decodingFailed:
            return "Failed to decode server response."
        case .validationFailed(let message):
            return message
        }
    }
}

enum RemoteBackendAPI {
    struct FetchModelsResult {
        let models: [RemoteModel]
        let statusCode: Int
        let reason: String?
    }

    static func fetchModels(for backend: RemoteBackend) async throws -> FetchModelsResult {
        guard let endpoint = backend.modelsEndpointURL else { throw RemoteBackendError.invalidEndpoint }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let auth = backend.authHeader, !auth.isEmpty {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        await logger.log("[RemoteBackendAPI] ⇢ Fetch models request for backend=\(backend.name) type=\(backend.endpointType.rawValue)\n\(describe(request: request))")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            if backend.endpointType == .ollama {
                if let urlError = error as? URLError {
                    let cannotReachHost: Bool
                    switch urlError.code {
                    case .cannotConnectToHost, .networkConnectionLost, .timedOut, .notConnectedToInternet:
                        cannotReachHost = true
                    default:
                        cannotReachHost = false
                    }
                    if cannotReachHost {
                        let advisory: String
                        if backend.usesLoopbackHost {
                            advisory = "Could not connect to Ollama at localhost. When connecting from another device, replace \"localhost\" with your computer's IP address or hostname and start Ollama with `OLLAMA_HOST=0.0.0.0` so it can accept remote connections."
                        } else {
                            advisory = "Could not connect to the Ollama server. Make sure Ollama is running on \(backend.displayBaseHost) and is configured to accept connections from this device (for example by launching it with `OLLAMA_HOST=0.0.0.0`)."
                        }
                        await logger.log("[RemoteBackendAPI] ❌ Ollama connection advisory: \(advisory)")
                        throw RemoteBackendError.validationFailed(advisory)
                    }
                }
            }
            await logger.log("[RemoteBackendAPI] ❌ Fetch models request failed: \(error.localizedDescription)")
            throw RemoteBackendError.validationFailed(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw RemoteBackendError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            await logger.log("[RemoteBackendAPI] ⚠️ Fetch models response status=\(http.statusCode)\nBody: \(body)")
            throw RemoteBackendError.unexpectedStatus(http.statusCode, body)
        }
        await logger.log("[RemoteBackendAPI] ⇠ Fetch models response status=\(http.statusCode) size=\(data.count)B\nBody: \(String(data: data, encoding: .utf8) ?? "<non-utf8>")")
        let statusCode = http.statusCode
        let reason = RemoteBackend.normalizedStatusReason(for: statusCode)
        switch backend.endpointType {
        case .lmStudio:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            guard let response = try? decoder.decode(LMStudioModelsResponse.self, from: data) else {
                await logger.log("[RemoteBackendAPI] ❌ Failed to decode LM Studio models response")
                throw RemoteBackendError.decodingFailed
            }
            let models = response.data
                .map(RemoteModel.make)
                .filter { !$0.isEmbedding }
            await logger.log("[RemoteBackendAPI] ✅ Decoded \(models.count) LM Studio models")
            return FetchModelsResult(models: models, statusCode: statusCode, reason: reason)
        case .ollama:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            guard let response = try? decoder.decode(OllamaTagsResponse.self, from: data) else {
                await logger.log("[RemoteBackendAPI] ❌ Failed to decode Ollama tags response")
                throw RemoteBackendError.decodingFailed
            }
            let models = response.models
                .map(RemoteModel.make)
                .filter { !$0.isEmbedding }
            await logger.log("[RemoteBackendAPI] ✅ Decoded \(models.count) Ollama models")
            return FetchModelsResult(models: models, statusCode: statusCode, reason: reason)
        case .openAI:
            let decoder = JSONDecoder()
            guard let response = try? decoder.decode(OpenAIModelsResponse.self, from: data) else {
                await logger.log("[RemoteBackendAPI] ❌ Failed to decode OpenAI models response")
                throw RemoteBackendError.decodingFailed
            }
            let models = response.data
                .map(RemoteModel.make)
                .filter { !$0.isEmbedding }
            await logger.log("[RemoteBackendAPI] ✅ Decoded \(models.count) OpenAI models")
            return FetchModelsResult(models: models, statusCode: statusCode, reason: reason)
        }
    }

    static func requestLoad(for backend: RemoteBackend, modelID: String) async throws {
        if backend.endpointType == .ollama {
            try await requestOllamaLoad(for: backend, modelID: modelID)
            return
        }

        let candidates = backend.loadPathCandidates(for: modelID)
        var lastError: Error = RemoteBackendError.invalidEndpoint
        for path in candidates {
            guard let url = backend.absoluteURL(for: path) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 30
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let auth = backend.authHeader, !auth.isEmpty {
                request.setValue(auth, forHTTPHeaderField: "Authorization")
            }
            let payload: [String: String] = ["model": modelID]
            request.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [])
            await logger.log("[RemoteBackendAPI] ⇢ Requesting load for model=\(modelID) backend=\(backend.name) path=\(path)\n\(describe(request: request))")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw RemoteBackendError.invalidResponse }
                guard (200...299).contains(http.statusCode) else {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    await logger.log("[RemoteBackendAPI] ⚠️ Load request failed status=\(http.statusCode) path=\(path)\nBody: \(body)")
                    lastError = RemoteBackendError.unexpectedStatus(http.statusCode, body)
                    continue
                }
                await logger.log("[RemoteBackendAPI] ⇠ Load request succeeded status=\(http.statusCode) path=\(path)")
                return
            } catch {
                await logger.log("[RemoteBackendAPI] ❌ Load request error path=\(path): \(error.localizedDescription)")
                lastError = error
                continue
            }
        }
        if let backendError = lastError as? RemoteBackendError {
            throw backendError
        } else {
            throw RemoteBackendError.validationFailed(lastError.localizedDescription)
        }
    }

    private static func requestOllamaLoad(for backend: RemoteBackend, modelID: String) async throws {
        guard let url = backend.absoluteURL(for: "/api/generate") else {
            throw RemoteBackendError.invalidEndpoint
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let auth = backend.authHeader, !auth.isEmpty {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        let payload: [String: Any] = [
            "model": modelID,
            "prompt": "",
            "stream": false,
            "keep_alive": "5m"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        await logger.log("[RemoteBackendAPI] ⇢ Requesting Ollama load for model=\(modelID) backend=\(backend.name)\n\(describe(request: request))")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RemoteBackendError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            await logger.log("[RemoteBackendAPI] ⚠️ Ollama load failed status=\(http.statusCode)\nBody: \(body)")
            throw RemoteBackendError.unexpectedStatus(http.statusCode, body)
        }
        await logger.log("[RemoteBackendAPI] ⇠ Ollama load succeeded status=\(http.statusCode)")
    }

    private static func describe(request: URLRequest) -> String {
        let method = request.httpMethod ?? "<unknown>"
        let urlString = request.url?.absoluteString ?? "<no url>"
        let headers = sanitizedHeaders(from: request.allHTTPHeaderFields)
        let headerLines = headers.map { "\($0): \($1)" }.sorted().joined(separator: "\n")
        let body: String
        if let data = request.httpBody, !data.isEmpty {
            body = String(data: data, encoding: .utf8) ?? "<binary body size=\(data.count)>"
        } else {
            body = "<empty>"
        }
        return "\(method) \(urlString)\nHeaders:\n\(headerLines.isEmpty ? "<none>" : headerLines)\nBody:\n\(body)"
    }

    private static func sanitizedHeaders(from headers: [String: String]?) -> [String: String] {
        guard let headers else { return [:] }
        var sanitized: [String: String] = [:]
        for (key, value) in headers {
            if key.caseInsensitiveCompare("Authorization") == .orderedSame {
                sanitized[key] = "<redacted>"
            } else {
                sanitized[key] = value
            }
        }
        return sanitized
    }
}

enum RemoteBackendsStore {
    private static let storageKey = "remoteBackends.v1"

    static func load() -> [RemoteBackend] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([RemoteBackend].self, from: data) {
            return decoded
        }
        return []
    }

    static func save(_ backends: [RemoteBackend]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(backends) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

struct RemoteBackendDraft {
    var name: String = ""
    var baseURL: String = ""
    var endpointType: RemoteBackend.EndpointType = .openAI
    var chatPath: String
    var modelsPath: String
    var authHeader: String = ""
    var customModelIDs: [String] = [""]

    init() {
        chatPath = endpointType.defaultChatPath
        modelsPath = endpointType.defaultModelsPath
    }

    init(from backend: RemoteBackend) {
        name = backend.name
        baseURL = backend.baseURLString
        chatPath = backend.chatPath
        modelsPath = backend.modelsPath
        authHeader = backend.authHeader ?? ""
        customModelIDs = backend.customModelIDs.isEmpty ? [""] : backend.customModelIDs
        endpointType = backend.endpointType
    }

    func validatedBaseURL() -> URL? {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains("://") {
            trimmed = "http://" + trimmed
        }
        if trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        guard let url = URL(string: trimmed), url.host != nil else { return nil }
        return url
    }

    var usesLoopbackHost: Bool {
        guard let host = validatedBaseURL()?.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}

extension RemoteBackendDraft {
    var sanitizedCustomModelIDs: [String] {
        RemoteBackend.normalize(customModelIDs)
    }

    mutating func appendCustomModelSlot() {
        customModelIDs.append("")
    }

    mutating func removeCustomModel(at index: Int) {
        guard customModelIDs.indices.contains(index) else { return }
        customModelIDs.remove(at: index)
        if customModelIDs.isEmpty {
            customModelIDs = [""]
        }
    }
}

extension RemoteBackend {
    func updating(from draft: RemoteBackendDraft) throws -> RemoteBackend {
        var updated = try RemoteBackend(from: draft)
        updated.id = id
        updated.cachedModels = cachedModels
        updated.lastFetched = lastFetched
        updated.lastError = lastError
        updated.lastConnectionSummary = lastConnectionSummary
        return updated
    }
}

struct ActiveRemoteSession: Equatable {
    let backendID: RemoteBackend.ID
    let backendName: String
    let modelID: String
    let modelName: String
    let endpointType: RemoteBackend.EndpointType
}

private struct LinkedHashSet<Element: Hashable>: Sequence {
    private var ordered: [Element] = []
    private var seen: Set<Element> = []

    init(_ elements: [Element]) {
        for element in elements {
            if !seen.contains(element) {
                seen.insert(element)
                ordered.append(element)
            }
        }
    }

    func makeIterator() -> IndexingIterator<[Element]> {
        ordered.makeIterator()
    }

    var array: [Element] { ordered }
}

private extension Array where Element: Hashable {
    init(_ set: LinkedHashSet<Element>) {
        self = set.array
    }
}

private extension CharacterSet {
    static let remoteModelIDAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-_.@")
        return set
    }()
}
