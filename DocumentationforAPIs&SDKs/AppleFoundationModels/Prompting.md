# Prompting an On-Device Foundation Model

Tailor prompts carefully to obtain effective results from an on-device model. These models are smaller than server frontier models and have tighter context windows, so prompt clarity and structure matter more.

## Overview

Many prompting techniques are designed for large server models with broad context and stronger reasoning. On-device models require more disciplined prompt engineering because of their smaller size and token limits.

To improve accuracy and reduce hallucinations:

* Use simple, clear instructions
* Keep prompts concise and specific
* Iterate based on observed outputs
* Reduce how much reasoning the model must perform
* Break complex tasks into smaller requests
* Add conditional logic carefully
* Use one-shot or few-shot examples when helpful
* Provide a dedicated reasoning field if structured output is required

Test prompts continuously during development and evaluate outputs for reliability and user experience.

---

## Core Prompt Design Principles

Prompt engineering involves shaping requests through wording, context, and formatting. It is an iterative process that depends on testing and refinement.

Prompts may also include conditional behavior. For example:

If the input is a question, answer directly.
If the input is a statement, ask a follow-up question.

---

## Keep Prompts Simple and Clear

On-device models have smaller context windows and fewer parameters. Long or indirect prompts reduce performance and increase confusion.

Good practices:

* Focus on one well-defined goal
* Use direct imperative verbs such as “List” or “Create”
* Assign a clear role to the model
* Use short, direct sentences
* State the task plainly
* Keep prompts within one to three paragraphs

Avoid:

* Multiple unrelated requests in one prompt
* Excess politeness or hedging language
* Passive voice
* Heavy jargon
* Prompts that are too vague
* Prompts that are overly long

### Example

Concise prompt:

Given a person’s home-decor transactions and search history, generate three relevant categories ranked by relevance. Then add two related categories not present in their history.

Indirect prompt:

The person’s input contains recent transactions and search history. The response should include relevant categories ordered by relevance, plus additional creative categories not already present.

---

## Use Role, Persona, and Tone

You can shape responses by assigning a role and persona.

Role describes the function. Persona describes the style or character.

Example:

You are an expert English teacher. Provide feedback on the sentence for clarity.

Tone can also be guided by writing style in the prompt itself.

Examples of personas:

* Senior software engineer mentoring junior developers
* Interior designer consulting a client
* Medieval scholar using lightly archaic language

You can also describe the end user:

The person is a first-grade student. Adjust feedback accordingly.

---

## Improve Instruction Following

Instruction following is the model’s ability to execute the prompt exactly.

If performance is weak:

* Improve clarity and directness
* Add emphasis words such as must or do not
* Repeat key instructions once near the end

Evaluate each change. Over-emphasis or excessive repetition can reduce reliability.

If needed, split a complex task into multiple simpler prompts.

---

## Reduce Reasoning Load

On-device models have limited reasoning depth. Help them by supplying structure.

Instead of a vague complex request, provide step guidance.

Example:

1. Choose four relevant furniture categories.
2. Recommend two additional categories.
3. Return an ordered list from most to least relevant.

If still unreliable, divide the workflow across multiple sessions so each step uses a fresh context window.

---

## Prefer Programmatic Logic Over Long Conditionals

Long conditional instructions inside prompts can confuse smaller models.

Instead of embedding many IF rules inside one prompt, build prompt text programmatically based on known inputs, then send only the relevant branch.

This reduces token usage and distraction.

---

## Use Few-Shot Examples

Few-shot prompting provides small input-output examples to guide format and style.

Keep examples:

* Short
* Simple
* Structurally consistent

Typical range is two to fifteen examples.

Complex or verbose examples may cause copying or hallucinated details.

Few-shot prompting pairs well with guided generation using defined data structures.

---

## Guided Generation with Structures

When generating structured data, define a schema type and guide the model to fill it.

Example structure:

```
struct NPC {
  name: String
  coffeeOrder: String
  imageDescription: String
}
```

Provide short example objects that match this format so the model learns the pattern.

---

## Handling Reasoning Output

Step-by-step reasoning prompts may leak extra text into structured outputs.

Add a dedicated reasoning field as the first property in your structure.

Example pattern:

* reasoningSteps: model places its plan here
* answer: final structured result only

Then instruct:

1. Begin with a plan
2. Show reasoning steps
3. Place the final result only in the answer field

If reasoning still fails, the task may exceed the model’s capacity.

---

## Feedback and Iteration

If behavior seems incorrect or inconsistent, submit feedback with:

* The exact prompt
* Observed issues
* Desired output

Use system feedback tools to help improve future model behavior.

---

## Related Components

* LanguageModelSession for model interactions
* Instructions to define behavior
* Prompt for user input
* Transcript for session history
* GenerationOptions for output control
