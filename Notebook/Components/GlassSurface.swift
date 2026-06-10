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

struct CircleButtonStyle: ButtonStyle {
    var tint: Color = NotebookTheme.ink
    var foreground: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .background(tint, in: Circle())
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .shadow(color: tint.opacity(configuration.isPressed ? 0.08 : 0.18), radius: configuration.isPressed ? 3 : 8, y: configuration.isPressed ? 2 : 5)
            .animation(.spring(response: 0.24, dampingFraction: 0.72), value: configuration.isPressed)
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

struct StudyAgentBubble: View {
    var mode: AgentMode
    @State private var open = false
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if open {
                Text(mode.message)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)
                    .multilineTextAlignment(.trailing)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .transition(.move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.94)))
            }

            Button {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                    open.toggle()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Circle().stroke(.white.opacity(0.75), lineWidth: 1)
                        }
                    Image(systemName: open ? "xmark" : "sparkles")
                        .font(.system(size: 20, weight: .bold))
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .foregroundStyle(NotebookTheme.ink)
                }
                .frame(width: 58, height: 58)
                .scaleEffect(pulse ? 1.04 : 0.98)
                .shadow(color: .black.opacity(0.14), radius: 12, y: 8)
                .accessibilityLabel(mode.accessibilityLabel)
            }
            .buttonStyle(.plain)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

enum AgentMode {
    case auth
    case shelf
    case notebook

    var message: String {
        switch self {
        case .auth: "i can help you sign up, choose classes, and set up voice."
        case .shelf: "tap a notebook to scan notes, type pages, or study."
        case .notebook: "scan first, then ask me to explain anything on the page."
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .auth: "signup helper"
        case .shelf: "study helper"
        case .notebook: "notebook helper"
        }
    }
}

struct ContainerTextFlip: View {
    var words: [String]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.8)) { timeline in
            let wordIndex = Int(timeline.date.timeIntervalSinceReferenceDate / 1.8) % max(words.count, 1)
            let word = words.isEmpty ? "" : words[wordIndex]
            Text(word)
                .id(wordIndex)
                .font(.system(.callout, design: wordIndex.isMultiple(of: 2) ? .serif : .rounded, weight: .semibold))
                .foregroundStyle(NotebookTheme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.92)),
                    removal: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 1.04))
                ))
                .animation(.spring(response: 0.48, dampingFraction: 0.78), value: wordIndex)
        }
        .frame(minWidth: 106, minHeight: 34)
        .clipped()
    }
}
