---
title: MLSendableFeatureValue
description: A sendable feature value.
source: https://developer.apple.com/documentation/coreml/mlsendablefeaturevalue
timestamp: 2026-03-08T17:53:22.538Z
---

**Navigation:** [Coreml](/documentation/coreml)

**Structure**

# MLSendableFeatureValue

**Available on:** iOS 18.0+, iPadOS 18.0+, Mac Catalyst 18.0+, macOS 15.0+, tvOS 18.0+, visionOS 2.0+, watchOS 11.0+

> A sendable feature value.

```swift
struct MLSendableFeatureValue
```

## Overview

This version of feature value is similar to [MLFeature Value](/documentation/coreml/mlfeaturevalue) but it can be passed across concurrency domains. Once in the target concurrency domain, you can then convert it to a [MLFeature Value](/documentation/coreml/mlfeaturevalue).

## Conforms To

- [Copyable](/documentation/Swift/Copyable)
- [CustomDebugStringConvertible](/documentation/Swift/CustomDebugStringConvertible)
- [Equatable](/documentation/Swift/Equatable)
- [Escapable](/documentation/Swift/Escapable)
- [Sendable](/documentation/Swift/Sendable)
- [SendableMetatype](/documentation/Swift/SendableMetatype)

## Creating a sendable feature value

- [init(_:)](/documentation/coreml/mlsendablefeaturevalue/init(_:)) Creates a feature value containing a double-precision floating-point value.
- [init(undefined:)](/documentation/coreml/mlsendablefeaturevalue/init(undefined:)) Creates an undefined feature value of a specific type.

## Accessing the values

- [doubleValue](/documentation/coreml/mlsendablefeaturevalue/doublevalue) The double-precision floating-point value, if the contained value is a double.
- [float16Value](/documentation/coreml/mlsendablefeaturevalue/float16value) The 16-bit floating-point value, if the contained value is a 16-bit float.
- [floatValue](/documentation/coreml/mlsendablefeaturevalue/floatvalue) The single-precision floating-point value, if the contained value is a float.
- [integerDictionaryValue](/documentation/coreml/mlsendablefeaturevalue/integerdictionaryvalue) The integer dictionary value, if the contained value is a dictionary of integers to numbers.
- [integerValue](/documentation/coreml/mlsendablefeaturevalue/integervalue) The integer value, if the contained value is an integer.
- [isScalar](/documentation/coreml/mlsendablefeaturevalue/isscalar) A Boolean value indicating whether the value is a single number.
- [isShapedArray](/documentation/coreml/mlsendablefeaturevalue/isshapedarray) A Boolean value indicating whether the value is a shaped array.
- [isUndefined](/documentation/coreml/mlsendablefeaturevalue/isundefined) A Boolean value indicating whether the value is missing or undefined.
- [stringArrayValue](/documentation/coreml/mlsendablefeaturevalue/stringarrayvalue) The string array value, if the contained value is an array of string.
- [stringDictionaryValue](/documentation/coreml/mlsendablefeaturevalue/stringdictionaryvalue) The string dictionary value, if the contained value is a dictionary of strings to numbers.
- [stringValue](/documentation/coreml/mlsendablefeaturevalue/stringvalue) The string value, if the contained value is a string.
- [type](/documentation/coreml/mlsendablefeaturevalue/type) The type of value.

## Getting the shaped array value

- [shapedArrayValue(of:)](/documentation/coreml/mlsendablefeaturevalue/shapedarrayvalue(of:)) Returns the shaped array value, if the contained value is a shaped array of the specified type.

## Model inputs and outputs

- [Making Predictions with a Sequence of Inputs](/documentation/coreml/making-predictions-with-a-sequence-of-inputs)
- [MLFeatureValue](/documentation/coreml/mlfeaturevalue)
- [MLFeatureProvider](/documentation/coreml/mlfeatureprovider)
- [MLDictionaryFeatureProvider](/documentation/coreml/mldictionaryfeatureprovider)
- [MLBatchProvider](/documentation/coreml/mlbatchprovider)
- [MLArrayBatchProvider](/documentation/coreml/mlarraybatchprovider)
- [MLModelAsset](/documentation/coreml/mlmodelasset)

---

*Extracted by [sosumi.ai](https://sosumi.ai) - Making Apple docs AI-readable.*
*This is unofficial content. All documentation belongs to Apple Inc.*