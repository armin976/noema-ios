# Expanding generation with tool calling

**Build tools that enable the model to perform tasks that are specific to your use case.**

## Overview

Tools provide a way to extend the functionality of the model for your own use cases. Tool calling allows the model to interact with external code you create in order to fetch up to date information, ground responses in sources of truth that you provide, and perform side effects such as turning on dark mode.

You can create tools that enable the model to:

* Query entries from your app’s database and reference them in its answer
* Perform actions within your app, such as adjusting game difficulty or making a web request
* Integrate with other frameworks such as Contacts or HealthKit that already use platform privacy and security mechanisms

## Create a custom tool for your task

When you prompt the model with a request, it decides whether it can answer directly or whether it should call a tool. If a tool is helpful, the model generates arguments and invokes it. After the tool runs, it returns output to the model, which then produces the final response.

The framework follows six phases:

1. You present a list of available tools and their parameters to the model
2. You submit your prompt
3. The model generates arguments for the tool or tools it wants to invoke
4. Your tool runs code using those arguments
5. Your tool passes its output back to the model
6. The model produces a final response using the tool output

A tool conforms to `Tool` and defines accepted arguments and a call method. Tool calls may run concurrently with themselves or with other tools.

### Example tool

```swift
struct BreadDatabaseTool: Tool {
    let name = "searchBreadDatabase"
    let description = "Searches a local database for bread recipes."

    @Generable
    struct Arguments {
        @Guide(description: "The type of bread to search for")
        var searchTerm: String

        @Guide(description: "The number of recipes to get", .range(1...6))
        var limit: Int
    }

    struct Recipe {
        var name: String
        var description: String
        var link: URL
    }

    func call(arguments: Arguments) async throws -> [String] {
        var recipes: [Recipe] = []
        // Retrieve recipes from your database here.

        let formattedRecipes = recipes.map {
            "Recipe for '\($0.name)': \($0.description) Link: \($0.link)"
        }
        return formattedRecipes
    }
}
```

Descriptions on generable properties help the model understand argument semantics. Keep them brief to reduce context usage and latency. Tools use guided generation for their `Arguments` type.

## Provide a session with the tool you create

When creating a `LanguageModelSession`, you can provide relevant tools. These remain available for all later interactions in that session.

```swift
let session = LanguageModelSession(
    tools: [BreadDatabaseTool()]
)

let response = try await session.respond(
    to: "Find three sourdough bread recipes"
)
```

Tool output may be a `String` or a `GeneratedContent` object. The model can call tools multiple times in parallel when useful.

### Example weather tool

```swift
struct WeatherTool: Tool {
    let name = "getWeather"
    let description = "Retrieve the latest weather information for a city"

    @Generable
    struct Arguments {
        @Guide(description: "The city to get weather information for")
        var city: String
    }

    struct Forecast: Encodable {
        var city: String
        var temperature: Int
    }

    func call(arguments: Arguments) async throws -> String {
        let temperature = Int.random(in: 30...100)

        let formattedResult = """
        The forecast for '\(arguments.city)' is '\(temperature)' degrees Fahrenheit.
        """
        return formattedResult
    }
}

let session = LanguageModelSession(
    tools: [WeatherTool()],
    instructions: "Help the person with getting weather information"
)

let response = try await session.respond(
    to: "Is it hotter in Boston, Wichita, or Pittsburgh?"
)
```

## Handle errors thrown by a tool

If a tool throws an error, the session throws `LanguageModelSession.ToolCallError`. This includes both the tool reference and the underlying error so you can diagnose the issue.

Tools may throw when access is denied, data is missing, or a network request fails. A tool may also return a short failure string for the model to incorporate.

```swift
do {
    let answer = try await session.respond(
        "Find a recipe for tomato soup."
    )
} catch let error as LanguageModelSession.ToolCallError {
    print(error.tool.name)

    if case .databaseIsEmpty =
        error.underlyingError as? SearchBreadDatabaseToolError {
        // Display an error in the UI.
    }
} catch {
    print("Some other error: \(error)")
}
```

## Inspect the call graph

A session exposes an observable `transcript` that records prompts, tool calls, tool outputs, and responses. This makes debugging and visualization straightforward, especially when paired with SwiftUI.

```swift
struct MyHistoryView: View {
    @State var session = LanguageModelSession(
        tools: [BreadDatabaseTool()]
    )

    var body: some View {
        List(session.transcript) { entry in
            switch entry {
            case .instructions(let instructions):
                // Show instructions
            case .prompt(let prompt):
                // Show prompt
            case .toolCall(let call):
                // Show tool name and arguments
            case .toolOutput(let output):
                // Show tool output
            case .response(let response):
                // Show model response
            }
        }
        .task {
            do {
                try await session.respond(
                    to: "Find a milk bread recipe."
                )
            } catch {
                // Handle error
            }
        }
    }
}
```

## See also

* Generate dynamic game content with guided generation and tools
* `Tool` protocol documentation
* Guided generation for Swift data structures
* Managing the on device foundation model context window
