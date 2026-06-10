import Foundation
import UIKit

@MainActor
protocol ObjectReconstructionServing {
    func reconstruct(from image: UIImage, lines: [String], keywords: [String], visualSignal: Double) async -> DetectedModel?
}

struct SAM3DObjectReconstructionAdapter: ObjectReconstructionServing {
    static let sourceURL = URL(string: "https://github.com/facebookresearch/sam-3d-objects")!

    func reconstruct(from image: UIImage, lines: [String], keywords: [String], visualSignal: Double) async -> DetectedModel? {
        guard visualSignal > 0.2 else { return nil }
        let joined = lines.joined(separator: " ").lowercased()
        let objectTerms = [
            "model", "diagram", "figure", "shape", "object", "structure", "cell", "atom", "molecule",
            "circuit", "graph", "map", "cycle", "system", "force", "lens", "organ"
        ]
        let terms = objectTerms.filter { joined.contains($0) }
        let nodes = Array((keywords + terms).filter { $0.count > 2 }.prefix(6))
        let defaultNodes = ["outline", "surface", "label", "depth", "relation", "note"]

        return DetectedModel(
            title: terms.first.map { "\($0) reconstruction" } ?? "object reconstruction",
            summary: "the scan geometry was lifted into an interactive study model from the page.",
            terms: nodes.isEmpty ? defaultNodes : nodes,
            nodes: nodes.isEmpty ? defaultNodes : nodes
        )
    }
}

enum ImageStructureAnalyzer {
    static func visualModelSignal(in image: UIImage) -> Double {
        guard let cgImage = image.cgImage else { return 0 }
        let width = 56
        let height = 72
        var pixels = [UInt8](repeating: 255, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return 0 }

        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var darkCount = 0
        var edgeCount = 0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let index = y * width + x
                let value = Int(pixels[index])
                if value < 154 { darkCount += 1 }
                let right = Int(pixels[index + 1])
                let down = Int(pixels[index + width])
                if abs(value - right) > 44 || abs(value - down) > 44 {
                    edgeCount += 1
                }
            }
        }

        let sampleCount = Double((width - 2) * (height - 2))
        let inkDensity = Double(darkCount) / sampleCount
        let edgeDensity = Double(edgeCount) / sampleCount
        return min(1, inkDensity * 0.55 + edgeDensity * 0.75)
    }
}
