> ## Documentation Index
> Fetch the complete documentation index at: https://docs.liquid.ai/llms.txt
> Use this file to discover all available pages before exploring further.

# Messages & Content

> API reference for chat messages and content types in the LEAP iOS SDK

## Chat Messages

### Roles

```swift  theme={"theme":{"light":"github-light","dark":"github-dark"}}
public enum ChatMessageRole: String {
  case user
  case system
  case assistant
  case tool
}
```

Include `.tool` messages when you append function-call results back into the conversation.

### Message Structure

```swift  theme={"theme":{"light":"github-light","dark":"github-dark"}}
public struct ChatMessage {
  public var role: ChatMessageRole
  public var content: [ChatMessageContent]
  public var reasoningContent: String?
  public var functionCalls: [LeapFunctionCall]?

  public init(
    role: ChatMessageRole,
    content: [ChatMessageContent],
    reasoningContent: String? = nil,
    functionCalls: [LeapFunctionCall]? = nil
  )

  public init(from json: [String: Any]) throws
}
```

* `content`: Ordered fragments of the message. The SDK supports `.text`, `.image`, and `.audio` parts.
* `reasoningContent`: Optional text produced inside `<think>` tags by eligible models.
* `functionCalls`: Attach the calls returned by `MessageResponse.functionCall` when you include tool execution results in the history.

### Message Content

```swift  theme={"theme":{"light":"github-light","dark":"github-dark"}}
public enum ChatMessageContent {
  case text(String)
  case image(Data)   // JPEG bytes
  case audio(Data)   // WAV bytes

  public init(from json: [String: Any]) throws
}
```

Provide JPEG-encoded bytes for `.image` and WAV data for `.audio`. Helper initializers such as `ChatMessageContent.fromUIImage`, `ChatMessageContent.fromNSImage`, `ChatMessageContent.fromWAVData`, and `ChatMessageContent.fromFloatSamples(_:sampleRate:channelCount:)` simplify interop with platform-native buffers. On the wire, image parts are encoded as OpenAI-style `image_url` payloads and audio parts as `input_audio` arrays with Base64 data.
