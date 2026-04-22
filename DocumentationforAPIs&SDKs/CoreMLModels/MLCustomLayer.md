---
title: MLCustomLayer
description: An interface that defines the behavior of a custom layer in your neural network model.
source: https://developer.apple.com/documentation/coreml/mlcustomlayer
timestamp: 2026-03-08T17:52:04.403Z
---

**Navigation:** [Coreml](/documentation/coreml)

**Protocol**

# MLCustomLayer

**Available on:** iOS 11.2+, iPadOS 11.2+, Mac Catalyst 13.1+, macOS 10.13.2+, tvOS 11.2+, visionOS 1.0+, watchOS 4.2+

> An interface that defines the behavior of a custom layer in your neural network model.

```swift
protocol MLCustomLayer
```

## Overview

You use the [MLCustom Layer](/documentation/coreml/mlcustomlayer) protocol to define the behavior of your own neural network layers in Core ML models. You can deploy novel or proprietary models on your own release schedule. Custom layers also provide a mechanism for pre- or post-processing during model evaluation.

## Creating a layer

- [init(parameters:)](/documentation/coreml/mlcustomlayer/init(parameters:)) Initializes the custom layer implementation.

## Integrating a layer

- [setWeightData(_:)](/documentation/coreml/mlcustomlayer/setweightdata(_:)) Assigns the weights for the connections within the layer.
- [outputShapes(forInputShapes:)](/documentation/coreml/mlcustomlayer/outputshapes(forinputshapes:)) Calculates the shapes of the output of this layer for the given input shapes.

## Evaluating a layer

- [evaluate(inputs:outputs:)](/documentation/coreml/mlcustomlayer/evaluate(inputs:outputs:)) Evaluates the custom layer with the given inputs.
- [encode(commandBuffer:inputs:outputs:)](/documentation/coreml/mlcustomlayer/encode(commandbuffer:inputs:outputs:)) Encodes GPU commands to evaluate the custom layer.

## Custom model layers

- [Creating and Integrating a Model with Custom Layers](/documentation/coreml/creating-and-integrating-a-model-with-custom-layers)

---

*Extracted by [sosumi.ai](https://sosumi.ai) - Making Apple docs AI-readable.*
*This is unofficial content. All documentation belongs to Apple Inc.*