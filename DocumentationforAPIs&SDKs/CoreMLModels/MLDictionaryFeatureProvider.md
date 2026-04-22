---
title: MLDictionaryFeatureProvider
description: A convenience wrapper for the given dictionary of data.
source: https://developer.apple.com/documentation/coreml/mldictionaryfeatureprovider
timestamp: 2026-03-08T17:53:48.937Z
---

**Navigation:** [Coreml](/documentation/coreml)

**Class**

# MLDictionaryFeatureProvider

**Available on:** iOS 11.0+, iPadOS 11.0+, Mac Catalyst 13.1+, macOS 10.13+, tvOS 11.0+, visionOS 1.0+, watchOS 4.0+

> A convenience wrapper for the given dictionary of data.

```swift
class MLDictionaryFeatureProvider
```

## Overview

If your input data is stored in a dictionary, consider this type of [MLFeature Provider](/documentation/coreml/mlfeatureprovider) that is backed by a dictionary. It is a convenience interface, saving you the trouble of iterating through the dictionary to assign all of its values.

## Inherits From

- [NSObject](/documentation/ObjectiveC/NSObject-swift.class)

## Conforms To

- [CVarArg](/documentation/Swift/CVarArg)
- [CustomDebugStringConvertible](/documentation/Swift/CustomDebugStringConvertible)
- [CustomStringConvertible](/documentation/Swift/CustomStringConvertible)
- [Equatable](/documentation/Swift/Equatable)
- [Hashable](/documentation/Swift/Hashable)
- [MLFeatureProvider](/documentation/coreml/mlfeatureprovider)
- [NSCoding](/documentation/Foundation/NSCoding)
- [NSFastEnumeration](/documentation/Foundation/NSFastEnumeration)
- [NSObjectProtocol](/documentation/ObjectiveC/NSObjectProtocol)
- [NSSecureCoding](/documentation/Foundation/NSSecureCoding)

## Creating the provider

- [init(dictionary:)](/documentation/coreml/mldictionaryfeatureprovider/init(dictionary:)) Creates the feature provider based on a dictionary.

## Accessing the features

- [subscript(_:)](/documentation/coreml/mldictionaryfeatureprovider/subscript(_:)) Subscript interface for the feature provider to pass through to the dictionary.
- [dictionary](/documentation/coreml/mldictionaryfeatureprovider/dictionary) The backing dictionary.

## Model inputs and outputs

- [Making Predictions with a Sequence of Inputs](/documentation/coreml/making-predictions-with-a-sequence-of-inputs)
- [MLFeatureValue](/documentation/coreml/mlfeaturevalue)
- [MLSendableFeatureValue](/documentation/coreml/mlsendablefeaturevalue)
- [MLFeatureProvider](/documentation/coreml/mlfeatureprovider)
- [MLBatchProvider](/documentation/coreml/mlbatchprovider)
- [MLArrayBatchProvider](/documentation/coreml/mlarraybatchprovider)
- [MLModelAsset](/documentation/coreml/mlmodelasset)

---

*Extracted by [sosumi.ai](https://sosumi.ai) - Making Apple docs AI-readable.*
*This is unofficial content. All documentation belongs to Apple Inc.*