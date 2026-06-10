import SwiftUI

struct NotebookPaperView<Content: View>: View {
    var cornerRadius: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(NotebookTheme.paper)
                .overlay(PaperRules().clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)

            content
                .padding(20)
        }
    }
}

struct PaperRules: View {
    var body: some View {
        Canvas { context, size in
            let left = size.width * 0.16
            var vertical = Path()
            vertical.move(to: CGPoint(x: left, y: 0))
            vertical.addCurve(
                to: CGPoint(x: left, y: size.height),
                control1: CGPoint(x: left - 6, y: size.height * 0.28),
                control2: CGPoint(x: left + 6, y: size.height * 0.72)
            )
            context.stroke(vertical, with: .color(NotebookTheme.redRule.opacity(0.35)), lineWidth: 1)

            let lineSpacing: CGFloat = 24
            var y: CGFloat = 28
            while y < size.height {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addCurve(
                    to: CGPoint(x: size.width, y: y),
                    control1: CGPoint(x: size.width * 0.33, y: y - 2.2),
                    control2: CGPoint(x: size.width * 0.66, y: y + 2.2)
                )
                context.stroke(line, with: .color(NotebookTheme.blueLine.opacity(0.28)), lineWidth: 0.7)
                y += lineSpacing
            }
        }
    }
}

struct PageChip: View {
    var text: String
    var systemName: String

    var body: some View {
        Label(text, systemImage: systemName)
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.white.opacity(0.58), in: Capsule())
            .foregroundStyle(NotebookTheme.ink)
    }
}
