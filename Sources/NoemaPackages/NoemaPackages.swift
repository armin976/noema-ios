// NoemaPackages.swift
// Re-export the XCFramework's module.
// The module name inside the XCFramework is "llama".
@_exported import llama

// Re-export the RollingThought module
@_exported import RollingThought

// Resources:
// default.metallib is bundled via Package.swift resources in Sources/NoemaPackages/Resources/