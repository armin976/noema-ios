---
title: MLComputeDevice
description: Compute devices for framework operations.
source: https://developer.apple.com/documentation/coreml/mlcomputedevice
timestamp: 2026-03-08T17:56:46.909Z
---

**Navigation:** [Coreml](/documentation/coreml)

**Enumeration**

# MLComputeDevice

**Available on:** iOS 17.0+, iPadOS 17.0+, Mac Catalyst 17.0+, macOS 14.0+, tvOS 17.0+, visionOS 1.0+, watchOS 10.0+

> Compute devices for framework operations.

```swift
enum MLComputeDevice
```

## Conforms To

- [CustomStringConvertible](/documentation/Swift/CustomStringConvertible)
- [Equatable](/documentation/Swift/Equatable)
- [Hashable](/documentation/Swift/Hashable)
- [Sendable](/documentation/Swift/Sendable)
- [SendableMetatype](/documentation/Swift/SendableMetatype)

## Device types

- [MLComputeDevice.cpu(_:)](/documentation/coreml/mlcomputedevice/cpu(_:)) A device that represents a CPU compute device.
- [MLComputeDevice.gpu(_:)](/documentation/coreml/mlcomputedevice/gpu(_:)) A device that represents a GPU compute device.
- [MLComputeDevice.neuralEngine(_:)](/documentation/coreml/mlcomputedevice/neuralengine(_:)) A device that represents a Neural Engine compute device.

## Getting all devices

- [allComputeDevices](/documentation/coreml/mlcomputedevice/allcomputedevices) Returns an array that contains all of the compute devices that are accessible.

## Compute devices

- [MLCPUComputeDevice](/documentation/coreml/mlcpucomputedevice)
- [MLGPUComputeDevice](/documentation/coreml/mlgpucomputedevice)
- [MLNeuralEngineComputeDevice](/documentation/coreml/mlneuralenginecomputedevice)
- [MLComputeDeviceProtocol](/documentation/coreml/mlcomputedeviceprotocol)

---

*Extracted by [sosumi.ai](https://sosumi.ai) - Making Apple docs AI-readable.*
*This is unofficial content. All documentation belongs to Apple Inc.*