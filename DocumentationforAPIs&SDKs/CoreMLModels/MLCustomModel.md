---
title: MLCustomModel
description: An interface that defines the behavior of a custom model.
source: https://developer.apple.com/documentation/coreml/mlcustommodel
timestamp: 2026-03-08T17:52:17.007Z
---

**Navigation:** [Coreml](/documentation/coreml)

**Protocol**

# MLCustomModel

**Available on:** iOS 12.0+, iPadOS 12.0+, Mac Catalyst 13.1+, macOS 10.14+, tvOS 12.0+, visionOS 1.0+, watchOS 5.0+

> An interface that defines the behavior of a custom model.

```swift
protocol MLCustomModel
```

## Overview

To integrate your custom model with Core ML, adopt the [MLCustom Model](/documentation/coreml/mlcustommodel) protocol in the implementation of your custom model. If you use a Swift class for your custom implementation, make it accessible to Core ML by using the `@objc(`*name*`)` attribute.

```swift
@objc(MyCustomModel)
class MyCustomModel: NSObject, MLCustomModel {
  ...
}
```

This defines the Objective-C name for the class, which Core ML needs to access your custom class’s implementation.

## Creating the model

- [init(modelDescription:parameters:)](/documentation/coreml/mlcustommodel/init(modeldescription:parameters:)) Creates a custom model with the given description and parameters.

## Making predictions

- [prediction(from:options:)](/documentation/coreml/mlcustommodel/prediction(from:options:)) Predicts output values from the given input features.
- [predictions(from:options:)](/documentation/coreml/mlcustommodel/predictions(from:options:)) Predicts output values from the given batch of input features.

---

*Extracted by [sosumi.ai](https://sosumi.ai) - Making Apple docs AI-readable.*
*This is unofficial content. All documentation belongs to Apple Inc.*