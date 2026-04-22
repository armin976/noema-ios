# Foundation Models

Perform tasks with the on-device model that specializes in language understanding, structured output, and tool calling.

Availability:

* iOS 26.0+
* iPadOS 26.0+
* Mac Catalyst 26.0+
* macOS 26.0+
* visionOS 26.0+

## Overview

The Foundation Models framework provides access to Apple’s on-device large language model that powers Apple Intelligence to help you perform intelligent tasks specific to your use case. The text-based on-device model identifies patterns that allow for generating new text that’s appropriate for the request you make, and it can make decisions to call code you write to perform specialized tasks.

Key capabilities:

* Generate text content based on requests you make. The on-device model excels at a diverse range of text generation tasks, like summarization, entity extraction, text understanding, refinement, dialog for games, generating creative content, and more.
* Generate entire Swift data structures with guided generation. With the `@Generable` macro, you can define custom data structures and the framework provides strong guarantees that the model generates instances of your type.
* Expand the model’s capabilities with tool calling. Use `Tool` to create custom tools that the model can call to assist with handling your request. For example, the model can call a tool that searches a local or online database for information, or calls a service in your app.

Requirements:

* To use the on-device language model, people need to turn on Apple Intelligence on their device.
* For a list of supported devices, see Apple Intelligence:
  [https://www.apple.com/apple-intelligence/](https://www.apple.com/apple-intelligence/)

Policy and usage:

* For more information about acceptable usage of the Foundation Models framework, see:
  [https://developer.apple.com/apple-intelligence/acceptable-use-requirements-for-the-foundation-models-framework](https://developer.apple.com/apple-intelligence/acceptable-use-requirements-for-the-foundation-models-framework)

## Related videos

* Meet the Foundation Models framework (WWDC25):
  [https://developer.apple.com/videos/play/wwdc2025/286](https://developer.apple.com/videos/play/wwdc2025/286)
* Deep dive into the Foundation Models framework (WWDC25):
  [https://developer.apple.com/videos/play/wwdc2025/301](https://developer.apple.com/videos/play/wwdc2025/301)
* Code-along: Bring on-device AI to your app using the Foundation Models framework (WWDC25):
  [https://developer.apple.com/videos/play/wwdc2025/259](https://developer.apple.com/videos/play/wwdc2025/259)

## Topics

### Essentials

* Generating content and performing tasks with Foundation Models
  [https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models)
* Improving the safety of generative model output
  [https://developer.apple.com/documentation/foundationmodels/improving-the-safety-of-generative-model-output](https://developer.apple.com/documentation/foundationmodels/improving-the-safety-of-generative-model-output)
* Supporting languages and locales with Foundation Models
  [https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models)
* Adding intelligent app features with generative models
  [https://developer.apple.com/documentation/foundationmodels/adding-intelligent-app-features-with-generative-models](https://developer.apple.com/documentation/foundationmodels/adding-intelligent-app-features-with-generative-models)
* `SystemLanguageModel` (class)
  [https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)
* `SystemLanguageModel.UseCase` (struct)
  [https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/usecase](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/usecase)

### Prompting

* Prompting an on-device foundation model
  [https://developer.apple.com/documentation/foundationmodels/prompting-an-on-device-foundation-model](https://developer.apple.com/documentation/foundationmodels/prompting-an-on-device-foundation-model)
* Analyzing the runtime performance of your Foundation Models app
  [https://developer.apple.com/documentation/foundationmodels/analyzing-the-runtime-performance-of-your-foundation-models-app](https://developer.apple.com/documentation/foundationmodels/analyzing-the-runtime-performance-of-your-foundation-models-app)
* `LanguageModelSession` (class)
  [https://developer.apple.com/documentation/foundationmodels/languagemodelsession](https://developer.apple.com/documentation/foundationmodels/languagemodelsession)
* `Instructions` (struct)
  [https://developer.apple.com/documentation/foundationmodels/instructions](https://developer.apple.com/documentation/foundationmodels/instructions)
* `Prompt` (struct)
  [https://developer.apple.com/documentation/foundationmodels/prompt](https://developer.apple.com/documentation/foundationmodels/prompt)
* `Transcript` (struct)
  [https://developer.apple.com/documentation/foundationmodels/transcript](https://developer.apple.com/documentation/foundationmodels/transcript)
* `GenerationOptions` (struct)
  [https://developer.apple.com/documentation/foundationmodels/generationoptions](https://developer.apple.com/documentation/foundationmodels/generationoptions)

### Guided generation

* Generating Swift data structures with guided generation
  [https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation)
* `Generable` (protocol)
  [https://developer.apple.com/documentation/foundationmodels/generable](https://developer.apple.com/documentation/foundationmodels/generable)

### Tool calling

* Expanding generation with tool calling
  [https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling)
* Generate dynamic game content with guided generation and tools
  [https://developer.apple.com/documentation/foundationmodels/generate-dynamic-game-content-with-guided-generation-and-tools](https://developer.apple.com/documentation/foundationmodels/generate-dynamic-game-content-with-guided-generation-and-tools)
* `Tool` (protocol)
  [https://developer.apple.com/documentation/foundationmodels/tool](https://developer.apple.com/documentation/foundationmodels/tool)

### Feedback

* `LanguageModelFeedback` (struct)
  [https://developer.apple.com/documentation/foundationmodels/languagemodelfeedback](https://developer.apple.com/documentation/foundationmodels/languagemodelfeedback)
