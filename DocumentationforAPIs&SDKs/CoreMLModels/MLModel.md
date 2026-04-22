---
title: MLModel
description: An encapsulation of all the details of your machine learning model.
source: https://developer.apple.com/documentation/coreml/mlmodel
timestamp: 2026-03-08T17:50:52.274Z
---

**Navigation:** [Coreml](/documentation/coreml)

**Class**

# MLModel

**Available on:** iOS 11.0+, iPadOS 11.0+, Mac Catalyst 13.1+, macOS 10.13+, tvOS 11.0+, visionOS 1.0+, watchOS 4.0+

> An encapsulation of all the details of your machine learning model.

```swift
class MLModel
```

## Overview

[MLModel](/documentation/coreml/mlmodel) encapsulates a model’s prediction methods, configuration, and model description.

In most cases, you can use Core ML without accessing the [MLModel](/documentation/coreml/mlmodel) class directly. Instead, use the programmer-friendly wrapper class that Xcode automatically generates when you add a model (see [integrating-a-core-ml-model-into-your](/documentation/coreml/integrating-a-core-ml-model-into-your-app)). If your app needs the [MLModel](/documentation/coreml/mlmodel) interface, use the wrapper class’s `model` property.

With the [MLModel](/documentation/coreml/mlmodel) interface, you can:

- Make a prediction with your app’s custom [MLFeature Provider](/documentation/coreml/mlfeatureprovider) by calling [prediction(from:)](/documentation/coreml/mlmodel/prediction(from:)-9y2aa) or [prediction(from:options:)](/documentation/coreml/mlmodel/prediction(from:options:)-81mr6).
- Make multiple predictions with your app’s custom [MLBatch Provider](/documentation/coreml/mlbatchprovider) by calling [predictions(fromBatch:)](/documentation/coreml/mlmodel/predictions(frombatch:)) or [predictions(from:options:)](/documentation/coreml/mlmodel/predictions(from:options:)).
- Inspect your model’s [metadata](/documentation/coreml/mlmodeldescription/metadata) and [MLFeature Description](/documentation/coreml/mlfeaturedescription) instances through [model Description](/documentation/coreml/mlmodel/modeldescription).

If your app downloads and compiles a model on the user’s device, you must use the [MLModel](/documentation/coreml/mlmodel) class directly to make predictions. See [downloading-and-compiling-a-model-on-the-user-s](/documentation/coreml/downloading-and-compiling-a-model-on-the-user-s-device).

> [!IMPORTANT]
> Use an [MLModel](/documentation/coreml/mlmodel) instance on one thread or one dispatch queue at a time. Do this by either serializing method calls to the model, or by creating a separate model instance for each thread and dispatch queue.

## Inherits From

- [NSObject](/documentation/ObjectiveC/NSObject-swift.class)

## Conforms To

- [CVarArg](/documentation/Swift/CVarArg)
- [CustomDebugStringConvertible](/documentation/Swift/CustomDebugStringConvertible)
- [CustomStringConvertible](/documentation/Swift/CustomStringConvertible)
- [Equatable](/documentation/Swift/Equatable)
- [Hashable](/documentation/Swift/Hashable)
- [NSObjectProtocol](/documentation/ObjectiveC/NSObjectProtocol)

## Loading a model

- [load(contentsOf:configuration:)](/documentation/coreml/mlmodel/load(contentsof:configuration:)) Construct a model asynchronously from a compiled model asset.
- [load(_:configuration:completionHandler:)](/documentation/coreml/mlmodel/load(_:configuration:completionhandler:)) Construct a model asynchronously from a compiled model asset.
- [load(contentsOf:configuration:completionHandler:)](/documentation/coreml/mlmodel/load(contentsof:configuration:completionhandler:)) Creates a Core ML model instance asynchronously from a compiled model file, a custom configuration, and a completion handler.
- [init(contentsOf:)](/documentation/coreml/mlmodel/init(contentsof:)) Creates a Core ML model instance from a compiled model file.
- [init(contentsOf:configuration:)](/documentation/coreml/mlmodel/init(contentsof:configuration:)) Creates a Core ML model instance from a compiled model file and a custom configuration.
- [init(contentsOfURL:)](/documentation/coreml/mlmodel/init(contentsofurl:))
- [init(contentsOfURL:configuration:)](/documentation/coreml/mlmodel/init(contentsofurl:configuration:))

## Compiling a model

- [compileModel(at:)](/documentation/coreml/mlmodel/compilemodel(at:))
- [compileModel(at:completionHandler:)](/documentation/coreml/mlmodel/compilemodel(at:completionhandler:)) Compile a model for a device.

## Making predictions

- [prediction(from:)](/documentation/coreml/mlmodel/prediction(from:))
- [prediction(from:options:)](/documentation/coreml/mlmodel/prediction(from:options:))
- [predictions(fromBatch:)](/documentation/coreml/mlmodel/predictions(frombatch:)) Generates predictions for each input feature provider within the batch provider.
- [predictions(from:options:)](/documentation/coreml/mlmodel/predictions(from:options:)) Generates a prediction for each input feature provider within the batch provider using the prediction options.
- [prediction(from:using:)](/documentation/coreml/mlmodel/prediction(from:using:))
- [prediction(from:using:options:)](/documentation/coreml/mlmodel/prediction(from:using:options:))
- [MLPredictionOptions](/documentation/coreml/mlpredictionoptions) The options available when making a prediction.

## Making state

- [makeState()](/documentation/coreml/mlmodel/makestate()) Creates a new state object.

## Inspecting a model

- [availableComputeDevices](/documentation/coreml/mlmodel/availablecomputedevices-6klyt) The list of available compute devices that the model’s prediction methods use.
- [configuration](/documentation/coreml/mlmodel/configuration) The configuration of the model set during initialization.
- [modelDescription](/documentation/coreml/mlmodel/modeldescription) Model information you use at runtime during development, which Xcode also displays in its Core ML model editor view.
- [MLModelDescription](/documentation/coreml/mlmodeldescription) Information about a model, primarily the input and output format for each feature the model expects, and optional metadata.
- [parameterValue(for:)](/documentation/coreml/mlmodel/parametervalue(for:)) Returns a model parameter value for a key.
- [MLParameterKey](/documentation/coreml/mlparameterkey) The keys for the parameter dictionary in a model configuration or a model update context.

## Supporting types

- [MLModelConfiguration](/documentation/coreml/mlmodelconfiguration) The settings for creating or updating a machine learning model.
- [MLOptimizationHints](/documentation/coreml/mloptimizationhints-swift.struct)
- [MLKey](/documentation/coreml/mlkey) An abstract base class for machine learning key types.

## Core ML models

- [Getting a Core ML Model](/documentation/coreml/getting-a-core-ml-model)
- [Updating a Model File to a Model Package](/documentation/coreml/updating-a-model-file-to-a-model-package)
- [Integrating a Core ML Model into Your App](/documentation/coreml/integrating-a-core-ml-model-into-your-app)
- [Model Customization](/documentation/coreml/model-customization)
- [Model Personalization](/documentation/coreml/model-personalization)

---

*Extracted by [sosumi.ai](https://sosumi.ai) - Making Apple docs AI-readable.*
*This is unofficial content. All documentation belongs to Apple Inc.*