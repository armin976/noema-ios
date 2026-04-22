# Generating content and performing tasks with Foundation Models

Enhance the experience in your app by prompting an on-device large language model.

## Overview

The Foundation Models framework lets you tap into the on-device large models at the core of Apple Intelligence. You can enhance your app by using generative models to create content or perform tasks. The framework supports language understanding and generation based on model capabilities.

For design guidance, see Human Interface Guidelines → Technologies → Generative AI:
[https://developer.apple.com/design/human-interface-guidelines/generative-ai](https://developer.apple.com/design/human-interface-guidelines/generative-ai)

## Understand model capabilities

When considering features for your app, it helps to know what the on-device language model can do. The on-device model supports text generation and understanding that you can use to:

| Capability               | Prompt example                                                 |
| ------------------------ | -------------------------------------------------------------- |
| Summarize                | “Summarize this article.”                                      |
| Extract entities         | “List the people and places mentioned in this text.”           |
| Understand text          | “What happens to the dog in this story?”                       |
| Refine or edit text      | “Change this story to be in second person.”                    |
| Classify or judge text   | “Is this text relevant to the topic ‘Swift’?”                  |
| Compose creative writing | “Generate a short bedtime story about a fox.”                  |
| Generate tags from text  | “Provide two tags that describe the main topics of this text.” |
| Generate game dialog     | “Respond in the voice of a friendly inn keeper.”               |

The on-device language model may not be suitable for handling all requests, like:

| Capabilities to avoid     | Prompt example                                                 |
| ------------------------- | -------------------------------------------------------------- |
| Do basic math             | “How many b’s are there in bagel?”                             |
| Create code               | “Generate a Swift navigation list.”                            |
| Perform logical reasoning | “If I’m at Apple Park facing Canada, what direction is Texas?” |

The model can complete complex generative tasks when you use guided generation or tool calling. For more on
