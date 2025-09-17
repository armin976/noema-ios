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
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Result")
                                    .font(.headline)
                                    .foregroundColor(.green)
                            }
                            
                                                ScrollView {
                        Text(formatResult(result))
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 300)
                    .padding()
                    .background(Color.green.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.green.opacity(0.2), lineWidth: 1)
                    )
                    .cornerRadius(8)
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
        }
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
