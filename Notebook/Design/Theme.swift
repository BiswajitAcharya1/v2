import SwiftUI

enum NotebookTheme {
    static let paper = Color(red: 0.965, green: 0.948, blue: 0.905)
    static let ink = Color(red: 0.095, green: 0.095, blue: 0.088)
    static let graphite = Color(red: 0.16, green: 0.16, blue: 0.15)
    static let shelf = Color(red: 0.88, green: 0.84, blue: 0.76)
    static let field = Color(red: 0.945, green: 0.936, blue: 0.912)
    static let muted = Color(red: 0.42, green: 0.4, blue: 0.36)
    static let blueLine = Color(red: 0.56, green: 0.68, blue: 0.82)
    static let redRule = Color(red: 0.8, green: 0.38, blue: 0.34)

    static func accent(_ token: ColorToken) -> Color {
        switch token {
        case .graphite: Color(red: 0.22, green: 0.22, blue: 0.2)
        case .blue: Color(red: 0.34, green: 0.48, blue: 0.68)
        case .green: Color(red: 0.34, green: 0.55, blue: 0.42)
        case .plum: Color(red: 0.48, green: 0.38, blue: 0.55)
        case .amber: Color(red: 0.7, green: 0.52, blue: 0.26)
        }
    }
}

extension Font {
    static let notebookTitle = Font.system(.largeTitle, design: .serif, weight: .semibold)
    static let notebookSection = Font.system(.title3, design: .rounded, weight: .semibold)
    static let notebookBody = Font.system(.body, design: .rounded, weight: .regular)
}

extension View {
    func lowercaseOnly() -> some View {
        textCase(nil)
    }
}
