---
title: MLFeatureValue
description: A generic wrapper around an underlying value and the value’s type.
source: https://developer.apple.com/documentation/coreml/mlfeaturevalue
timestamp: 2026-03-08T17:53:08.740Z
---

**Navigation:** [Coreml](/documentation/coreml)

**Class**

# MLFeatureValue

**Available on:** iOS 11.0+, iPadOS 11.0+, Mac Catalyst 13.1+, macOS 10.13+, tvOS 11.0+, visionOS 1.0+, watchOS 4.0+

> A generic wrapper around an underlying value and the value’s type.

```swift
class MLFeatureValue
```

## Overview

A Core ML *feature value* wraps an underlying value and bundles it with that value’s type, which is one of the types that [MLFeature Type](/documentation/coreml/mlfeaturetype) defines. Apps typically access feature values indirectly by using the methods in the wrapper class Xcode automatically generates for Core ML model files.

If your app accesses an [MLModel](/documentation/coreml/mlmodel) directly, it must create and consume [MLFeature Provider](/documentation/coreml/mlfeatureprovider) instances. For each prediction, Core ML accepts a feature provider for its inputs, and generates a separate feature provider for its outputs. The input feature provider contains one `MLFeatureValue` instance per input, and the output feature provider contains one per output. See [MLFeature Description](/documentation/coreml/mlfeaturedescription) for more information about the model input and output features.

## Inherits From

- [NSObject](/documentation/ObjectiveC/NSObject-swift.class)

## Conforms To

- [CVarArg](/documentation/Swift/CVarArg)
- [CustomDebugStringConvertible](/documentation/Swift/CustomDebugStringConvertible)
- [CustomStringConvertible](/documentation/Swift/CustomStringConvertible)
- [Equatable](/documentation/Swift/Equatable)
- [Hashable](/documentation/Swift/Hashable)
- [NSCoding](/documentation/Foundation/NSCoding)
- [NSCopying](/documentation/Foundation/NSCopying)
- [NSObjectProtocol](/documentation/ObjectiveC/NSObjectProtocol)
- [NSSecureCoding](/documentation/Foundation/NSSecureCoding)

## Creating a feature value

- [init(_:)](/documentation/coreml/mlfeaturevalue/init(_:)) Creates a feature value from a sendable feature value.

## Creating numeric feature values

- [init(int64:)](/documentation/coreml/mlfeaturevalue/init(int64:)) Creates a feature value that contains an integer.
- [init(double:)](/documentation/coreml/mlfeaturevalue/init(double:)) Creates a feature value that contains a double.

## Creating string feature values

- [init(string:)](/documentation/coreml/mlfeaturevalue/init(string:)) Creates a feature value that contains a string.

## Creating multidimensional feature values

- [init(multiArray:)](/documentation/coreml/mlfeaturevalue/init(multiarray:)) Creates a feature value that contains a multidimensional array.
- [init(shapedArray:)](/documentation/coreml/mlfeaturevalue/init(shapedarray:)) Creates a feature value that contains a shaped array.

## Creating collection feature values

- [init(dictionary:)](/documentation/coreml/mlfeaturevalue/init(dictionary:)) Creates a feature value that contains a dictionary of numbers.
- [init(sequence:)](/documentation/coreml/mlfeaturevalue/init(sequence:)) Creates a feature value that contains a sequence.

## Creating image feature values

- [init(pixelBuffer:)](/documentation/coreml/mlfeaturevalue/init(pixelbuffer:)) Creates a feature value that contains an image from a pixel buffer.
- [init(CGImage:pixelsWide:pixelsHigh:pixelFormatType:options:)](/documentation/coreml/mlfeaturevalue/init(cgimage:pixelswide:pixelshigh:pixelformattype:options:)-2zg43) Creates a feature value that contains an image defined by a core graphics image and its size and pixel format.
- [init(CGImage:orientation:pixelsWide:pixelsHigh:pixelFormatType:options:)](/documentation/coreml/mlfeaturevalue/init(cgimage:orientation:pixelswide:pixelshigh:pixelformattype:options:)-4nme0) Creates a feature value that contains an image defined by a core graphics image and its orientation, size, and pixel format.
- [init(CGImage:constraint:options:)](/documentation/coreml/mlfeaturevalue/init(cgimage:constraint:options:)-1j00l) Creates a feature value that contains an image defined by a core graphics image and a constraint.
- [init(CGImage:orientation:constraint:options:)](/documentation/coreml/mlfeaturevalue/init(cgimage:orientation:constraint:options:)-87vk0) Creates a feature value that contains an image defined by a core graphics image, an orientation, and a constraint.
- [init(imageAtURL:pixelsWide:pixelsHigh:pixelFormatType:options:)](/documentation/coreml/mlfeaturevalue/init(imageaturl:pixelswide:pixelshigh:pixelformattype:options:)) Creates a feature value that contains an image defined by an image URL and the image’s size and pixel format.
- [init(imageAtURL:orientation:pixelsWide:pixelsHigh:pixelFormatType:options:)](/documentation/coreml/mlfeaturevalue/init(imageaturl:orientation:pixelswide:pixelshigh:pixelformattype:options:)) Creates a feature value that contains an image defined by an image URL and the image’s orientation, size, and pixel format.
- [init(imageAtURL:constraint:options:)](/documentation/coreml/mlfeaturevalue/init(imageaturl:constraint:options:)) Creates a feature value that contains an image defined by an image URL and a constraint.
- [init(imageAtURL:orientation:constraint:options:)](/documentation/coreml/mlfeaturevalue/init(imageaturl:orientation:constraint:options:)) Creates a feature value that contains an image defined by an image URL, an orientation, and a constraint.
- [MLImageConstraint](/documentation/coreml/mlimageconstraint) The width, height, and pixel format constraints of an image feature.
- [MLFeatureValue.ImageOption](/documentation/coreml/mlfeaturevalue/imageoption) The initializer options you use to crop and scale an image when creating an image feature value.

## Creating undefined feature values

- [init(undefined:)](/documentation/coreml/mlfeaturevalue/init(undefined:)) Creates a feature value with a type that represents an undefined or missing value.

## Accessing the feature’s type

- [type](/documentation/coreml/mlfeaturevalue/type) The type of the feature value.

## Accessing the feature’s value

- [isUndefined](/documentation/coreml/mlfeaturevalue/isundefined) A Boolean value that indicates whether the feature value is undefined or missing.
- [int64Value](/documentation/coreml/mlfeaturevalue/int64value) The underlying integer of the feature value.
- [doubleValue](/documentation/coreml/mlfeaturevalue/doublevalue) The underlying double of the feature value.
- [stringValue](/documentation/coreml/mlfeaturevalue/stringvalue) The underlying string of the feature value.
- [imageBufferValue](/documentation/coreml/mlfeaturevalue/imagebuffervalue) The underlying image of the feature value as a pixel buffer.
- [shapedArrayValue(of:)](/documentation/coreml/mlfeaturevalue/shapedarrayvalue(of:)) Returns the underlying shaped array of the feature value.
- [multiArrayValue](/documentation/coreml/mlfeaturevalue/multiarrayvalue) The underlying multiarray of the feature value.
- [sequenceValue](/documentation/coreml/mlfeaturevalue/sequencevalue) The underlying sequence of the feature value.
- [dictionaryValue](/documentation/coreml/mlfeaturevalue/dictionaryvalue) The underlying dictionary of the feature value.

## Comparing feature values

- [isEqual(to:)](/documentation/coreml/mlfeaturevalue/isequal(to:)) Returns a Boolean value that indicates whether a feature value is equal to another.

## Supporting types

- [MLFeatureType](/documentation/coreml/mlfeaturetype) The possible types for feature values, input features, and output features.
- [MLShapedArray](/documentation/coreml/mlshapedarray) A machine learning collection type that stores scalar values in a multidimensional array.
- [MLShapedArrayProtocol](/documentation/coreml/mlshapedarrayprotocol) An interface that defines a shaped array type.
- [MLMultiArray](/documentation/coreml/mlmultiarray) A machine learning collection type that stores numeric values in an array with multiple dimensions.
- [MLSequence](/documentation/coreml/mlsequence) A machine learning collection type that stores a series of strings or integers.

## Initializers

- [init(cgImage:constraint:options:)](/documentation/coreml/mlfeaturevalue/init(cgimage:constraint:options:)) Construct image feature value from CGImage, using the size and type information required by feature description (orientation is assumed to be kCGImagePropertyOrientationUp)
- [init(cgImage:orientation:constraint:options:)](/documentation/coreml/mlfeaturevalue/init(cgimage:orientation:constraint:options:)) Construct image feature value from CGImage w/ specified orientation, using the size and type information required by feature description
- [init(cgImage:orientation:pixelsWide:pixelsHigh:pixelFormatType:options:)](/documentation/coreml/mlfeaturevalue/init(cgimage:orientation:pixelswide:pixelshigh:pixelformattype:options:)) Construct image feature value from CGImage w/ specified orientation
- [init(cgImage:pixelsWide:pixelsHigh:pixelFormatType:options:)](/documentation/coreml/mlfeaturevalue/init(cgimage:pixelswide:pixelshigh:pixelformattype:options:)) Construct image feature value from CGImage (orientation is assumed to be kCGImagePropertyOrientationUp)
- [init(imageAt:constraint:options:)](/documentation/coreml/mlfeaturevalue/init(imageat:constraint:options:)) Construct image feature value from an image on disk, using a model specified image constraint. Orientation is read from Exif if avaiable
- [init(imageAt:orientation:constraint:options:)](/documentation/coreml/mlfeaturevalue/init(imageat:orientation:constraint:options:)) Construct image feature value from an image on disk using a model specified image constraint. The passed in orientation supersedes any in the file
- [init(imageAt:orientation:pixelsWide:pixelsHigh:pixelFormatType:options:)](/documentation/coreml/mlfeaturevalue/init(imageat:orientation:pixelswide:pixelshigh:pixelformattype:options:)) Construct image feature value from an image on disk. The passed in orientation supersedes any in the file
- [init(imageAt:pixelsWide:pixelsHigh:pixelFormatType:options:)](/documentation/coreml/mlfeaturevalue/init(imageat:pixelswide:pixelshigh:pixelformattype:options:)) Construct image feature value from an image on disk. Orientation is read from Exif if avaiable

## Default Implementations

- [MLFeatureValue Implementations](/documentation/coreml/mlfeaturevalue/mlfeaturevalue-implementations)

## Model inputs and outputs

- [Making Predictions with a Sequence of Inputs](/documentation/coreml/making-predictions-with-a-sequence-of-inputs)
- [MLSendableFeatureValue](/documentation/coreml/mlsendablefeaturevalue)
- [MLFeatureProvider](/documentation/coreml/mlfeatureprovider)
- [MLDictionaryFeatureProvider](/documentation/coreml/mldictionaryfeatureprovider)
- [MLBatchProvider](/documentation/coreml/mlbatchprovider)
- [MLArrayBatchProvider](/documentation/coreml/mlarraybatchprovider)
- [MLModelAsset](/documentation/coreml/mlmodelasset)

---

*Extracted by [sosumi.ai](https://sosumi.ai) - Making Apple docs AI-readable.*
*This is unofficial content. All documentation belongs to Apple Inc.*