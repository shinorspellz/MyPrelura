import Foundation

/// Result of on-device garment analysis for the listing assistant. All fields optional; pipeline may fail at any step.
struct GarmentAnalysisResult {
    var category: String?
    var colour: String?
    var style: String?

    var title: String?
    var description: String?
    var tags: [String]?
}
