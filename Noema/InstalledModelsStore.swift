// InstalledModelsStore.swift
import Foundation

struct InstalledModel: Identifiable, Codable {
    let id: UUID
    let modelID: String
    let quantLabel: String
    let url: URL
    let format: ModelFormat
    let sizeBytes: Int64
    var lastUsed: Date?
    var installDate: Date
    let checksum: String?
    var isFavourite: Bool = false
    var totalLayers: Int = 0
    var isMultimodal: Bool = false
    var isToolCapable: Bool = false

    init(id: UUID = UUID(), modelID: String, quantLabel: String, url: URL, format: ModelFormat, sizeBytes: Int64, lastUsed: Date?, installDate: Date, checksum: String?, isFavourite: Bool, totalLayers: Int, isMultimodal: Bool = false, isToolCapable: Bool = false) {
        self.id = id
        self.modelID = modelID
        self.quantLabel = quantLabel
        self.url = url
        self.format = format
        self.sizeBytes = sizeBytes
        self.lastUsed = lastUsed
        self.installDate = installDate
        self.checksum = checksum
        self.isFavourite = isFavourite
        self.totalLayers = totalLayers
        self.isMultimodal = isMultimodal
        self.isToolCapable = isToolCapable
    }
}

extension InstalledModel {
    /// Human-friendly name for display in logs/UI.
    var displayName: String {
        if !modelID.isEmpty {
            return quantLabel.isEmpty ? modelID : "\(modelID) (\(quantLabel))"
        }
        return url.deletingPathExtension().lastPathComponent
    }
}

final class InstalledModelsStore {
    private var items: [InstalledModel] = []
    private let url: URL
    private let queue = DispatchQueue(label: "store")

    init(filename: String = "installed.json") {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = docs.appendingPathComponent(filename)
        reload()
    }

    func isInstalled(id: String, quantLabel: String) -> Bool {
        items.contains { $0.modelID == id && $0.quantLabel == quantLabel }
    }

    func all() -> [InstalledModel] { items }

    func add(_ m: InstalledModel) {
        queue.sync {
            let url = Self.canonicalURL(for: m.url, format: m.format)
            let newModel = InstalledModel(id: m.id,
                                          modelID: m.modelID,
                                          quantLabel: m.quantLabel,
                                          url: url,
                                          format: m.format,
                                          sizeBytes: m.sizeBytes,
                                          lastUsed: m.lastUsed,
                                          installDate: m.installDate,
                                          checksum: m.checksum,
                                          isFavourite: m.isFavourite,
                                          totalLayers: m.totalLayers,
                                          isMultimodal: m.isMultimodal,
                                          isToolCapable: m.isToolCapable)
            self.items.append(newModel)
            self.save()
        }
    }

    func updateLastUsed(modelID: String, quantLabel: String, date: Date) {
        queue.sync {
            if let idx = self.items.firstIndex(where: { $0.modelID == modelID && $0.quantLabel == quantLabel }) {
                self.items[idx].lastUsed = date
                self.save()
            }
        }
    }

    func remove(modelID: String, quantLabel: String) {
        queue.sync {
            self.items.removeAll { $0.modelID == modelID && $0.quantLabel == quantLabel }
            self.save()
        }
    }

    func updateFavorite(modelID: String, quantLabel: String, fav: Bool) {
        queue.sync {
            if let idx = self.items.firstIndex(where: { $0.modelID == modelID && $0.quantLabel == quantLabel }) {
                self.items[idx].isFavourite = fav
                self.save()
            }
        }
    }

    func updateLayers(modelID: String, quantLabel: String, layers: Int) {
        queue.sync {
            if let index = items.firstIndex(where: { $0.modelID == modelID && $0.quantLabel == quantLabel }) {
                items[index].totalLayers = layers
                save()
            }
        }
    }

    func updateCapabilities(modelID: String, quantLabel: String, isMultimodal: Bool, isToolCapable: Bool) {
        queue.sync {
            if let index = items.firstIndex(where: { $0.modelID == modelID && $0.quantLabel == quantLabel }) {
                items[index].isMultimodal = isMultimodal
                items[index].isToolCapable = isToolCapable
                save()
            }
        }
    }

    func reload() {
        guard let data = try? Data(contentsOf: url) else { return }
        if let decoded = try? JSONDecoder().decode([InstalledModel].self, from: data) {
            items = decoded
            _ = migratePaths()
        }
    }

    private func save() {
        let data = try? JSONEncoder().encode(items)
        try? data?.write(to: url)
    }

    var totalSizeBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }

    /// Migrates any legacy SLM records so the stored URL points at the bundle root
    /// under Application Support/Models/<slug>.bundle. Returns whether changes were made.
    @discardableResult
    func migrateLeapBundles() -> Bool {
        var changed = false
        queue.sync {
            let base = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Models", isDirectory: true)
            for idx in items.indices {
                guard items[idx].format == .slm else { continue }
                let current = items[idx].url
                let cfg = current.appendingPathComponent("config.yaml")
                if current.pathExtension != "bundle" ||
                    !FileManager.default.fileExists(atPath: cfg.path) {
                    let canonical = base.appendingPathComponent(items[idx].modelID + ".bundle")
                    let it = items[idx]
                    items[idx] = InstalledModel(id: it.id,
                                               modelID: it.modelID,
                                               quantLabel: it.quantLabel,
                                               url: canonical,
                                               format: .slm,
                                               sizeBytes: it.sizeBytes,
                                               lastUsed: it.lastUsed,
                                               installDate: it.installDate,
                                               checksum: it.checksum,
                                               isFavourite: it.isFavourite,
                                               totalLayers: it.totalLayers,
                                               isMultimodal: it.isMultimodal,
                                               isToolCapable: it.isToolCapable)
                    changed = true
                }
            }
            if changed { save() }
        }
        return changed
    }

    /// Migrates GGUF and MLX records to ensure URLs use the canonical shape.
    /// GGUF entries store the `.gguf` file path; MLX entries store the root
    /// directory containing model files.
    @discardableResult
    func migratePaths() -> Bool {
        var changed = false
        queue.sync {
            for idx in items.indices {
                let item = items[idx]
                let canonical = Self.canonicalURL(for: item.url, format: item.format)
                if canonical != item.url {
                    let oldURL = item.url
                    items[idx] = InstalledModel(id: item.id,
                                               modelID: item.modelID,
                                               quantLabel: item.quantLabel,
                                               url: canonical,
                                               format: item.format,
                                               sizeBytes: item.sizeBytes,
                                               lastUsed: item.lastUsed,
                                               installDate: item.installDate,
                                               checksum: item.checksum,
                                               isFavourite: item.isFavourite,
                                               totalLayers: item.totalLayers,
                                               isMultimodal: item.isMultimodal,
                                               isToolCapable: item.isToolCapable)
                    // Keep default model selection stable if path changed.
                    let defaults = UserDefaults.standard
                    if let current = defaults.string(forKey: "defaultModelPath"), !current.isEmpty,
                       current == oldURL.path {
                        defaults.set(canonical.path, forKey: "defaultModelPath")
                    }
                    // Migrate any saved per-model settings under old path key.
                    if let data = defaults.data(forKey: "modelSettings"),
                       var dict = try? JSONDecoder().decode([String: ModelSettings].self, from: data),
                       let val = dict.removeValue(forKey: oldURL.path) {
                        dict[canonical.path] = val
                        if let newData = try? JSONEncoder().encode(dict) {
                            defaults.set(newData, forKey: "modelSettings")
                        }
                    }
                    changed = true
                }
            }
            if changed { save() }
        }
        return changed
    }

    private static func splitModelID(_ modelID: String) -> (owner: String?, repo: String) {
        guard let slash = modelID.firstIndex(of: "/") else {
            return (nil, modelID)
        }
        let owner = String(modelID[..<slash])
        let repo = String(modelID[modelID.index(after: slash)...])
        return (owner.isEmpty ? nil : owner, repo)
    }

    private static func sanitizedRepoComponent(for format: ModelFormat, repo: String) -> String {
        switch format {
        case .mlx:
            let trimmed = repo.replacingOccurrences(of: #"(?i)([-_]?gguf)$"#, with: "", options: .regularExpression)
            let cleaned = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "-_ "))
            return cleaned.isEmpty ? repo : cleaned
        default:
            return repo
        }
    }

    static func normalizedRepoName(for format: ModelFormat, modelID: String) -> String {
        let (_, repo) = splitModelID(modelID)
        return sanitizedRepoComponent(for: format, repo: repo)
    }

    static func canonicalURL(for url: URL, format: ModelFormat) -> URL {
        let fixed = url.resolvingSymlinksInPath().standardizedFileURL
        switch format {
        case .gguf:
            if fixed.pathExtension.lowercased() == "gguf" { return fixed }
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: fixed.path, isDirectory: &isDir), isDir.boolValue,
               let found = firstGGUF(in: fixed) {
                return found.resolvingSymlinksInPath().standardizedFileURL
            }
            return fixed
        case .mlx:
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: fixed.path, isDirectory: &isDir) {
                return (isDir.boolValue ? fixed : fixed.deletingLastPathComponent()).resolvingSymlinksInPath().standardizedFileURL
            }
            return fixed
        case .slm:
            return fixed
        case .apple:
            return fixed
        }
    }

    /// Base directory used for storing models of the given format and id.
    static func baseDir(for format: ModelFormat, modelID: String) -> URL {
        switch format {
        case .slm:
            return FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Models", isDirectory: true)
        case .gguf, .mlx, .apple:
            var dir = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("LocalLLMModels", isDirectory: true)
            let parts = splitModelID(modelID)
            if let owner = parts.owner, !owner.isEmpty {
                dir.appendPathComponent(owner, isDirectory: true)
            }
            let repoComponent = sanitizedRepoComponent(for: format, repo: parts.repo)
            dir.appendPathComponent(repoComponent, isDirectory: true)
            return dir
        }
    }

    /// Attempts to repair missing paths by recomputing them under the current sandbox.
    @discardableResult
    func rehomeIfMissing() -> Bool {
        var changed = false
        queue.sync {
            for idx in items.indices {
                let item = items[idx]
                guard !FileManager.default.fileExists(atPath: item.url.path) else { continue }
                let base = Self.baseDir(for: item.format, modelID: item.modelID)
                let repaired: URL?
                switch item.format {
                case .gguf:
                    repaired = Self.firstGGUF(in: base)
                case .mlx:
                    var isDir: ObjCBool = false
                    let exists = FileManager.default.fileExists(atPath: base.path, isDirectory: &isDir)
                    repaired = (exists && isDir.boolValue) ? base : nil
                case .slm:
                    let u = FileManager.default
                        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("Models", isDirectory: true)
                        .appendingPathComponent(item.modelID + ".bundle")
                    var d: ObjCBool = false
                    let exists = FileManager.default.fileExists(atPath: u.path, isDirectory: &d)
                    repaired = (exists && d.boolValue) ? u : nil
                case .apple:
                    repaired = nil
                }
                if let newURL = repaired {
                    let oldURL = item.url
                    items[idx] = InstalledModel(id: item.id,
                                               modelID: item.modelID,
                                               quantLabel: item.quantLabel,
                                               url: newURL,
                                               format: item.format,
                                               sizeBytes: item.sizeBytes,
                                               lastUsed: item.lastUsed,
                                               installDate: item.installDate,
                                               checksum: item.checksum,
                                               isFavourite: item.isFavourite,
                                               totalLayers: item.totalLayers,
                                               isMultimodal: item.isMultimodal,
                                               isToolCapable: item.isToolCapable)
                    // Preserve default model path across re-homing.
                    let defaults = UserDefaults.standard
                    if let current = defaults.string(forKey: "defaultModelPath"), !current.isEmpty,
                       current == oldURL.path {
                        defaults.set(newURL.path, forKey: "defaultModelPath")
                    }
                    // Migrate any saved per-model settings under old path key.
                    if let data = defaults.data(forKey: "modelSettings"),
                       var dict = try? JSONDecoder().decode([String: ModelSettings].self, from: data),
                       let val = dict.removeValue(forKey: oldURL.path) {
                        dict[newURL.path] = val
                        if let newData = try? JSONEncoder().encode(dict) {
                            defaults.set(newData, forKey: "modelSettings")
                        }
                    }
                    changed = true
                }
            }
            if changed { save() }
        }
        return changed
    }

    /// Returns true if the given URL is a readable GGUF file (magic == "GGUF").
    static func isValidGGUF(at url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "gguf" else { return false }
        guard let fh = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? fh.close() }
        let magic = try? fh.read(upToCount: 4)
        return magic == Data("GGUF".utf8)
    }

    static func firstGGUF(in dir: URL) -> URL? {
        // Collect all .gguf files in the directory and one level of subdirectories
        var candidates: [URL] = []
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            candidates.append(contentsOf: files.filter { $0.pathExtension.lowercased() == "gguf" })
            for sub in files {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: sub.path, isDirectory: &isDir), isDir.boolValue,
                   let subfiles = try? FileManager.default.contentsOfDirectory(at: sub, includingPropertiesForKeys: nil) {
                    candidates.append(contentsOf: subfiles.filter { $0.pathExtension.lowercased() == "gguf" })
                }
            }
        }
        if candidates.isEmpty { return nil }
        // Prefer non-mmproj/projector files and validate GGUF magic; choose the largest by size
        func isMMProj(_ u: URL) -> Bool {
            let name = u.lastPathComponent.lowercased()
            return name.contains("mmproj") || name.contains("projector") || name.contains("image_proj")
        }
        func fileSize(_ u: URL) -> Int64 {
            (try? FileManager.default.attributesOfItem(atPath: u.path)[.size] as? Int64) ?? 0
        }
        let valid = candidates.filter { isValidGGUF(at: $0) }
        let weights = valid.filter { !isMMProj($0) }
        if let best = weights.sorted(by: { fileSize($0) > fileSize($1) }).first {
            return best
        }
        // If only mmproj files exist, do not return them as model weights.
        return nil
    }
}
