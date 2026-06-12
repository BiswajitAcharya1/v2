import Foundation

struct CanvasCourse: Identifiable, Hashable {
    var id: Int
    var name: String
    var courseCode: String?
    var grade: String?
    var score: Double?

    var notebookSubject: String {
        let raw = courseCode?.isEmpty == false ? courseCode ?? name : name
        return raw
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9\s]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var gradeLabel: String {
        if let grade, !grade.isEmpty { return grade.lowercased() }
        if let score { return "\(Int(score.rounded()))%" }
        return "grade hidden"
    }
}

struct CanvasCourseService {
    func fetchCourses(domain: String, token: String) async throws -> [CanvasCourse] {
        let cleanDomain = domain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !cleanDomain.isEmpty, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CanvasImportError.missingCredentials
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = cleanDomain
        components.path = "/api/v1/courses"
        components.queryItems = [
            URLQueryItem(name: "include[]", value: "total_scores"),
            URLQueryItem(name: "include[]", value: "term"),
            URLQueryItem(name: "state[]", value: "available"),
            URLQueryItem(name: "per_page", value: "60")
        ]
        guard let url = components.url else { throw CanvasImportError.invalidDomain }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 24

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CanvasImportError.invalidResponse }
        guard 200..<300 ~= http.statusCode else { throw CanvasImportError.rejected(http.statusCode) }
        let courses = try JSONDecoder().decode([CanvasCourseDTO].self, from: data)
        return courses.compactMap(\.course).filter { !$0.notebookSubject.isEmpty }
    }
}

enum CanvasImportError: LocalizedError {
    case missingCredentials
    case invalidDomain
    case invalidResponse
    case rejected(Int)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "enter your canvas domain and access token."
        case .invalidDomain:
            return "canvas domain could not be read."
        case .invalidResponse:
            return "canvas did not return courses."
        case .rejected(let code):
            return "canvas rejected the token (\(code))."
        }
    }
}

private struct CanvasCourseDTO: Decodable {
    var id: Int?
    var name: String?
    var courseCode: String?
    var enrollments: [CanvasEnrollmentDTO]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case courseCode = "course_code"
        case enrollments
    }

    var course: CanvasCourse? {
        guard let id, let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let enrollment = enrollments?.first
        return CanvasCourse(
            id: id,
            name: name,
            courseCode: courseCode,
            grade: enrollment?.computedCurrentGrade ?? enrollment?.computedFinalGrade,
            score: enrollment?.computedCurrentScore ?? enrollment?.computedFinalScore
        )
    }
}

private struct CanvasEnrollmentDTO: Decodable {
    var computedCurrentScore: Double?
    var computedFinalScore: Double?
    var computedCurrentGrade: String?
    var computedFinalGrade: String?

    enum CodingKeys: String, CodingKey {
        case computedCurrentScore = "computed_current_score"
        case computedFinalScore = "computed_final_score"
        case computedCurrentGrade = "computed_current_grade"
        case computedFinalGrade = "computed_final_grade"
    }
}
