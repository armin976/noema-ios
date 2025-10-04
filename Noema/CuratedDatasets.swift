// CuratedDatasets.swift
import Foundation

enum CuratedDatasets {
    // Existing HF curated datasets (placeholder)
    static let hf: [ManualDatasetRegistry.Entry] = ManualDatasetRegistry.defaultEntries

    // Curated selections from the Open Textbook Library
    static let otl: [ManualDatasetRegistry.Entry] = [
        ManualDatasetRegistry.Entry(
            record: DatasetRecord(
                id: "OTL/a-first-course-in-linear-algebra",
                displayName: "A First Course in Linear Algebra",
                publisher: "Robert A. Beezer",
                summary: "Introductory linear algebra textbook.",
                installed: false),
            details: DatasetDetails(
                id: "OTL/a-first-course-in-linear-algebra",
                summary: "A First Course in Linear Algebra is an introductory textbook aimed at college-level sophomores and juniors.",
                files: [DatasetFile(
                    id: "a-first-course-in-linear-algebra.pdf",
                    name: "a-first-course-in-linear-algebra.pdf",
                    sizeBytes: 0,
                    downloadURL: URL(string: "https://citeseerx.ist.psu.edu/document?repid=rep1&type=pdf&doi=2d126254474e43b7d300ef5e60752d5e19f287c3")!
                )],
                displayName: "A First Course in Linear Algebra"
            )
        )
    ]
}
