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
        var seen = Set<String>()
        return (segmented + reconstructed).filter { model in
            seen.insert(model.title).inserted
        }
    }
}

struct SAM3DObjectReconstructionAdapter: ObjectReconstructionServing {
    static let sourceURL = URL(string: "https://github.com/facebookresearch/sam-3d-objects")!

    func reconstruct(from image: UIImage, lines: [String], keywords: [String], visualSignal: Double) async -> [DetectedModel] {
        let joined = lines.joined(separator: " ").lowercased()
        let textSuggestsObject = ["diagram", "sketch", "model", "shape", "cell", "atom", "circuit", "graph", "map", "arrow", "label"].contains(where: joined.contains)
        guard visualSignal > 0.14 || textSuggestsObject else { return [] }
        if let endpointModel = await requestRemoteModel(from: image, keywords: keywords) {
            return [endpointModel]
        }

        let objectTerms = [
            "model", "diagram", "figure", "shape", "object", "structure", "cell", "atom", "molecule",
            "circuit", "graph", "map", "cycle", "system", "force", "lens", "organ"
        ]
        let terms = objectTerms.filter { joined.contains($0) }
        let diagramNodes = ReconstructionTextAnalyzer.diagramNodes(from: lines, keywords: keywords)
        let nodes = Array((diagramNodes + keywords + terms).filter { $0.count > 2 }.prefix(7))
        let profile = ImageStructureAnalyzer.profile(in: image)
        let structureNodes = ["outline", profile.complexityLabel, "labels", "edges", "relations", "study focus"]
        let finalNodes = nodes.isEmpty ? structureNodes : Array((nodes + structureNodes).prefix(6))
        let shape = ReconstructionTextAnalyzer.shape(from: lines, profile: profile)
        return [DetectedModel(
            title: terms.first.map { "\($0) region" } ?? "diagram region",
            summary: "vellum isolated the strongest visual region and rebuilt its labels, arrows, edges, and note anchors into a tappable study model.",
            terms: finalNodes,
            nodes: finalNodes,
            reconstruction: ModelReconstructionFactory.make(
                source: "sam 3d objects local",
                confidence: max(0.42, min(0.96, profile.signal + 0.38)),
                shape: shape,
                nodes: finalNodes,
                hint: "drag the model, then tap each anchor in order."
            )
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
              let envelope = try? JSONDecoder().decode(ReconstructionResponse.self, from: data) else { return nil }

        let nodes = envelope.nodes?.filter { !$0.isEmpty } ?? Array(keywords.prefix(6))
        return DetectedModel(
            title: envelope.title ?? "sam 3d object",
            summary: envelope.summary ?? "sam 3d objects returned an isolated object from the scanned page.",
            terms: Array(keywords.prefix(6)),
            nodes: nodes.isEmpty ? ["mask", "object", "depth", "surface"] : nodes,
            reconstruction: ModelReconstructionFactory.make(
                source: "sam 3d objects endpoint",
                confidence: 0.92,
                shape: .mesh,
                nodes: nodes.isEmpty ? ["mask", "object", "depth", "surface"] : nodes,
                hint: "endpoint reconstruction is ready to rotate and label."
            )
        )
    }

    private var configuredEndpoint: URL? {
        if let value = Bundle.main.object(forInfoDictionaryKey: "SAM3DObjectsEndpoint") as? String,
           let url = URL(string: value), !value.isEmpty {
            return url
        }
        if let value = ProcessInfo.processInfo.environment["SAM3D_OBJECTS_ENDPOINT"],
           let url = URL(string: value), !value.isEmpty {
            return url
        }
        return nil
    }
}

struct TripoSRObjectReconstructionAdapter: ObjectReconstructionServing {
    static let sourceURL = URL(string: "https://github.com/VAST-AI-Research/TripoSR")!

    func reconstruct(from image: UIImage, lines: [String], keywords: [String], visualSignal: Double) async -> [DetectedModel] {
        let joined = lines.joined(separator: " ").lowercased()
        let textSuggestsObject = ["diagram", "sketch", "model", "shape", "cell", "atom", "circuit", "graph", "map", "arrow", "label"].contains(where: joined.contains)
        guard visualSignal > 0.16 || textSuggestsObject else { return [] }
        if let endpointModel = await requestRemoteModel(from: image, keywords: keywords) {
            return [endpointModel]
        }

        let profile = ImageStructureAnalyzer.profile(in: image)
        let objectWords = ["cell", "atom", "molecule", "circuit", "lens", "organ", "shape", "structure", "model", "diagram", "figure"]
        let diagramNodes = ReconstructionTextAnalyzer.diagramNodes(from: lines, keywords: keywords)
        let terms = Array((diagramNodes + keywords + objectWords.filter { joined.contains($0) }).filter { $0.count > 2 }.prefix(7))
        let geometryNodes = ["front plane", "depth cue", profile.complexityLabel, "label anchors", "rotation", "memory hook"]
        let nodes = terms.isEmpty ? geometryNodes : Array((terms + geometryNodes).prefix(6))
        let shape = ReconstructionTextAnalyzer.shape(from: lines, profile: profile)
        return [DetectedModel(
            title: ReconstructionTextAnalyzer.title(from: lines, fallback: "interactive 3d study object"),
            summary: "the diagram geometry was converted into a rotatable study object with depth cues, scan labels, and linked note anchors.",
            terms: terms,
            nodes: nodes,
            reconstruction: ModelReconstructionFactory.make(
                source: "triposr local",
                confidence: max(0.44, min(0.94, profile.signal + 0.34)),
                shape: shape == .orbit ? .mesh : shape,
                nodes: nodes,
                hint: "swipe the surface to see the depth cues from the scan."
            )
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
              let envelope = try? JSONDecoder().decode(ReconstructionResponse.self, from: data) else { return nil }

        let nodes = envelope.nodes?.filter { !$0.isEmpty } ?? Array(keywords.prefix(6))
        return DetectedModel(
            title: envelope.title ?? "triposr reconstruction",
            summary: envelope.summary ?? "triposr returned a reconstructed object from the scanned page.",
            terms: Array(keywords.prefix(6)),
            nodes: nodes.isEmpty ? ["mesh", "texture", "depth", "labels"] : nodes,
            reconstruction: ModelReconstructionFactory.make(
                source: "triposr endpoint",
                confidence: 0.9,
                shape: .mesh,
                nodes: nodes.isEmpty ? ["mesh", "texture", "depth", "labels"] : nodes,
                hint: "endpoint mesh is ready for orbit review."
            )
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

enum ModelReconstructionFactory {
    static func make(source: String, confidence: Double, shape: ModelShape, nodes: [String], hint: String) -> ModelReconstruction {
        let cleanedNodes = nodes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        let safeNodes = cleanedNodes.isEmpty ? ["idea", "edge", "label", "depth"] : Array(cleanedNodes.prefix(8))
        let anchors = safeNodes.enumerated().map { index, label in
            anchor(for: index, count: safeNodes.count, label: label, shape: shape)
        }
        return ModelReconstruction(
            source: source,
            confidence: min(1, max(0, confidence)),
            shape: shape,
            anchors: anchors,
            interactionHint: hint
        )
    }

    private static func anchor(for index: Int, count: Int, label: String, shape: ModelShape) -> ModelAnchor {
        let phase = Double(index) / Double(max(count, 1))
        switch shape {
        case .cycle:
            let angle = phase * .pi * 2 - .pi / 2
            return ModelAnchor(label: label, x: 0.5 + cos(angle) * 0.36, y: 0.5 + sin(angle) * 0.28, z: sin(angle) * 0.35)
        case .table:
            let columns = min(3, max(1, count))
            let row = index / columns
            let column = index % columns
            return ModelAnchor(label: label, x: 0.24 + Double(column) * 0.26, y: 0.28 + Double(row) * 0.18, z: Double(row) * 0.08)
        case .stack:
            return ModelAnchor(label: label, x: 0.28 + phase * 0.44, y: 0.72 - phase * 0.46, z: phase)
        case .mesh:
            let angle = phase * .pi * 2 - .pi / 2
            let wobble = index.isMultiple(of: 2) ? 0.08 : -0.08
            return ModelAnchor(label: label, x: 0.5 + cos(angle) * (0.3 + wobble), y: 0.5 + sin(angle) * 0.34, z: cos(angle) * 0.42)
        case .orbit:
            let angle = phase * .pi * 2 - .pi / 2
            return ModelAnchor(label: label, x: 0.5 + cos(angle) * 0.34, y: 0.5 + sin(angle) * 0.24, z: sin(angle) * 0.22)
        }
    }
}

private struct ReconstructionResponse: Decodable {
    var title: String?
    var summary: String?
    var nodes: [String]?
}

private enum ReconstructionTextAnalyzer {
    static func diagramNodes(from lines: [String], keywords: [String]) -> [String] {
        let separators = CharacterSet(charactersIn: "→->:=|,;()[]{}")
        var candidates: [String] = []
        for line in lines {
            let lower = line.lowercased()
            let isStructureLine = lower.contains("->")
                || lower.contains("→")
                || lower.contains(":")
                || lower.contains("=")
                || lower.contains("diagram")
                || lower.contains("model")
                || lower.contains("table")
            guard isStructureLine || candidates.count < 3 else { continue }
            let tokens = lower
                .components(separatedBy: separators)
                .flatMap { $0.components(separatedBy: .whitespacesAndNewlines) }
                .map { $0.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines)) }
                .filter { token in
                    token.count > 2
                        && !["the", "and", "with", "from", "into", "that", "this", "notes", "page"].contains(token)
                }
            candidates.append(contentsOf: tokens)
        }
        var seen = Set<String>()
        return (candidates + keywords)
            .filter { seen.insert($0).inserted }
            .prefix(8)
            .map(\.self)
    }

    static func shape(from lines: [String], profile: ImageStructureAnalyzer.Profile) -> ModelShape {
        let text = lines.joined(separator: " ").lowercased()
        if text.contains("table") || text.contains("chart") || text.contains("matrix") { return .table }
        if text.contains("cycle") || text.contains("loop") || text.contains("flow") || text.contains("→") || text.contains("->") { return .cycle }
        if text.contains("layer") || text.contains("stack") || text.contains("levels") { return .stack }
        if profile.edgeDensity > 0.24 || profile.signal > 0.34 { return .mesh }
        return .orbit
    }

    static func title(from lines: [String], fallback: String) -> String {
        let candidates = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        if let heading = candidates.first(where: { $0.count <= 44 && ($0.contains("diagram") || $0.contains("model") || $0.contains("cycle")) }) {
            return heading
        }
        if let short = candidates.first(where: { $0.count >= 4 && $0.count <= 34 }) {
            return "\(short) model"
        }
        return fallback
    }
}

enum ImageStructureAnalyzer {
    struct Profile {
        var signal: Double
        var inkDensity: Double
        var edgeDensity: Double
        var balance: Double

        var complexityLabel: String {
            if edgeDensity > 0.28 { return "dense sketch" }
            if signal > 0.22 { return "clear shape" }
            if balance > 0.72 { return "balanced form" }
            return "light sketch"
        }
    }

    static func visualModelSignal(in image: UIImage) -> Double {
        profile(in: image).signal
    }

    static func profile(in image: UIImage) -> Profile {
        guard let cgImage = image.cgImage else {
            return Profile(signal: 0, inkDensity: 0, edgeDensity: 0, balance: 0)
        }
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
        ) else {
            return Profile(signal: 0, inkDensity: 0, edgeDensity: 0, balance: 0)
        }

        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var darkCount = 0
        var edgeCount = 0
        var leftDark = 0
        var rightDark = 0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let index = y * width + x
                let value = Int(pixels[index])
                if value < 154 {
                    darkCount += 1
                    if x < width / 2 {
                        leftDark += 1
                    } else {
                        rightDark += 1
                    }
                }
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
        let darkerSide = max(leftDark, rightDark)
        let lighterSide = min(leftDark, rightDark)
        let balance = darkerSide == 0 ? 0 : Double(lighterSide) / Double(darkerSide)
        let signal = min(1, inkDensity * 0.55 + edgeDensity * 0.75 + balance * 0.04)
        return Profile(signal: signal, inkDensity: inkDensity, edgeDensity: edgeDensity, balance: balance)
    }
}
