// ToolCallView.swift
import SwiftUI

struct ToolCallView: View {
    let toolCall: ChatVM.Msg.ToolCall
    @State private var showingDetails = false
    
    var body: some View {
        Button(action: { showingDetails = true }) {
            VStack(alignment: .leading, spacing: 8) {
                // Header similar to RollingThoughtBox
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: toolCall.iconName)
                            .font(.caption)
                            .foregroundStyle(iconColor)
                        Text(toolCall.displayName)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray6))
                    .clipShape(Capsule())
                    
                    Spacer()
                    
                    if toolCall.error != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if toolCall.result != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }
                
                // Show key parameters inline
                if !toolCall.requestParams.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(toolCall.requestParams.keys.sorted().prefix(2)), id: \.self) { key in
                            HStack(spacing: 4) {
                                Text("\(key):")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(String(describing: toolCall.requestParams[key]?.value ?? "").prefix(50))
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                        if toolCall.requestParams.count > 2 {
                            Text("... and \(toolCall.requestParams.count - 2) more")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .italic()
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            .padding(12)
            .background(Color(.systemGray6).opacity(toolCall.result != nil ? 0.5 : 1.0))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingDetails) {
            ToolCallDetailSheet(toolCall: toolCall)
        }
    }
    
    private var iconColor: Color {
        if toolCall.error != nil {
            return .orange
        } else if toolCall.result != nil {
            return .green
        } else {
            return .blue
        }
    }
    
    private var backgroundColor: Color {
        Color(.systemGray6)
    }
    
    private var borderColor: Color {
        if toolCall.error != nil {
            return .orange.opacity(0.3)
        } else if toolCall.result != nil {
            return .green.opacity(0.3)
        } else {
            return .gray.opacity(0.3)
        }
    }
}

struct ToolCallDetailSheet: View {
    let toolCall: ChatVM.Msg.ToolCall
    @Environment(\.dismiss) private var dismiss
    @State private var resultDisplayMode: ResultDisplayMode = .formatted

    init(toolCall: ChatVM.Msg.ToolCall) {
        self.toolCall = toolCall
        let defaultMode: ResultDisplayMode
        if let result = toolCall.result,
           !Self.parseWebResults(from: result).isEmpty {
            defaultMode = .formatted
        } else {
            defaultMode = .raw
        }
        _resultDisplayMode = State(initialValue: defaultMode)
    }

    private enum ResultDisplayMode: String, CaseIterable, Hashable {
        case formatted
        case raw

        var title: String {
            rawValue.capitalized
        }
    }

    private struct WebSearchResultItem {
        let title: String
        let url: String
        let snippet: String
        let engine: String?
        let score: String?

        init?(dictionary: [String: Any]) {
            let rawTitle = (dictionary["title"] as? String) ?? (dictionary["name"] as? String) ?? ""
            let rawURL = (dictionary["url"] as? String) ?? (dictionary["link"] as? String) ?? ""
            let rawSnippet = (dictionary["snippet"] as? String)
                ?? (dictionary["summary"] as? String)
                ?? (dictionary["description"] as? String)
                ?? ""
            let normalizedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedSnippet = rawSnippet.trimmingCharacters(in: .whitespacesAndNewlines)

            if normalizedTitle.isEmpty && normalizedURL.isEmpty && normalizedSnippet.isEmpty {
                return nil
            }

            title = normalizedTitle
            url = normalizedURL
            snippet = normalizedSnippet
            engine = (dictionary["engine"] as? String) ?? (dictionary["source"] as? String)

            if let s = dictionary["score"] as? String {
                score = s
            } else if let n = dictionary["score"] as? NSNumber {
                score = n.stringValue
            } else if let b = dictionary["score"] as? Bool {
                score = b ? "true" : "false"
            } else if let s = dictionary["rank"] as? String {
                score = s
            } else if let n = dictionary["rank"] as? NSNumber {
                score = n.stringValue
            } else if let b = dictionary["rank"] as? Bool {
                score = b ? "true" : "false"
            } else {
                score = nil
            }
        }

        var displayTitle: String {
            title.isEmpty ? url : title
        }
    }
    
    private static func string(from value: Any) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        if let bool = value as? Bool { return bool ? "true" : "false" }
        return nil
    }

    private static func parseWebResults(from result: String) -> [WebSearchResultItem] {
        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }

        var rawItems: [[String: Any]] = []

        if let array = json as? [[String: Any]] {
            rawItems = array
        } else if let dict = json as? [String: Any] {
            let candidateKeys = ["results", "items", "data", "hits", "entries"]
            for key in candidateKeys {
                if let arr = dict[key] as? [[String: Any]] {
                    rawItems = arr
                    break
                }
            }
            if rawItems.isEmpty, let arr = dict["result"] as? [[String: Any]] {
                rawItems = arr
            }
        }

        return rawItems.compactMap { WebSearchResultItem(dictionary: $0) }
    }

    private struct ResultBoxStyle: ViewModifier {
        func body(content: Content) -> some View {
            content
                .frame(maxHeight: 300)
                .padding()
                .background(Color.green.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.green.opacity(0.2), lineWidth: 1)
                )
                .cornerRadius(8)
        }
    }

    private func formatResult(_ result: String) -> String {
        // Try to pretty-print JSON
        if let data = result.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            return prettyString
        }
        return result
    }

    private func rawResultView(for result: String) -> some View {
        ScrollView {
            Text(formatResult(result))
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .modifier(ResultBoxStyle())
    }

    @ViewBuilder
    private func formattedResultView(for result: String) -> some View {
        let hits = Self.parseWebResults(from: result)
        if hits.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Formatted view unavailable")
                    .font(.subheadline.weight(.semibold))
                Text("The tool returned data that can't be formatted. Switch to Raw to inspect the original response.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(ResultBoxStyle())
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(hits.enumerated()), id: \.offset) { index, item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(index + 1).")
                                    .font(.headline.weight(.semibold))
                                Text(item.displayTitle.isEmpty ? "Untitled Result" : item.displayTitle)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.leading)
                            }

                            if !item.snippet.isEmpty {
                                Text(item.snippet.strippingHTMLTags())
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            if !item.url.isEmpty {
                                if let destination = URL(string: item.url) ?? URL(string: "https://" + item.url) {
                                    Link(item.url, destination: destination)
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                        .lineLimit(2)
                                } else {
                                    Text(item.url)
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                        .lineLimit(2)
                                        .textSelection(.enabled)
                                }
                            }

                            if item.engine != nil {
                                HStack(spacing: 6) {
                                    if let engine = item.engine, !engine.isEmpty {
                                        Text(engine)
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color(.systemGray6))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.green.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            .modifier(ResultBoxStyle())
        }
    }
    
    private func formatParameterValue(_ value: Any?) -> String {
        guard let value = value else { return "null" }
        
        // Handle different types appropriately
        if let string = value as? String {
            return string
        } else if let dict = value as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
                  let prettyString = String(data: data, encoding: .utf8) {
            return prettyString
        } else if let array = value as? [Any],
                  let data = try? JSONSerialization.data(withJSONObject: array, options: .prettyPrinted),
                  let prettyString = String(data: data, encoding: .utf8) {
            return prettyString
        }
        
        return String(describing: value)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    HStack(spacing: 12) {
                        Image(systemName: toolCall.iconName)
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.blue)
                            .frame(width: 40, height: 40)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(toolCall.displayName)
                                .font(.headline)
                            Text(toolCall.toolName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(toolCall.timestamp, style: .time)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    // Request Parameters
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Request Parameters")
                            .font(.headline)
                        
                        if toolCall.requestParams.isEmpty {
                            Text("No parameters")
                                .foregroundColor(.secondary)
                                .italic()
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(toolCall.requestParams.keys.sorted()), id: \.self) { key in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(key)
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(.secondary)
                                        
                                        Text(formatParameterValue(toolCall.requestParams[key]?.value))
                                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(8)
                                            .background(Color(.systemGray6))
                                            .cornerRadius(6)
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color(.systemGray4), lineWidth: 1)
                    )
                    .cornerRadius(8)
                    
                    // Result or Error
                    if let error = toolCall.error {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Error")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                            }
                            
                            Text(error)
                                .font(.caption)
                                .textSelection(.enabled)
                                .padding()
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(8)
                        }
                    } else if let result = toolCall.result {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Result")
                                        .font(.headline)
                                        .foregroundColor(.green)
                                }

                                Spacer()

                                Picker("Result format", selection: $resultDisplayMode) {
                                    ForEach(ResultDisplayMode.allCases, id: \.self) { mode in
                                        Text(mode.title).tag(mode)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                                .frame(maxWidth: 180)
                            }

                            Group {
                                if resultDisplayMode == .formatted {
                                    formattedResultView(for: result)
                                } else {
                                    rawResultView(for: result)
                                }
                            }
                            .animation(.none, value: resultDisplayMode)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "clock.fill")
                                    .foregroundColor(.blue)
                                Text("Status")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                            }
                            
                            Text("In progress...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .italic()
                        }
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding()
            }
            .navigationTitle("Tool Call Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onChange(of: toolCall.result) { _, newValue in
                guard let newValue else { return }
                if resultDisplayMode == .formatted,
                   Self.parseWebResults(from: newValue).isEmpty {
                    resultDisplayMode = .raw
                }
            }
        }
    }
}

private enum HTMLStripper {
    static let newlineRegex = try? NSRegularExpression(
        pattern: "<\\s*(br|/?p)\\b[^>]*>",
        options: [.caseInsensitive]
    )
    static let tagRegex = try? NSRegularExpression(
        pattern: "<[^>]+>",
        options: [.caseInsensitive]
    )
}

fileprivate extension String {
    func strippingHTMLTags() -> String {
        guard !isEmpty else { return self }

        var working = self

        if let newlineRegex = HTMLStripper.newlineRegex {
            let range = NSRange(location: 0, length: working.utf16.count)
            working = newlineRegex.stringByReplacingMatches(
                in: working,
                options: [],
                range: range,
                withTemplate: "\n"
            )
        }

        if let tagRegex = HTMLStripper.tagRegex {
            let range = NSRange(location: 0, length: working.utf16.count)
            working = tagRegex.stringByReplacingMatches(
                in: working,
                options: [],
                range: range,
                withTemplate: ""
            )
        }

        working = working.replacingOccurrences(
            of: "\n{3,}",
            with: "\n\n",
            options: .regularExpression
        )

        working = working.replacingOccurrences(
            of: " {2,}",
            with: " ",
            options: .regularExpression
        )

        working = working.decodingHTMLEntities()
        working = working.replacingOccurrences(of: "\u{00A0}", with: " ")

        return working.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decodingHTMLEntities() -> String {
        // Handle common named entities first
        var decoded = self
        let namedEntities: [String: String] = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&nbsp;": "\u{00A0}"
        ]

        for (entity, replacement) in namedEntities {
            decoded = decoded.replacingOccurrences(of: entity, with: replacement)
        }

        // Decode numeric entities: decimal (e.g., &#169;) and hex (e.g., &#xA9;)
        func replacingMatches(pattern: String, transformer: (NSTextCheckingResult, String) -> String) -> String {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return decoded }
            let nsString = decoded as NSString
            let matches = regex.matches(in: decoded, options: [], range: NSRange(location: 0, length: nsString.length))
            var result = decoded
            // Replace from the end to keep ranges valid
            for match in matches.reversed() {
                let replacement = transformer(match, decoded)
                let range = match.range
                let startIndex = result.index(result.startIndex, offsetBy: range.location)
                let endIndex = result.index(startIndex, offsetBy: range.length)
                result.replaceSubrange(startIndex..<endIndex, with: replacement)
            }
            return result
        }

        // Decimal entities
        decoded = replacingMatches(pattern: "&#(\\d+);") { match, source in
            let nsSource = source as NSString
            let numberRange = match.range(at: 1)
            let numberString = nsSource.substring(with: numberRange)
            if let codePoint = Int(numberString), let scalar = UnicodeScalar(codePoint) {
                return String(scalar)
            } else {
                return nsSource.substring(with: match.range)
            }
        }

        // Hex entities
        decoded = replacingMatches(pattern: "&#x([0-9A-Fa-f]+);") { match, source in
            let nsSource = source as NSString
            let hexRange = match.range(at: 1)
            let hexString = nsSource.substring(with: hexRange)
            if let codePoint = Int(hexString, radix: 16), let scalar = UnicodeScalar(codePoint) {
                return String(scalar)
            } else {
                return nsSource.substring(with: match.range)
            }
        }

        return decoded
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 16) {
        // Successful tool call with result
        ToolCallView(toolCall: .init(
            toolName: "noema.web.retrieve",
            displayName: "Web Search",
            iconName: "globe",
            requestParams: [
                "query": AnyCodable("latest news on AI"),
                "count": AnyCodable(5),
                "safesearch": AnyCodable("moderate")
            ],
            result: """
            [{"title": "Breaking: New AI Model Released", "url": "https://example.com/ai-news", "snippet": "A groundbreaking new AI model has been released today..."},
             {"title": "AI Safety Research Update", "url": "https://example.com/safety", "snippet": "Latest developments in AI safety research show promising results..."}]
            """,
            error: nil
        ))
        
        // In-progress tool call
        ToolCallView(toolCall: .init(
            toolName: "noema.code.analyze",
            displayName: "Code Analysis",
            iconName: "curlybraces",
            requestParams: ["file": AnyCodable("main.swift"), "language": AnyCodable("swift")],
            result: nil,
            error: nil
        ))
        
        // Failed tool call
        ToolCallView(toolCall: .init(
            toolName: "noema.web.retrieve",
            displayName: "Web Search",
            iconName: "globe",
            requestParams: ["query": AnyCodable("test query")],
            result: nil,
            error: "Network error: Connection failed"
        ))
    }
    .padding()
    .frame(maxWidth: .infinity)
    .background(Color(.systemBackground))
}
