import Foundation
import Vision
import UIKit

@MainActor
class VisionService: ObservableObject {
    @Published var topClassifications: [String] = []

    private let classifyQueue = DispatchQueue(label: "com.moveclaw.vision", qos: .userInitiated)

    /// Run VNClassifyImageRequest on a UIImage and return top classifications
    func classify(_ image: UIImage, topK: Int = 5) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }

        return await withCheckedContinuation { continuation in
            classifyQueue.async {
                let request = VNClassifyImageRequest()
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

                do {
                    try handler.perform([request])

                    guard let results = request.results else {
                        continuation.resume(returning: [])
                        return
                    }

                    // Filter to confident results and take top K
                    let top = results
                        .filter { $0.confidence > 0.1 }
                        .prefix(topK)
                        .map { $0.identifier }

                    continuation.resume(returning: Array(top))
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    /// Check if any of the detected classifications are relevant to the bet condition
    func isRelevant(classifications: [String], toBetCondition condition: String) -> Bool {
        let conditionLower = condition.lowercased()
        let keywords = conditionLower.split(separator: " ").map(String.init)

        for classification in classifications {
            let classLower = classification.lowercased().replacingOccurrences(of: "_", with: " ")
            // Check if any classification word overlaps with bet condition words
            for keyword in keywords {
                if keyword.count > 3 && classLower.contains(keyword) {
                    return true
                }
            }
        }

        // Always return true for common activity-related classifications
        let activityIndicators = ["person", "hand", "food", "eating", "picking_up", "holding", "reaching"]
        for classification in classifications {
            if activityIndicators.contains(classification.lowercased()) {
                return true
            }
        }

        return false
    }
}
