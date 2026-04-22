---
title: Getting a Core ML Model
description: Obtain a Core ML model to use in your app.
source: https://developer.apple.com/documentation/coreml/getting-a-core-ml-model
timestamp: 2026-03-08T17:49:56.741Z
---

**Navigation:** [Coreml](/documentation/coreml)

**Article**

# Getting a Core ML Model

> Obtain a Core ML model to use in your app.

## Overview

Core ML supports a variety of machine learning models, including neural networks, tree ensembles, support vector machines, and generalized linear models. Core ML requires the Core ML model format (models with a `.mlmodel` file extension).

Using [Create ML](/documentation/CreateML) and your own data, you can train custom models to perform tasks like recognizing images, extracting meaning from text, or finding relationships between numerical values. Models trained using Create ML are in the Core ML model format and are ready to use in your app.

Apple also provides several popular, open source [](https://developer.apple.com/machine-learning/models/) that are already in the Core ML model format. You can download these models and start using them in your app.

Additionally, various research groups and universities publish their models and training data, which may not be in the Core ML model format. Use [](https://coremltools.readme.io/) to convert these models to use in your app.

## Core ML models

- [Updating a Model File to a Model Package](/documentation/coreml/updating-a-model-file-to-a-model-package)
- [Integrating a Core ML Model into Your App](/documentation/coreml/integrating-a-core-ml-model-into-your-app)
- [MLModel](/documentation/coreml/mlmodel)
- [Model Customization](/documentation/coreml/model-customization)
- [Model Personalization](/documentation/coreml/model-personalization)

---

*Extracted by [sosumi.ai](https://sosumi.ai) - Making Apple docs AI-readable.*
*This is unofficial content. All documentation belongs to Apple Inc.*