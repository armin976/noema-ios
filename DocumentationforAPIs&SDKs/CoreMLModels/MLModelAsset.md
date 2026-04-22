---
title: MLModelAsset
description: A wrapper for a Core ML model that can be loaded from a file.
source: https://developer.apple.com/documentation/coreml/mlmodelasset
timestamp: 2026-03-08T17:55:24.662Z
---

**Navigation:** [Coreml](/documentation/coreml)

**Class**

# MLModelAsset

**Available on:** iOS 11.0+, iPadOS 11.0+, Mac Catalyst 13.1+, macOS 10.13+, tvOS 11.0+, visionOS 1.0+, watchOS 4.0+

> A wrapper for a Core ML model that can be loaded from a file.

```swift
class MLModelAsset
```

## Overview

Use this class to load a Core ML model from a file. The model is loaded lazily, meaning that the model file is not read from disk until the model is used for the first time.

## Inherits From

- [NSObject](/documentation/ObjectiveC/NSObject-swift.class)

## Conforms To

- [CVarArg](/documentation/Swift/CVarArg)
- [CustomDebugStringConvertible](/documentation/Swift/CustomDebugStringConvertible)
- [CustomStringConvertible](/documentation/Swift/CustomStringConvertible)
- [Equatable](/documentation/Swift/Equatable)
- [Hashable](/documentation/Swift/Hashable)
- [NSCoding](/documentation/Foundation/NSCoding)
- [NSFastEnumeration](/documentation/Foundation/NSFastEnumeration)
- [NSObjectProtocol](/documentation/ObjectiveC/NSObjectProtocol)
- [NSSecureCoding](/documentation/Foundation/NSSecureCoding)

## Creating the model asset

- [init(named:)](/documentation/coreml/mlmodelasset/init(named:)) Creates a model asset from a model file in the app bundle.
- [init(contentsOf:)](/documentation/coreml/mlmodelasset/init(contentsof:)) Creates a model asset from a model file at a given URL.

## Accessing the model

- [model](/documentation/coreml/mlmodelasset/model) The loaded model.

## Model inputs and outputs

- [Making Predictions with a Sequence of Inputs](/documentation/coreml/making-predictions-with-a-sequence-of-inputs)
- [MLFeatureValue](/documentation/coreml/mlfeaturevalue)
- [MLSendableFeatureValue](/documentation/coreml/mlsendablefeaturevalue)
- [MLFeatureProvider](/documentation/coreml/mlfeatureprovider)
- [MLDictionaryFeatureProvider](/documentation/coreml/mldictionaryfeatureprovider)
- [MLArrayBatchProvider](/documentation/coreml/mlarraybatchprovider)
- [MLBatchProvider](/documentation/coreml/mlbatchprovider)

---

*Extracted by [sosumi.ai](https://sosumi.ai) - Making Apple docs AI-readable.*
*This is unofficial content. All documentation belongs to Apple Inc.*