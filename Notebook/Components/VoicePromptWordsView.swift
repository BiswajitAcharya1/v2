import SwiftUI

struct VoicePromptWordsView: View {
    var prompt: String
    var progress: Int
    var recording: Bool
    var voiceActive: Bool

    private var words: [String] {
        prompt.split(separator: " ").map(String.init)
    }

    var body: some View {
        WordWrapLayout(horizontalSpacing: 6, verticalSpacing: 7) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                Text(word)
                    .font(.system(.title3, design: .rounded, weight: wordWeight(index)))
                    .foregroundStyle(wordColor(index))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background {
                        Capsule()
                            .fill(wordFill(index))
                            .overlay {
                                Capsule().stroke(wordStroke(index), lineWidth: 0.8)
                            }
                    }
                    .scaleEffect(isActiveWord(index) ? 1.06 : 1)
                    .animation(.spring(response: 0.26, dampingFraction: 0.74), value: progress)
                    .animation(.spring(response: 0.22, dampingFraction: 0.72), value: voiceActive)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel(prompt)
    }

    private func isCompleted(_ index: Int) -> Bool {
        index < progress
    }

    private func isActiveWord(_ index: Int) -> Bool {
        recording && voiceActive && progress > 0 && index == progress - 1
    }

    private func wordWeight(_ index: Int) -> Font.Weight {
        isCompleted(index) ? .semibold : .regular
    }

    private func wordColor(_ index: Int) -> Color {
        if isCompleted(index) {
            return NotebookTheme.ink
        }
        return NotebookTheme.muted.opacity(recording ? 0.48 : 0.78)
    }

    private func wordFill(_ index: Int) -> Color {
        if isActiveWord(index) {
            return NotebookTheme.ink.opacity(0.1)
        }
        if isCompleted(index) {
            return .white.opacity(0.62)
        }
        return .white.opacity(0.28)
    }

    private func wordStroke(_ index: Int) -> Color {
        if isActiveWord(index) {
            return NotebookTheme.ink.opacity(0.24)
        }
        return .white.opacity(0.48)
    }
}

private struct WordWrapLayout: Layout {
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let proposedWidth = lineWidth == 0 ? size.width : lineWidth + horizontalSpacing + size.width
            if proposedWidth > maxWidth, lineWidth > 0 {
                totalHeight += lineHeight + verticalSpacing
                lineWidth = size.width
                lineHeight = size.height
            } else {
                lineWidth = proposedWidth
                lineHeight = max(lineHeight, size.height)
            }
        }

        return CGSize(width: maxWidth, height: totalHeight + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var line: [(LayoutSubviews.Element, CGSize)] = []
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        var y = bounds.minY

        func placeLine() {
            guard !line.isEmpty else { return }
            var x = bounds.midX - lineWidth / 2
            for (subview, size) in line {
                subview.place(
                    at: CGPoint(x: x, y: y + (lineHeight - size.height) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + horizontalSpacing
            }
            y += lineHeight + verticalSpacing
            line.removeAll()
            lineWidth = 0
            lineHeight = 0
        }

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let proposedWidth = lineWidth == 0 ? size.width : lineWidth + horizontalSpacing + size.width
            if proposedWidth > bounds.width, lineWidth > 0 {
                placeLine()
            }
            line.append((subview, size))
            lineWidth = lineWidth == 0 ? size.width : lineWidth + horizontalSpacing + size.width
            lineHeight = max(lineHeight, size.height)
        }
        placeLine()
    }
}
