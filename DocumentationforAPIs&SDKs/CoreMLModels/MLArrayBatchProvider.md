---
title: MLArrayBatchProvider
description: A convenience wrapper for an array of feature providers.
source: https://developer.apple.com/documentation/coreml/mlarraybatchprovider
timestamp: 2026-03-08T17:54:52.669Z
---

**Navigation:** [Coreml](/documentation/coreml)

**Class**

# MLArrayBatchProvider

**Available on:** iOS 12.0+, iPadOS 12.0+, Mac Catalyst 13.1+, macOS 10.14+, tvOS 12.0+, visionOS 1.0+, watchOS 5.0+

> A convenience wrapper for an array of feature providers.

```swift
class MLArrayBatchProvider
```

## Overview

This class is a convenience wrapper for an array of [MLFeature Provider](/documentation/coreml/mlfeatureprovider) instances. It is a convenience interface, saving you the trouble of iterating through the array to assign all of its values.

## Inherits From

- [NSObject](/documentation/ObjectiveC/NSObject-swift.class)

## Conforms To

- [CVarArg](/documentation/Swift/CVarArg)
- [CustomDebugStringConvertible](/documentation/Swift/CustomDebugStringConvertible)
- [CustomStringConvertible](/documentation/Swift/CustomStringConvertible)
- [Equatable](/documentation/Swift/Equatable)
- [Hashable](/documentation/Swift/Hashable)
- [MLBatchProvider](/documentation/coreml/mlbatchprovider)
- [NSCoding](/documentation/Foundation/NSCoding)
- [NSFastEnumeration](/documentation/Foundation/NSFastEnumeration)
- [NSObjectProtocol](/documentation/ObjectiveC/NSObjectProtocol)
- [NSSecureCoding](/documentation/Foundation/NSSecureCoding)

## Creating the provider

- [init(featureProviders:)](/documentation/coreml/mlarraybatchprovider/init(featureproviders:)) Creates the batch provider based on an array of feature providers.

## Accessing the features

- [subscript(_:)](/documentation/coreml/mlarraybatchprovider/subscript(_:)) Subscript interface for the batch provider to pass through to the array.
- [featureProviders](/documentation/coreml/mlarraybatchprovider/featureproviders) The backing array of feature providers.

## Model inputs and outputs

- [Making Predictions with a Sequence of Inputs](/documentation/coreml/making-predictions-with-a-sequence-of-inputs)
- [MLFeatureValue](/documentation/coreml/mlfeaturevalue)
- [MLSendableFeatureValue](/documentation/coreml/mlsendablefeaturevalue)
- [MLFeatureProvider](/documentation/coreml/mlfeatureprovider)
- [MLDictionaryFeatureProvider](/documentation/coreml/mldictionaryfeatureprovider)
- [MLBatchProvider](/documentation/coreml/mlbatchprovider)
- [MLModelAsset](/documentation/coreml/mlmodelasset)

---

*Extracted by [sosumi.ai](https://sosumi.ai) - Making Apple docs AI-readable.*
*This is unofficial content. All documentation belongs to Apple Inc.*
