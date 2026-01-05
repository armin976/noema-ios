// ToolRegistration.swift
import Foundation

// MARK: - Tool Registration and Initialization

@MainActor
public final class ToolRegistrar {
    public static let shared = ToolRegistrar()
    private var isInitialized = false
    
    private init() {}
    
    public func initializeTools() async {
        guard !isInitialized else { return }
        
        await logger.log("[ToolRegistrar] Initializing tools...")
        
        // Register web search tool
        await registerWebSearchTool()
        
        // Add more tools here as they become available
        // registerDatasetSearchTool()
        // registerCodeAnalysisTool()
        // registerCalculatorTool()
        
        isInitialized = true
        await logger.log("[ToolRegistrar] Tool initialization complete. Registered tools: \(ToolRegistry.shared.registeredToolNames)")
    }
    
    private func registerWebSearchTool() async {
        let webTool = WebRetrieveTool()
        ToolRegistry.shared.register(webTool)
        await logger.log("[ToolRegistrar] Registered WebRetrieveTool (SearXNG)")
    }
}

// MARK: - Tool Factory

public struct ToolFactory {
    
    // Factory method for creating tool instances with proper configuration
    public static func createWebSearchTool() -> WebRetrieveTool {
        return WebRetrieveTool()
    }
    
    // Add more factory methods for other tools as needed
    /*
    public static func createDatasetSearchTool() -> DatasetSearchTool {
        // Implementation for dataset search tool
    }
    
    public static func createCodeAnalysisTool() -> CodeAnalysisTool {
        // Implementation for code analysis tool
    }
    */
}

// MARK: - Tool Configuration

public struct ToolConfiguration {
    public let webSearchEnabled: Bool
    public let offlineMode: Bool
    public let maxToolTurns: Int
    public let toolTimeout: TimeInterval
    
    public init(
        webSearchEnabled: Bool = true,
        offlineMode: Bool = false,
        maxToolTurns: Int = 4,
        toolTimeout: TimeInterval = 30.0
    ) {
        self.webSearchEnabled = webSearchEnabled
        self.offlineMode = offlineMode
        self.maxToolTurns = maxToolTurns
        self.toolTimeout = toolTimeout
    }
    
    public static var `default`: ToolConfiguration {
        return ToolConfiguration()
    }
    
    public static func fromUserDefaults() -> ToolConfiguration {
        let defaults = UserDefaults.standard
        
        let webSearchEnabled = defaults.object(forKey: "webSearchEnabled") as? Bool ?? true
        let offlineMode = defaults.object(forKey: "offGrid") as? Bool ?? false
        let maxToolTurns = defaults.object(forKey: "maxToolTurns") as? Int ?? 4
        let toolTimeout = defaults.object(forKey: "toolTimeout") as? TimeInterval ?? 30.0
        
        let cfg = ToolConfiguration(
            webSearchEnabled: webSearchEnabled,
            offlineMode: offlineMode,
            maxToolTurns: maxToolTurns,
            toolTimeout: toolTimeout
        )
        // Apply network kill switch to align with tool configuration
        NetworkKillSwitch.setEnabled(cfg.offlineMode)
        return cfg
    }
}

// MARK: - Tool Manager

@MainActor
public final class ToolManager {
    public static let shared = ToolManager()
    
    private var configuration: ToolConfiguration
    private var toolLoop: ToolLoop?
    
    private init() {
        self.configuration = ToolConfiguration.fromUserDefaults()
    }
    
    public func updateConfiguration(_ config: ToolConfiguration) {
        self.configuration = config
        
        // Re-initialize tools if configuration changed
        Task {
            await ToolRegistrar.shared.initializeTools()
        }
    }
    
    public func createToolLoop(for backend: any ToolCapableLLM) async -> ToolLoop {
        let registry = await ToolRegistry.shared
        let toolLoop = ToolLoop(
            llm: backend,
            registry: registry,
            maxToolTurns: configuration.maxToolTurns,
            temperature: 0.7
        )
        
        self.toolLoop = toolLoop
        return toolLoop
    }
    
    public func isToolAvailable(_ toolName: String) async -> Bool {
        guard !configuration.offlineMode else { return false }
        
        switch toolName {
        case "noema.web.retrieve":
            // Use gate and require function-calling support by model card/capability detector
            return configuration.webSearchEnabled && WebToolGate.isAvailable(currentFormat: nil)
        default:
            let registry = await ToolRegistry.shared
            return registry.tool(named: toolName) != nil
        }
    }
    
    public var availableTools: [String] {
        get async {
            let registry = await ToolRegistry.shared
            var tools: [String] = []
            for toolName in registry.registeredToolNames {
                if await isToolAvailable(toolName) {
                    tools.append(toolName)
                }
            }
            return tools
        }
    }
}

// MARK: - Integration Helper

#if os(iOS) || os(visionOS)
extension ChatVM {

    func initializeToolSystem() {
        Task { @MainActor in
            await ToolRegistrar.shared.initializeTools()
            await logger.log("[ChatVM] Tool system initialized")
        }
    }

    func runToolEnabledGeneration(prompt: String) async throws -> String {
        // This would integrate with the existing ChatVM to use tools
        var messages = [
            ToolChatMessage.system("You are a helpful assistant with access to tools."),
            ToolChatMessage.user(prompt)
        ]

        // Get the current backend and create a tool-capable version
        // This would need to be integrated with the existing backend system

        await logger.log("[ChatVM] Running tool-enabled generation for: \(prompt.prefix(100))...")

        // For now, return a placeholder
        return "Tool-enabled generation not yet integrated with ChatVM"
    }
}
#elseif os(macOS)
extension ChatVM {
    func initializeToolSystem() { }
}
#endif
