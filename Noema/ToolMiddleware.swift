// ToolMiddleware.swift
import Foundation

private let toolPrefix = "TOOL_CALL:"

// Returns true if the given index lies within an open <think>…</think> block in textBuffer
private func isIndexInsideOpenThink(_ textBuffer: String, at index: String.Index) -> Bool {
    // Consider only the prefix up to the index
    let prefix = textBuffer[..<index]
    let lastOpen = prefix.range(of: "<think>", options: .backwards)
    let lastClose = prefix.range(of: "</think>", options: .backwards)
    if let o = lastOpen {
        if let c = lastClose { return o.lowerBound > c.lowerBound }
        return true
    }
    return false
}

// Tool metadata for UI display
struct ToolMetadata {
    let displayName: String
    let iconName: String
}

private let toolMetadataMap: [String: ToolMetadata] = [
    "noema.web.retrieve": ToolMetadata(displayName: "Web Search", iconName: "globe"),
    "noema.dataset.search": ToolMetadata(displayName: "Dataset Search", iconName: "doc.text.magnifyingglass"),
    "noema.code.analyze": ToolMetadata(displayName: "Code Analysis", iconName: "curlybraces"),
    "noema.math.calculate": ToolMetadata(displayName: "Calculator", iconName: "function"),
    "noema.image.analyze": ToolMetadata(displayName: "Image Analysis", iconName: "photo"),
    "noema.file.read": ToolMetadata(displayName: "File Reader", iconName: "doc"),
    "noema.system.info": ToolMetadata(displayName: "System Info", iconName: "info.circle"),
]

// Normalize various aliases emitted by different models to our canonical names
private func normalizeToolName(_ raw: String) -> String {
    if raw == "noema.web.retrieve" { return "noema.web.retrieve" }
    if raw == "noema_web_retrieve" { return "noema.web.retrieve" }
    // Common SLM/SDK aliases
    if raw == "Web_Search" || raw == "WEB_SEARCH" { return "noema.web.retrieve" }
    let lower = raw.lowercased()
    if lower == "web_search" || lower == "web.search" || lower == "websearch" || lower == "web-search" {
        return "noema.web.retrieve"
    }
    return raw
}

private func getToolMetadata(_ toolName: String) -> ToolMetadata {
    let canonical = normalizeToolName(toolName)
    return toolMetadataMap[canonical] ?? ToolMetadata(
        displayName: canonical.components(separatedBy: ".").last?.capitalized ?? "Tool",
        iconName: "wrench.and.screwdriver"
    )
}

@MainActor
func interceptToolCallIfPresent(_ line: String, messageIndex: Int? = nil, chatVM: ChatVM? = nil) async -> (String, String?)? {
    guard line.hasPrefix(toolPrefix) else { return nil }

    // Extract JSON block and preserve any trailing text after the closing brace
    let afterPrefix = String(line.dropFirst(toolPrefix.count))
    guard let open = afterPrefix.firstIndex(of: "{"),
          let close = findMatchingBrace(in: afterPrefix, startingFrom: open) else {
        // Incomplete JSON – wait for more tokens
        return nil
    }
    let jsonPart = String(afterPrefix[open...close])
    let trailingStart = afterPrefix.index(after: close)
    let trailingRaw = afterPrefix[trailingStart...]
    let trailing = String(trailingRaw).trimmingCharacters(in: .whitespacesAndNewlines)

    await logger.log("[Tool] TOOL_CALL detected: \(jsonPart)")

    struct Call: Decodable { let tool: String; let args: [String: AnyCodable] }
    guard let data = jsonPart.data(using: .utf8) else {
        return ("TOOL_RESULT: {\"code\":\"PARSE\",\"message\":\"Invalid encoding\"}", trailing.isEmpty ? nil : trailing)
    }
    
    do {
        let call = try JSONDecoder().decode(Call.self, from: data)
        let canonicalTool = normalizeToolName(call.tool)
        let metadata = getToolMetadata(canonicalTool)

        // Normalize common argument aliases before dispatch (e.g., top_k -> count, safe_search -> safesearch)
        var normalizedArgs = call.args.mapValues { $0.value }
        if let topk = normalizedArgs.removeValue(forKey: "top_k") { normalizedArgs["count"] = topk }
        if let safeSearch = normalizedArgs.removeValue(forKey: "safe_search") { normalizedArgs["safesearch"] = safeSearch }

        // For Leap SLM calls the model often omits optional params. Provide user-facing defaults
        // so the UI mirrors MLX/GGUF behavior.
        if canonicalTool == "noema.web.retrieve" {
            if normalizedArgs["count"] == nil { normalizedArgs["count"] = 3 }
            if normalizedArgs["safesearch"] == nil { normalizedArgs["safesearch"] = "moderate" }
            // Clamp invalid safesearch values to moderate
            if let s = normalizedArgs["safesearch"] as? String {
                let allowed = ["off", "moderate", "strict"]
                if !allowed.contains(s.lowercased()) { normalizedArgs["safesearch"] = "moderate" }
            }
            // If query is missing or invalid, fall back to the latest user message.
            if normalizedArgs["query"] == nil || (normalizedArgs["query"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                if let chatVM, let idx = messageIndex {
                    // Look backwards for the nearest user message before or equal to this index
                    var i = idx
                    var priorUser: String = ""
                    while i >= 0 {
                        if chatVM.streamMsgs.indices.contains(i) {
                            let r = chatVM.streamMsgs[i].role.lowercased()
                            if r == "user" || r == "🧑‍💻" { priorUser = chatVM.streamMsgs[i].text; break }
                        }
                        i -= 1
                    }
                    if !priorUser.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        normalizedArgs["query"] = priorUser
                    }
                }
            }
        }

        // Prepare params for UI display as [String: AnyCodable]
        let displayParams: [String: AnyCodable] = normalizedArgs.reduce(into: [:]) { acc, pair in
            acc[pair.key] = AnyCodable(pair.value)
        }

        // Create or update the tool call entry for the UI using normalized/display params
        var toolCall = ChatVM.Msg.ToolCall(
            toolName: canonicalTool,
            displayName: metadata.displayName,
            iconName: metadata.iconName,
            requestParams: displayParams
        )
        
        // Add or update tool call to the message if we have the context
        if let messageIndex = messageIndex, let chatVM = chatVM {
            if chatVM.streamMsgs.indices.contains(messageIndex) {
                if chatVM.streamMsgs[messageIndex].toolCalls == nil {
                    chatVM.streamMsgs[messageIndex].toolCalls = []
                }
                // Deduplicate: if the last call has the same canonical tool name and no result yet,
                // update it in place rather than appending a second entry.
                if var existing = chatVM.streamMsgs[messageIndex].toolCalls, let lastIndex = existing.indices.last,
                   existing[lastIndex].toolName == toolCall.toolName,
                   existing[lastIndex].result == nil && existing[lastIndex].error == nil {
                    let currentId = existing[lastIndex].id
                    toolCall = ChatVM.Msg.ToolCall(
                        id: currentId,
                        toolName: toolCall.toolName,
                        displayName: toolCall.displayName,
                        iconName: toolCall.iconName,
                        requestParams: toolCall.requestParams,
                        result: nil,
                        error: nil
                    )
                    existing[lastIndex] = toolCall
                    chatVM.streamMsgs[messageIndex].toolCalls = existing
                } else {
                    chatVM.streamMsgs[messageIndex].toolCalls?.append(toolCall)
                }
            }
        }
        
        guard let tool = ToolRegistry.shared.tool(named: canonicalTool) else {
            await logger.log("[Tool] Unknown tool: \(canonicalTool)")
            
            // Update tool call with error
            if let messageIndex = messageIndex, let chatVM = chatVM,
               chatVM.streamMsgs.indices.contains(messageIndex),
               var toolCalls = chatVM.streamMsgs[messageIndex].toolCalls,
               let lastIndex = toolCalls.indices.last {
                toolCalls[lastIndex] = ChatVM.Msg.ToolCall(
                    id: toolCall.id,
                    toolName: toolCall.toolName,
                    displayName: toolCall.displayName,
                    iconName: toolCall.iconName,
                    requestParams: toolCall.requestParams,
                    result: nil,
                    error: "Tool not registered"
                )
                chatVM.streamMsgs[messageIndex].toolCalls = toolCalls
            }
            
            return ("TOOL_RESULT: {\"code\":\"UNKNOWN_TOOL\",\"message\":\"Tool not registered\"}", trailing.isEmpty ? nil : trailing)
        }
        
        // Use normalized args for execution; clamp web search count to a hard maximum of 5 regardless of input
        var clampedArgs = normalizedArgs
        if canonicalTool == "noema.web.retrieve" {
            if let rawCount = clampedArgs["count"] as? Int {
                clampedArgs["count"] = max(1, min(rawCount, 5))
            } else if let rawCountString = clampedArgs["count"] as? String, let parsed = Int(rawCountString) {
                clampedArgs["count"] = max(1, min(parsed, 5))
            }
        }
        await logger.log("[Tool] Invoking \(canonicalTool) with args: \(clampedArgs)")
        let argsData = try JSONSerialization.data(withJSONObject: clampedArgs)
        
        // Respect cancellation before starting any tool work
        if Task.isCancelled { return nil }

        // Check for direct handler for faster execution
        let outData: Data
        if canonicalTool == "noema.web.retrieve" {
            let contextLimit = chatVM?.contextLimit ?? 4096
            outData = await handle_noema_web_retrieve(argsData, contextLimit: contextLimit)
        } else {
            outData = try await tool.call(args: argsData)
        }
        let outString = String(data: outData, encoding: .utf8) ?? "{\"code\":\"ENCODE\",\"message\":\"Failed to encode\"}"
        let preview = outString.count > 400 ? String(outString.prefix(400)) + "…" : outString
        await logger.log("[Tool] Result from \(canonicalTool): \(preview)")
        
        // Update tool call with result
        if let messageIndex = messageIndex, let chatVM = chatVM,
           chatVM.streamMsgs.indices.contains(messageIndex),
           var toolCalls = chatVM.streamMsgs[messageIndex].toolCalls,
           let lastIndex = toolCalls.indices.last {
            toolCalls[lastIndex] = ChatVM.Msg.ToolCall(
                id: toolCall.id,
                toolName: toolCall.toolName,
                displayName: toolCall.displayName,
                iconName: toolCall.iconName,
                requestParams: toolCall.requestParams,
                result: outString,
                error: nil
            )
            chatVM.streamMsgs[messageIndex].toolCalls = toolCalls
        }

        // If this is the web search tool, optionally update the message's
        // webHits/webError so the UI transitions from "Searching the web…".
        // Skip this UI injection for SLM flows — we want zero UI-level context injection.
        if Task.isCancelled { return nil }
        if canonicalTool == "noema.web.retrieve",
           let messageIndex = messageIndex,
           let chatVM = chatVM,
           chatVM.streamMsgs.indices.contains(messageIndex) {
            let isSLM = (chatVM.currentModelFormat == .slm)
            if !isSLM {
                await logger.log("[Tool][UI] Applying web search result to message state")
                chatVM.streamMsgs[messageIndex].usedWebSearch = true
                if let data = outString.data(using: .utf8) {
                    struct SimpleWebHit: Decodable { let title: String; let url: String; let snippet: String }
                    if let hits = try? JSONDecoder().decode([SimpleWebHit].self, from: data) {
                        chatVM.streamMsgs[messageIndex].webError = nil
                        chatVM.streamMsgs[messageIndex].webHits = hits.enumerated().map { (i, h) in
                            .init(id: String(i+1), title: h.title, snippet: h.snippet, url: h.url, engine: "brave", score: 0)
                        }
                    } else if let any = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let err: String? = {
                            if let e = any["error"] as? String { return e }
                            if let msg = any["message"] as? String { return msg }
                            if let code = any["code"] { return "Error: \(code)" }
                            return nil
                        }()
                        if let err = err, !err.isEmpty {
                            chatVM.streamMsgs[messageIndex].webError = err
                            chatVM.streamMsgs[messageIndex].webHits = nil
                        }
                    }
                }
            }
        }
        
        if Task.isCancelled { return nil }
        return ("TOOL_RESULT: \(outString)", trailing.isEmpty ? nil : trailing)
    } catch {
        if (error as? CancellationError) != nil { return nil }
        await logger.log("[Tool] Parse/dispatch error: \(error.localizedDescription)")
        
        // Update tool call with error if we have the context
        if let messageIndex = messageIndex, let chatVM = chatVM,
           chatVM.streamMsgs.indices.contains(messageIndex),
           var toolCalls = chatVM.streamMsgs[messageIndex].toolCalls,
           let lastIndex = toolCalls.indices.last {
            toolCalls[lastIndex] = ChatVM.Msg.ToolCall(
                id: toolCalls[lastIndex].id,
                toolName: toolCalls[lastIndex].toolName,
                displayName: toolCalls[lastIndex].displayName,
                iconName: toolCalls[lastIndex].iconName,
                requestParams: toolCalls[lastIndex].requestParams,
                result: nil,
                error: error.localizedDescription
            )
            chatVM.streamMsgs[messageIndex].toolCalls = toolCalls
        }
        
        if Task.isCancelled { return nil }
        return ("TOOL_RESULT: {\"code\":\"PARSE\",\"message\":\"\(error)\"}", trailing.isEmpty ? nil : trailing)
    }
}

// Detect and handle XML-style or bare-JSON tool calls that appear inside an accumulated buffer.
// This supports responses like:
// <tool_call>{"tool_name":"noema.web.retrieve","arguments":{"query":"...","count":3,"safesearch":"moderate"}}</tool_call>
// as well as a bare JSON object with the same shape (often emitted inside a "Thought." block).
// MLX models may emit a simplified structure {"tool":"...","args":{...}}, which is also handled here.
@MainActor
func interceptEmbeddedToolCallIfPresent(
    in textBuffer: String,
    messageIndex: Int? = nil,
    chatVM: ChatVM? = nil
) async -> (token: String, cleanedText: String)? {
    // 1) Try bare JSON around specific web tool name to quickly dispatch
    if let webRange = textBuffer.range(of: "noema.web.retrieve"),
       let open = textBuffer[..<webRange.lowerBound].lastIndex(of: "{"),
       let close = findMatchingBrace(in: textBuffer, startingFrom: open) {
        let candidate = String(textBuffer[open...close])
        if (candidate.contains("\"arguments\"") || candidate.contains("\"args\"")) {
            await logger.log("[Tool] Attempting to parse JSON around web tool: \(candidate.prefix(200))…")
            if let token = await dispatchParsedToolCallJSON(jsonString: candidate, messageIndex: messageIndex, chatVM: chatVM) {
                let before = String(textBuffer[..<open])
                var afterStart = textBuffer.index(after: close)
                while afterStart < textBuffer.endIndex && textBuffer[afterStart].isWhitespace {
                    afterStart = textBuffer.index(after: afterStart)
                }
                if afterStart < textBuffer.endIndex && textBuffer[afterStart] == "}" {
                    afterStart = textBuffer.index(after: afterStart)
                }
                let after = String(textBuffer[afterStart...])
                return (token, before + after)
            }
        }
    }

    // 2) Generic scan for JSON objects anywhere in the buffer
    var searchIndex = textBuffer.startIndex
    while searchIndex < textBuffer.endIndex {
        guard let startIndex = textBuffer[searchIndex...].firstIndex(of: "{") else { break }
        if let endIndex = findMatchingBrace(in: textBuffer, startingFrom: startIndex) {
            let candidate = String(textBuffer[startIndex...endIndex])
            if (candidate.contains("\"tool_name\"") || candidate.contains("\"name\"") || candidate.contains("\"tool\"")) &&
               (candidate.contains("\"arguments\"") || candidate.contains("\"args\"")) {
                await logger.log("[Tool] Attempting to parse JSON: \(candidate.prefix(200))…")
                if let token = await dispatchParsedToolCallJSON(jsonString: candidate, messageIndex: messageIndex, chatVM: chatVM) {
                    var removalStart = startIndex
                    var removalEnd = endIndex
                    if let fenceStart = textBuffer[..<startIndex].range(of: "```json", options: .backwards)?.lowerBound {
                        removalStart = fenceStart
                    } else if let fenceStart = textBuffer[..<startIndex].range(of: "```", options: .backwards)?.lowerBound {
                        removalStart = fenceStart
                    }
                    let afterEnd = textBuffer.index(after: endIndex)
                    if let fenceEnd = textBuffer[afterEnd...].range(of: "```")?.upperBound {
                        removalEnd = fenceEnd
                    }

                    // If JSON was emitted inside <tool_call> tags, remove the tags too
                    if let tagOpen = textBuffer[..<removalStart].range(of: "<tool_call>", options: .backwards) {
                        removalStart = tagOpen.lowerBound
                        if let tagClose = textBuffer[removalEnd...].range(of: "</tool_call>") {
                            removalEnd = tagClose.upperBound
                        }
                    }

                    let before = String(textBuffer[..<removalStart])
                    var afterStart: String.Index
                    if removalEnd == endIndex {
                        afterStart = textBuffer.index(after: removalEnd)
                    } else {
                        afterStart = removalEnd
                    }
                    while afterStart < textBuffer.endIndex && textBuffer[afterStart].isWhitespace {
                        afterStart = textBuffer.index(after: afterStart)
                    }
                    if afterStart < textBuffer.endIndex && textBuffer[afterStart] == "}" {
                        afterStart = textBuffer.index(after: afterStart)
                    }
                    let after = String(textBuffer[afterStart...])
                    return (token, before + after)
                }
            }
            searchIndex = textBuffer.index(after: endIndex)
        } else {
            let remainder = String(textBuffer[startIndex...])
            if (remainder.contains("\"tool_name\"") || remainder.contains("\"name\"") || remainder.contains("\"tool\"")) &&
               (remainder.contains("\"arguments\"") || remainder.contains("\"args\"")) {
                if let messageIndex = messageIndex, let chatVM = chatVM, chatVM.streamMsgs.indices.contains(messageIndex) {
                    var existing = chatVM.streamMsgs[messageIndex].toolCalls ?? []
                    let alreadyPending = existing.last?.result == nil && existing.last?.error == nil
                    if !alreadyPending {
                        let toolName = extractToolName(from: remainder) ?? "tool.call"
                        let meta = getToolMetadata(toolName)
                        let placeholder = ChatVM.Msg.ToolCall(
                            toolName: toolName,
                            displayName: meta.displayName,
                            iconName: meta.iconName,
                            requestParams: [:]
                        )
                        existing.append(placeholder)
                        chatVM.streamMsgs[messageIndex].toolCalls = existing
                        await logger.log("[Tool] Placeholder tool box inserted for \(toolName)")
                    }
                }
            }
            break
        }
    }

    // 3) Fallback: XML-style <tool_call>…</tool_call>
    if let start = textBuffer.range(of: "<tool_call>") {
        await logger.log("[Tool][Scan] Found <tool_call> marker in buffer (len=\(textBuffer.count))")
        if let end = textBuffer.range(of: "</tool_call>") {
            let rawInside = String(textBuffer[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            // Some models wrap JSON in code fences inside the tool_call tag; strip fences
            let jsonString: String = {
                var s = rawInside
                if s.hasPrefix("```") {
                    // Drop opening ```[lang]? line
                    if let fenceEnd = s.firstIndex(of: "\n") { s = String(s[s.index(after: fenceEnd)...]) } else { s = s.replacingOccurrences(of: "```", with: "") }
                }
                if s.hasSuffix("```") { s.removeLast(3) }
                return s.trimmingCharacters(in: .whitespacesAndNewlines)
            }()
            // Some models incorrectly place a tool RESULT inside <tool_call>. If we detect
            // a result-only object, skip logging/dispatch here and let generic detection
            // find the actual tool CALL JSON elsewhere in the buffer.
            let lower = jsonString.lowercased()
            let looksLikeResultOnly = lower.contains("\"result\"") && !(lower.contains("\"tool_name\"") || lower.contains("\"name\"") || lower.contains("\"tool\""))
            if !looksLikeResultOnly {
                // Ensure we have a complete JSON object before dispatching; if not, wait for more tokens
                if let firstBrace = jsonString.firstIndex(of: "{"),
                   let lastBrace = findMatchingBrace(in: jsonString, startingFrom: firstBrace) {
                    let complete = String(jsonString[firstBrace...lastBrace])
                    await logger.log("[Tool][Scan] Extracted JSON inside <tool_call>: \(complete.prefix(220))…")
                    if let token = await dispatchParsedToolCallJSON(jsonString: complete, messageIndex: messageIndex, chatVM: chatVM) {
                        let before = String(textBuffer[..<start.lowerBound])
                        let after = String(textBuffer[end.upperBound...])
                        return (token, before + after)
                    } else {
                        await logger.log("[Tool][Scan] dispatchParsedToolCallJSON returned nil for extracted JSON")
                    }
                } else {
                    // Incomplete JSON inside <tool_call>; do NOT bail. Some models emit a
                    // valid bare JSON tool object before the <tool_call> wrapper. Continue
                    // scanning below for bare JSON candidates in the buffer.
                    await logger.log("[Tool][Scan] Incomplete JSON inside <tool_call>; continuing to scan for bare JSON")
                }
            }
        } else {
            // No closing tag yet. Be tolerant: attempt to extract the first complete JSON
            // object after <tool_call> and dispatch immediately. This covers cases where
            // stop tokens cut the stream before </tool_call> is emitted.
            let tail = String(textBuffer[start.upperBound...])
            if let firstBrace = tail.firstIndex(of: "{"),
               let lastBrace = findMatchingBrace(in: tail, startingFrom: firstBrace) {
                let candidate = String(tail[firstBrace...lastBrace])
                await logger.log("[Tool][Scan] Found JSON after open <tool_call> (no close yet): \(candidate.prefix(220))…")
                if let token = await dispatchParsedToolCallJSON(jsonString: candidate, messageIndex: messageIndex, chatVM: chatVM) {
                    let before = String(textBuffer[..<start.lowerBound])
                    var afterStart = tail.index(after: lastBrace)
                    while afterStart < tail.endIndex && tail[afterStart].isWhitespace { afterStart = tail.index(after: afterStart) }
                    let after = String(tail[afterStart...])
                    return (token, before + after)
                } else {
                    await logger.log("[Tool][Scan] dispatchParsedToolCallJSON returned nil for JSON after open tag")
                }
            }
            // If we can't find a complete object yet, keep scanning for a bare JSON
            // object elsewhere in the buffer.
        }
    }

    return nil
}


@MainActor
private func dispatchParsedToolCallJSON(jsonString: String, messageIndex: Int? = nil, chatVM: ChatVM? = nil) async -> String? {
    // Clean wrappers and code fences, then extract the first complete JSON object
    func stripFencesAndTags(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "<tool_call>", with: "").replacingOccurrences(of: "</tool_call>", with: "")
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            if let nl = t.firstIndex(of: "\n") { t = String(t[t.index(after: nl)...]) } else { t = t.replacingOccurrences(of: "```", with: "") }
        }
        if t.hasSuffix("```") { t.removeLast(3) }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func extractFirstJSONObject(_ s: String) -> String? {
        guard let open = s.firstIndex(of: "{") else { return nil }
        guard let close = findMatchingBrace(in: s, startingFrom: open) else { return nil }
        return String(s[open...close])
    }
    func removeTrailingCommas(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        var inString = false
        var escape = false
        var i = s.startIndex
        // Lookahead for commas before } or ]
        while i < s.endIndex {
            let c = s[i]
            if escape { out.append(c); escape = false; i = s.index(after: i); continue }
            if c == "\\" && inString { out.append(c); escape = true; i = s.index(after: i); continue }
            if c == "\"" { inString.toggle(); out.append(c); i = s.index(after: i); continue }
            if !inString && c == "," {
                // Peek ahead skipping whitespace
                var j = s.index(after: i)
                while j < s.endIndex, s[j].isWhitespace { j = s.index(after: j) }
                if j < s.endIndex, s[j] == "}" || s[j] == "]" {
                    // Skip trailing comma
                    i = j; continue
                }
            }
            out.append(c)
            i = s.index(after: i)
        }
        return out
    }

    let cleaned = stripFencesAndTags(jsonString)
    guard let complete = extractFirstJSONObject(cleaned) else {
        // Incomplete object; wait for more tokens without logging an error
        return nil
    }

    struct XMLCall: Decodable {
        let tool_name: String
        let arguments: [String: AnyCodable]

        private enum CodingKeys: String, CodingKey { case tool_name, name, tool, arguments, args }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let tn = try container.decodeIfPresent(String.self, forKey: .tool_name) {
                self.tool_name = tn
            } else if let n = try container.decodeIfPresent(String.self, forKey: .name) {
                self.tool_name = n
            } else {
                self.tool_name = try container.decode(String.self, forKey: .tool)
            }
            if let args = try container.decodeIfPresent([String: AnyCodable].self, forKey: .arguments) {
                self.arguments = args
            } else if let args = try container.decodeIfPresent([String: AnyCodable].self, forKey: .args) {
                self.arguments = args
            } else if let argsString = try container.decodeIfPresent(String.self, forKey: .arguments) ?? container.decodeIfPresent(String.self, forKey: .args) {
                // Some models serialize the arguments object as a JSON string; parse it
                if let data = argsString.data(using: .utf8), let any = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    self.arguments = any.mapValues { AnyCodable($0) }
                } else {
                    self.arguments = [:]
                }
            } else {
                self.arguments = [:]
            }
        }
    }

    // Try strict decode first
    if let data = complete.data(using: .utf8), let call = try? JSONDecoder().decode(XMLCall.self, from: data) {
        // Reuse the canonical TOOL_CALL path to unify UI updates and execution
        let payload: [String: Any] = [
            "tool": call.tool_name,
            "args": call.arguments.mapValues { $0.value }
        ]
        if let payloadData = try? JSONSerialization.data(withJSONObject: payload),
           let payloadString = String(data: payloadData, encoding: .utf8) {
            if let (token, _) = await interceptToolCallIfPresent("\(toolPrefix)\(payloadString)", messageIndex: messageIndex, chatVM: chatVM) {
                return token
            }
        }
        return nil
    }
    // Retry after removing trailing commas which some models emit
    let relaxed = removeTrailingCommas(complete)
    if let data2 = relaxed.data(using: .utf8), let call2 = try? JSONDecoder().decode(XMLCall.self, from: data2) {
        let payload: [String: Any] = [
            "tool": call2.tool_name,
            "args": call2.arguments.mapValues { $0.value }
        ]
        if let payloadData = try? JSONSerialization.data(withJSONObject: payload),
           let payloadString = String(data: payloadData, encoding: .utf8) {
            if let (token, _) = await interceptToolCallIfPresent("\(toolPrefix)\(payloadString)", messageIndex: messageIndex, chatVM: chatVM) {
                return token
            }
        }
        return nil
    }

    // Last‑chance relaxed parser for slightly malformed objects that still look like
    // { "tool_name"|"name"|"tool": "...", "arguments"|"args": { ... } } but fail strict JSON decoding.
    // This helps with tiny SLMs or GGUF models that sometimes drop quotes or sprinkle
    // dangling commas despite the instructions not to.
    func extractBetween(_ s: String, start: String, end: String) -> String? {
        guard let r1 = s.range(of: start) else { return nil }
        guard let r2 = s.range(of: end, range: r1.upperBound..<s.endIndex) else { return nil }
        return String(s[r1.upperBound..<r2.lowerBound])
    }
    func bestEffortToolName(_ s: String) -> String? {
        // Try proper JSON key first
        if let tn = extractStringValue(forKey: "tool_name", in: s) { return tn }
        if let tn = extractStringValue(forKey: "name", in: s) { return tn }
        if let tn = extractStringValue(forKey: "tool", in: s) { return tn }
        // Try extremely relaxed patterns: tool_name: "..." without proper quoting
        if let rough = extractBetween(s, start: "tool_name", end: ",") ?? extractBetween(s, start: "tool:", end: ",") {
            if let q1 = rough.firstIndex(of: "\""), let q2 = rough[rough.index(after: q1)...].firstIndex(of: "\"") {
                return String(rough[rough.index(after: q1)..<q2])
            }
        }
        return nil
    }
    func bestEffortArgsJSON(_ s: String) -> String? {
        // Find the object after arguments/args key and return a balanced {...}
        for key in ["\"arguments\"", "\"args\"", "arguments", "args"] {
            if let keyRange = s.range(of: key),
               let colon = s.range(of: ":", range: keyRange.upperBound..<s.endIndex)?.lowerBound,
               let open = s[colon..<s.endIndex].firstIndex(of: "{") {
                let tail = String(s[open...])
                if let close = findMatchingBrace(in: tail, startingFrom: tail.startIndex) {
                    return String(tail[tail.startIndex...close])
                }
            }
        }
        return nil
    }
    if let tn = bestEffortToolName(complete), let argsJSON = bestEffortArgsJSON(complete) {
        // Build normalized payload
        let canonical = normalizeToolName(tn)
        var argsObj: [String: Any] = [:]
        if let data = argsJSON.data(using: .utf8),
           let any = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            argsObj = any
        }
        let payload: [String: Any] = ["tool": canonical, "args": argsObj]
        if let payloadData = try? JSONSerialization.data(withJSONObject: payload),
           let payloadString = String(data: payloadData, encoding: .utf8) {
            if let (token, _) = await interceptToolCallIfPresent("\(toolPrefix)\(payloadString)", messageIndex: messageIndex, chatVM: chatVM) {
                return token
            }
        }
    }

    await logger.log("[Tool] Failed to decode tool call JSON: \(complete.prefix(200))…")
    do {
        let data = complete.data(using: .utf8) ?? Data()
        let _ = try JSONDecoder().decode(XMLCall.self, from: data)
    } catch {
        await logger.log("[Tool] JSON decode error details: \(error)")
    }
    return nil
}

// finalizeDispatch removed; logic inlined in decode paths above

// Helper function to find the matching closing brace for a JSON object
private func findMatchingBrace(in text: String, startingFrom startIndex: String.Index) -> String.Index? {
    guard startIndex < text.endIndex, text[startIndex] == "{" else { return nil }
    var depth = 0
    var inString = false
    var escape = false
    var i = startIndex
    while i < text.endIndex {
        let c = text[i]
        if escape { escape = false; i = text.index(after: i); continue }
        if c == "\\" && inString { escape = true; i = text.index(after: i); continue }
        if c == "\"" { inString.toggle(); i = text.index(after: i); continue }
        if !inString {
            if c == "{" { depth += 1 }
            else if c == "}" {
                depth -= 1
                if depth == 0 { return i }
            }
        }
        i = text.index(after: i)
    }
    return nil
}

// Best-effort extraction of tool name from an incomplete JSON object
private func extractToolName(from text: String) -> String? {
    // Prefer new key
    if let tn = extractStringValue(forKey: "tool_name", in: text) { return tn }
    // Fallback for legacy
    if let n = extractStringValue(forKey: "name", in: text) { return n }
    // MLX-style simplified key
    if let t = extractStringValue(forKey: "tool", in: text) { return t }
    return nil
}

private func extractStringValue(forKey key: String, in text: String) -> String? {
    let quotedKey = "\"\(key)\""
    guard let keyRange = text.range(of: quotedKey) else { return nil }
    if let colon = text.range(of: ":", range: keyRange.upperBound..<text.endIndex)?.lowerBound,
       let firstQuote = text[ text.index(after: colon)..<text.endIndex ].firstIndex(of: "\"" ) {
        let afterFirst = text.index(after: firstQuote)
        if let secondQuote = text[ afterFirst..<text.endIndex ].firstIndex(of: "\"" ) {
            let value = String(text[afterFirst..<secondQuote])
            if !value.isEmpty { return value }
        }
    }
    return nil
}
