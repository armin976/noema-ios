// DatasetIndexingAttributes.swift
import ActivityKit
import Foundation

// Mirror types used by the app for Live Activity rendering in this extension's module.

enum DatasetProcessingStage: String, Codable, Sendable {
    case extracting
    case compressing
    case embedding
    case completed
    case failed
}

struct DatasetIndexingAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var datasetID: String
        var name: String
        var stage: DatasetProcessingStage
        var progress: Double
        var message: String?
    }

    var datasetID: String
    var name: String
}


