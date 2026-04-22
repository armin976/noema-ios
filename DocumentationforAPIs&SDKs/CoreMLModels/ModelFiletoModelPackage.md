---
title: Updating a Model File to a Model Package
description: Convert a Core ML model file into a model package in Xcode.
source: https://developer.apple.com/documentation/coreml/updating-a-model-file-to-a-model-package
timestamp: 2026-03-08T17:50:18.010Z
---

**Navigation:** [Coreml](/documentation/coreml)

**Article**

# Updating a Model File to a Model Package

> Convert a Core ML model file into a model package in Xcode.

## Overview

A Core ML model package is a file-system structure that can store a model in separate files, similar to an app bundle. Model packages offer more flexibility and extensibility than Core ML model files, including editable metadata and separation of a model’s architecture from its weights and biases. Update your model file to a model package by converting the model in Xcode.

Open or select a Core ML model in Xcode and update it to an ML package by either clicking the Edit button or the Update to Model Package button in the Utilities tab.

![Screenshot of a model window in Xcode highlighting the Edit button in the window’s upper-right corner, and the Model Update section in the window’s Utility tab that includes an “Update to Model Package” button.](https://docs-assets.developer.apple.com/published/cef4d987e8b802b35bac75a347543bd5/media-3846185%402x.png)

Xcode presents a confirmation dialog before it converts the model to the ML package format. By default, Xcode moves the original model file to the Trash. You can keep your original model file by deselecting the checkbox in the Xcode dialog. Click Update and Edit when you’re ready to convert the model to a package.

Once Xcode finishes converting the model, it opens the model’s General tab, where you can edit any of the metadata text fields, including Description, Author, and License.

![Screenshot of a model window highlighting the metadata, which shows the user currently editing the License text field.](https://docs-assets.developer.apple.com/published/550d8743bf5e04f9f7ed75d63aae605d/media-3846183%402x.png)

You can also add a new metadata field in an ML package by entering a new property name and value in the Additional Metadata section.

## Core ML models

- [Getting a Core ML Model](/documentation/coreml/getting-a-core-ml-model)
- [Integrating a Core ML Model into Your App](/documentation/coreml/integrating-a-core-ml-model-into-your-app)
- [MLModel](/documentation/coreml/mlmodel)
- [Model Customization](/documentation/coreml/model-customization)
- [Model Personalization](/documentation/coreml/model-personalization)

---

*Extracted by [sosumi.ai](https://sosumi.ai) - Making Apple docs AI-readable.*
*This is unofficial content. All documentation belongs to Apple Inc.*