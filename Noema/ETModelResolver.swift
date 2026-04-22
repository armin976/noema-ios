import Foundation

enum ETModelResolver {
    static func pteURL(for url: URL) -> URL? {
        let fixed = url.resolvingSymlinksInPath().standardizedFileURL
        if fixed.pathExtension.lowercased() == "pte" {
            return fixed
        }
        return firstMatchingFile(in: fixed, extensions: ["pte"])
    }

    static func tokenizerURL(for url: URL) -> URL? {
        let fixed = url.resolvingSymlinksInPath().standardizedFileURL
        if fixed.lastPathComponent.lowercased() == "tokenizer.json" {
            return fixed
        }
        return firstMatchingFile(
            in: fixed,
            names: [
                "tokenizer.json",
                "tokenizer.model",
                "spiece.model",
                "sentencepiece.bpe.model"
            ]
        )
    }

    static func tokenizerConfigURL(for url: URL) -> URL? {
        let fixed = url.resolvingSymlinksInPath().standardizedFileURL
        if fixed.lastPathComponent.lowercased() == "tokenizer_config.json" {
            return fixed
        }
        return firstMatchingFile(in: fixed, names: ["tokenizer_config.json"])
    }

    static func hasPTEArtifact(at url: URL) -> Bool {
        pteURL(for: url) != nil
    }

    private static func firstMatchingFile(in root: URL, names: [String] = [], extensions: [String] = []) -> URL? {
        let fm = FileManager.default
        let nameSet = Set(names.map { $0.lowercased() })
        let extSet = Set(extensions.map { $0.lowercased() })

        func matches(_ file: URL) -> Bool {
            let fileName = file.lastPathComponent.lowercased()
            if !nameSet.isEmpty, nameSet.contains(fileName) { return true }
            if !extSet.isEmpty, extSet.contains(file.pathExtension.lowercased()) { return true }
            return false
        }

        var isDir: ObjCBool = false
        if fm.fileExists(atPath: root.path, isDirectory: &isDir), !isDir.boolValue {
            return matches(root) ? root : nil
        }

        guard let files = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return nil
        }

        if let direct = files.first(where: { matches($0) }) {
            return direct
        }

        for entry in files {
            var subIsDir: ObjCBool = false
            guard fm.fileExists(atPath: entry.path, isDirectory: &subIsDir), subIsDir.boolValue else { continue }
            guard let subFiles = try? fm.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil) else { continue }
            if let subMatch = subFiles.first(where: { matches($0) }) {
                return subMatch
            }
        }

        return nil
    }
}
