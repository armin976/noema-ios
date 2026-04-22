---
title: MLBatchProvider
description: An interface that represents a collection of feature providers.
source: https://developer.apple.com/documentation/coreml/mlbatchprovider
timestamp: 2026-03-08T17:54:15.472Z
---

**Navigation:** [Coreml](/documentation/coreml)

**Protocol**

# MLBatchProvider

**Available on:** iOS 12.0+, iPadOS 12.0+, Mac Catalyst 13.1+, macOS 10.14+, tvOS 12.0+, visionOS 1.0+, watchOS 5.0+

> An interface that represents a collection of feature providers.

```swift
protocol MLBatchProvider
```

## Overview

Similar to the [MLFeature Provider](/documentation/coreml/mlfeatureprovider), this interface allows you to define your own batch provider. If you collect your data asynchronously or it is memory intensive, implement this protocol on your data structure to optimize performance with batch processing.

## Conforming Types

- [MLArrayBatchProvider](/documentation/coreml/mlarraybatchprovider)

## Accessing values

- [features(at:)](/documentation/coreml/mlbatchprovider/features(at:)) Returns the feature provider at the given index.
- [count](/documentation/coreml/mlbatchprovider/count) The number of feature providers in this batch.

## Model inputs and outputs

- [Making Predictions with a Sequence of Inputs](/documentation/coreml/making-predictions-with-a-sequence-of-inputs)
- [MLFeatureValue](/documentation/coreml/mlfeaturevalue)
- [MLSendableFeatureValue](/documentation/coreml/mlsendablefeaturevalue)
- [MLFeatureProvider](/documentation/coreml/mlfeatureprovider)
- [MLDictionaryFeatureProvider](/documentation/coreml/mldictionaryfeatureprovider)
- [MLArrayBatchProvider](/documentation/coreml/mlarraybatchprovider)
- [MLModelAsset](/documentation/coreml/mlmodelasset)

---

*Extracted by [sosumi.ai](https://sosumi.ai) - Making Apple docs AI-readable.*
*This is unofficial content. All documentation belongs to Apple Inc.*