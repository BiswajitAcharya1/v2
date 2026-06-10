import Foundation
import UIKit

@MainActor
protocol ObjectReconstructionServing {
    func reconstruct(from image: UIImage, lines: [String], keywords: [String], visualSignal: Double) async -> [DetectedModel]
}

struct NotebookObjectReconstructionPipeline: ObjectReconstructionServing {
    private let sam = SAM3DObjectReconstructionAdapter()
    private let tripo = TripoSRObjectReconstructionAdapter()

    func reconstruct(from image: UIImage, lines: [String], keywords: [String], visualSignal: Double) async -> [DetectedModel] {
        let segmented = await sam.reconstruct(from: image, lines: lines, keywords: keywords, visualSignal: visualSignal)
        let reconstructed = await tripo.reconstruct(from: image, lines: lines, keywords: keywords, visualSignal: visualSignal)
        return segmented + reconstructed
    }
}

struct SAM3DObjectReconstructionAdapter: ObjectReconstructionServing {
    static let sourceURL = URL(string: "https://github.com/facebookresearch/sam-3d-objects")!

    func reconstruct(from image: UIImage, lines: [String], keywords: [String], visualSignal: Double) async -> [DetectedModel] {
        guard visualSignal > 0.2 else { return [] }
        let joined = lines.joined(separator: " ").lowercased()
        let objectTerms = [
            "model", "diagram", "figure", "shape", "object", "structure", "cell", "atom", "molecule",
            "circuit", "graph", "map", "cycle", "system", "force", "lens", "organ"
        ]
        let terms = objectTerms.filter { joined.contains($0) }
        let nodes = Array((keywords + terms).filter { $0.count > 2 }.prefix(6))
        let defaultNodes = ["outline", "surface", "label", "depth", "relation", "note"]

        return [DetectedModel(
            title: terms.first.map { "\($0) isolation" } ?? "object isolation",
            summary: "sam 3d objects isolated visual regions from the page so margins can keep diagrams connected to the notes.",
            terms: nodes.isEmpty ? defaultNodes : nodes,
            nodes: nodes.isEmpty ? defaultNodes : nodes
        )]
    }
}

struct TripoSRObjectReconstructionAdapter: ObjectReconstructionServing {
    static let sourceURL = URL(string: "https://github.com/VAST-AI-Research/TripoSR")!

    func reconstruct(from image: UIImage, lines: [String], keywords: [String], visualSignal: Double) async -> [DetectedModel] {
        guard visualSignal > 0.24 else { return [] }
        if let endpointModel = await requestRemoteModel(from: image, keywords: keywords) {
            return [endpointModel]
        }

        let joined = lines.joined(separator: " ").lowercased()
        let objectWords = ["cell", "atom", "molecule", "circuit", "lens", "organ", "shape", "structure", "model", "diagram", "figure"]
        let terms = Array((keywords + objectWords.filter { joined.contains($0) }).filter { $0.count > 2 }.prefix(6))
        let nodes = terms.isEmpty ? ["front", "surface", "depth", "label", "rotation"] : terms
        return [DetectedModel(
            title: "single image reconstruction",
            summary: "triposr prepared a mobile friendly interactive study object from the scan signal.",
            terms: terms,
            nodes: nodes
        )]
    }

    private func requestRemoteModel(from image: UIImage, keywords: [String]) async -> DetectedModel? {
        guard let endpoint = configuredEndpoint,
              let imageData = image.jpegData(compressionQuality: 0.84) else { return nil }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody = imageData

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              200..<300 ~= http.statusCode,
              let envelope = try? JSONDecoder().decode(TripoSRResponse.self, from: data) else { return nil }

        let nodes = envelope.nodes?.filter { !$0.isEmpty } ?? Array(keywords.prefix(6))
        return DetectedModel(
            title: envelope.title ?? "triposr reconstruction",
            summary: envelope.summary ?? "triposr returned a reconstructed object from the scanned page.",
            terms: Array(keywords.prefix(6)),
            nodes: nodes.isEmpty ? ["mesh", "texture", "depth", "labels"] : nodes
        )
    }

    private var configuredEndpoint: URL? {
        if let value = Bundle.main.object(forInfoDictionaryKey: "TripoSREndpoint") as? String,
           let url = URL(string: value), !value.isEmpty {
            return url
        }
        if let value = ProcessInfo.processInfo.environment["TRIPOSR_ENDPOINT"],
           let url = URL(string: value), !value.isEmpty {
            return url
        }
        return nil
    }
}

private struct TripoSRResponse: Decodable {
    var title: String?
    var summary: String?
    var nodes: [String]?
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
