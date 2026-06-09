import SwiftUI

struct GlassSurface<Content: View>: View {
    var radius: CGFloat = 18
    var padding: CGFloat = 14
    var interactive = false
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            content
                .padding(padding)
                .glassEffect(
                    interactive ? .regular.interactive() : .regular,
                    in: .rect(cornerRadius: radius)
                )
        } else {
            content
                .padding(padding)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(.white.opacity(0.28), lineWidth: 0.7)
                }
        }
    }
}

struct PillButtonStyle: ButtonStyle {
    var tint: Color = NotebookTheme.ink
    var foreground: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(tint, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

struct IconGlassButton: View {
    var systemName: String
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(NotebookTheme.ink)
                .frame(width: 42, height: 42)
                .contentShape(Circle())
                .accessibilityLabel(label)
        }
        .buttonStyle(.plain)
        .background(.ultraThinMaterial, in: Circle())
    }
}
