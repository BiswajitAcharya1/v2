import Foundation

enum SubjectCatalog {
    static let all = [
        "math", "pre algebra", "algebra", "geometry", "trigonometry", "precalculus", "calculus", "statistics",
        "science", "biology", "chemistry", "physics", "environmental science", "earth science", "anatomy",
        "history", "world history", "us history", "european history", "government", "civics",
        "english", "literature", "writing", "creative writing", "spanish", "french", "latin",
        "computer science", "coding", "data science", "robotics", "economics", "psychology", "sociology",
        "art", "music", "theater", "health", "business", "engineering",
        "ap biology", "ap chemistry", "ap physics", "ap calculus", "ap statistics", "ap computer science",
        "linear algebra", "discrete math", "organic chemistry", "biochemistry", "microbiology", "neuroscience",
        "astronomy", "geology", "philosophy", "ethics", "religion", "journalism", "public speaking",
        "film", "photography", "design", "finance", "accounting", "marketing", "entrepreneurship"
    ]

    static let featured = ["biology", "math", "computer science", "chemistry", "history", "english", "physics", "economics"]

    static func suggestions(for draft: String, excluding existing: Set<String>, limit: Int = 6) -> [String] {
        let available = all.filter { !existing.contains($0) }
        let cleanedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !cleanedDraft.isEmpty else {
            return Array((featured.filter { available.contains($0) } + available.filter { !featured.contains($0) }).prefix(limit))
        }

        let prefixMatches = available.filter { $0.hasPrefix(cleanedDraft) }
        let containedMatches = available.filter {
            !prefixMatches.contains($0) && $0.localizedCaseInsensitiveContains(cleanedDraft)
        }
        return Array((prefixMatches + containedMatches).prefix(limit))
    }

    static func bestMatch(for draft: String, excluding existing: Set<String>) -> String? {
        let cleanedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanedDraft.isEmpty else { return nil }
        if all.contains(cleanedDraft), !existing.contains(cleanedDraft) {
            return cleanedDraft
        }
        return all.first { !existing.contains($0) && $0.hasPrefix(cleanedDraft) }
    }
}
