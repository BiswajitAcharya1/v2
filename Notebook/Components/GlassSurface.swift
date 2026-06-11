import SwiftUI
import UIKit

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
                .overlay {
                    GlassEdgeLight(radius: radius)
                }
        } else {
            content
                .padding(padding)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay {
                    GlassEdgeLight(radius: radius)
                }
        }
    }
}

private struct GlassEdgeLight: View {
    var radius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [.white.opacity(0.72), .white.opacity(0.18), .black.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.8
            )
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.white.opacity(0.18))
                    .frame(height: 1)
                    .padding(.horizontal, radius * 0.42)
                    .blur(radius: 0.5)
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
            .background {
                Capsule()
                    .fill(tint)
                    .overlay(alignment: configuration.isPressed ? .bottomTrailing : .topLeading) {
                        Capsule()
                            .fill(.white.opacity(configuration.isPressed ? 0.18 : 0.09))
                            .frame(width: configuration.isPressed ? 88 : 54, height: 26)
                            .blur(radius: 10)
                    }
            }
            .overlay {
                Capsule()
                    .stroke(.white.opacity(configuration.isPressed ? 0.34 : 0.16), lineWidth: 0.8)
            }
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .rotation3DEffect(.degrees(configuration.isPressed ? -2.5 : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.75)
            .shadow(color: tint.opacity(configuration.isPressed ? 0.08 : 0.16), radius: configuration.isPressed ? 5 : 8, y: configuration.isPressed ? 3 : 6)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: configuration.isPressed)
            .modifier(HapticPressFeedback(isPressed: configuration.isPressed))
    }
}

struct CircleButtonStyle: ButtonStyle {
    var tint: Color = NotebookTheme.ink
    var foreground: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .background {
                Circle()
                    .fill(tint)
                    .overlay(alignment: configuration.isPressed ? .bottomTrailing : .topLeading) {
                        Circle()
                            .fill(.white.opacity(configuration.isPressed ? 0.22 : 0.1))
                            .frame(width: configuration.isPressed ? 34 : 24, height: configuration.isPressed ? 34 : 24)
                            .blur(radius: 8)
                    }
            }
            .overlay {
                Circle()
                    .stroke(.white.opacity(configuration.isPressed ? 0.36 : 0.18), lineWidth: 0.8)
            }
            .scaleEffect(configuration.isPressed ? 0.945 : 1)
            .rotation3DEffect(.degrees(configuration.isPressed ? 5 : 0), axis: (x: 0.6, y: 1, z: 0), perspective: 0.72)
            .shadow(color: tint.opacity(configuration.isPressed ? 0.08 : 0.18), radius: configuration.isPressed ? 4 : 8, y: configuration.isPressed ? 3 : 5)
            .animation(.spring(response: 0.4, dampingFraction: 0.86), value: configuration.isPressed)
            .modifier(HapticPressFeedback(isPressed: configuration.isPressed))
    }
}

struct FloatingCircleButtonStyle: ButtonStyle {
    var tint: Color = NotebookTheme.ink
    var foreground: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .background {
                ZStack {
                    Circle()
                        .fill(tint)
                    Circle()
                        .trim(from: 0.08, to: 0.34)
                        .stroke(.white.opacity(configuration.isPressed ? 0.5 : 0.24), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                        .rotationEffect(.degrees(configuration.isPressed ? 118 : -18))
                        .padding(5)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.white.opacity(configuration.isPressed ? 0.42 : 0.22), .clear],
                                center: configuration.isPressed ? .bottomTrailing : .topLeading,
                                startRadius: 2,
                                endRadius: configuration.isPressed ? 46 : 34
                            )
                        )
                        .scaleEffect(configuration.isPressed ? 1.12 : 0.86)
                    Circle()
                        .fill(.white.opacity(configuration.isPressed ? 0.52 : 0.34))
                        .frame(width: configuration.isPressed ? 8 : 6, height: configuration.isPressed ? 8 : 6)
                        .offset(x: configuration.isPressed ? -13 : 14, y: configuration.isPressed ? 15 : -14)
                    Circle()
                        .stroke(.white.opacity(configuration.isPressed ? 0.5 : 0.24), lineWidth: 0.9)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .rotationEffect(.degrees(configuration.isPressed ? 6 : 0))
            .rotation3DEffect(.degrees(configuration.isPressed ? -6 : 0), axis: (x: 0.2, y: 1, z: 0), perspective: 0.7)
            .shadow(color: tint.opacity(configuration.isPressed ? 0.1 : 0.22), radius: configuration.isPressed ? 5 : 12, y: configuration.isPressed ? 4 : 8)
            .animation(.spring(response: 0.46, dampingFraction: 0.82), value: configuration.isPressed)
            .modifier(HapticPressFeedback(isPressed: configuration.isPressed))
    }
}

private struct HapticPressFeedback: ViewModifier {
    var isPressed: Bool
    @State private var wasPressed = false

    func body(content: Content) -> some View {
        content
            .onChange(of: isPressed) { _, newValue in
                if newValue && !wasPressed {
                    Haptics.press()
                }
                wasPressed = newValue
            }
    }
}

struct GooeyInput: View {
    var label: String?
    var systemName: String?
    @Binding var text: String
    var isSecure = false
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?
    var onSubmit: (() -> Void)?

    @FocusState private var focused: Bool
    @State private var breath = false

    private var isActive: Bool {
        focused || !text.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let label {
                Text(label)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(NotebookTheme.muted)
            }

            HStack(spacing: 10) {
                if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NotebookTheme.muted)
                }

                Group {
                    if isSecure {
                        SecureField("", text: $text)
                            .textContentType(textContentType)
                    } else {
                        TextField("", text: $text)
                            .keyboardType(keyboardType)
                            .textContentType(textContentType)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .foregroundStyle(NotebookTheme.ink)
                .tint(NotebookTheme.ink)
                .onSubmit {
                    Haptics.selection()
                    onSubmit?()
                }
            }
            .font(.system(.body, design: typingDesign, weight: .regular))
            .padding(.horizontal, 15)
            .padding(.vertical, 14)
            .background {
                GooeyInputBackground(active: isActive, breath: breath)
            }
            .overlay {
                Capsule()
                    .stroke(.white.opacity(focused ? 0.8 : 0.42), lineWidth: focused ? 1.1 : 0.8)
            }
            .scaleEffect(focused ? 1.012 : 1)
            .animation(.spring(response: 0.38, dampingFraction: 0.8), value: focused)
            .animation(.spring(response: 0.32, dampingFraction: 0.84), value: text.count)
        }
        .onChange(of: isActive) { _, newValue in
            withAnimation(.easeInOut(duration: 0.72)) {
                breath = newValue
            }
        }
    }

    private var typingDesign: Font.Design {
        let designs: [Font.Design] = [.rounded, .serif, .rounded, .monospaced, .default, .serif]
        return designs[max(0, text.count) % designs.count]
    }
}

private struct GooeyInputBackground: View {
    var active: Bool
    var breath: Bool

    var body: some View {
        Capsule()
            .fill(.white.opacity(active ? 0.74 : 0.62))
            .overlay {
                GeometryReader { proxy in
                    let width = proxy.size.width
                    let height = proxy.size.height
                    ZStack {
                        Circle()
                            .fill(NotebookTheme.ink.opacity(active ? 0.12 : 0.06))
                            .frame(width: active ? 82 : 54, height: active ? 82 : 54)
                            .blur(radius: 18)
                            .offset(x: breath ? width * 0.32 : -width * 0.3, y: breath ? -height * 0.08 : height * 0.1)
                        Circle()
                            .fill(Color(red: 1.0, green: 0.48, blue: 0.18).opacity(active ? 0.13 : 0.05))
                            .frame(width: active ? 70 : 46, height: active ? 70 : 46)
                            .blur(radius: 16)
                            .offset(x: breath ? -width * 0.28 : width * 0.28, y: breath ? height * 0.1 : -height * 0.08)
                    }
                    .frame(width: width, height: height)
                    .clipShape(Capsule())
                }
            }
    }
}

struct DirectionAwareTouchHighlight: View {
    var offset: CGSize
    var isActive: Bool
    var cornerRadius: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let height = max(proxy.size.height, 1)
            let x = min(max(0.5 + offset.width / max(width, 1), 0.08), 0.92)
            let y = min(max(0.5 + offset.height / max(height, 1), 0.08), 0.92)
            ZStack {
                RadialGradient(
                    colors: [.white.opacity(isActive ? 0.36 : 0.16), .clear],
                    center: UnitPoint(x: x, y: y),
                    startRadius: 4,
                    endRadius: isActive ? 180 : 120
                )
                LinearGradient(
                    colors: [.clear, .white.opacity(isActive ? 0.16 : 0.07), .clear],
                    startPoint: UnitPoint(x: 1 - x, y: 0),
                    endPoint: UnitPoint(x: x, y: 1)
                )
                .rotationEffect(.degrees(isActive ? Double(offset.width / 3) : 0))
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .animation(.spring(response: 0.34, dampingFraction: 0.76), value: offset)
            .animation(.spring(response: 0.26, dampingFraction: 0.82), value: isActive)
        }
        .allowsHitTesting(false)
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
        .simultaneousGesture(TapGesture().onEnded { Haptics.press() })
    }
}

enum LegalDocument: String, Identifiable {
    case terms
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terms: "terms of service"
        case .privacy: "privacy policy"
        }
    }

    var summary: String {
        switch self {
        case .terms:
            "clear rules for using vellum as a study notebook."
        case .privacy:
            "how vellum handles notes, account data, scans, and voice setup."
        }
    }

    var sections: [(String, String)] {
        switch self {
        case .terms:
            [
                ("your account", "use accurate sign up information, keep your password private, and only use accounts you are allowed to access."),
                ("your notes", "you keep ownership of notes you scan or type. vellum organizes them so you can study, search, listen, and review."),
                ("ai study tools", "ai explanations, flashcards, and only what matters are study aids. check important answers against your class materials."),
                ("acceptable use", "do not upload content you do not have the right to use, try to break the app, or use another person's account."),
                ("changes", "features may improve over time. when terms change, the app should make the updated version easy to review.")
            ]
        case .privacy:
            [
                ("data we save", "vellum stores your account session, subjects, notebooks, scanned pages, typed notes, study state, and optional voice samples on device for this demo build."),
                ("scans and text", "scanned notes are processed to extract readable text, tables, diagrams, and subject labels so pages can be filed into notebooks."),
                ("voice setup", "voice recording is optional. if you use it, the app stores short samples and transcripts so reading features can personalize playback."),
                ("sign in", "email sign in is local in this build. apple and google require production secrets before they can connect."),
                ("control", "you can skip voice setup, edit notes, add subjects, and review saved account information from account center.")
            ]
        }
    }
}

struct LegalDocumentView: View {
    let document: LegalDocument
    @Environment(\.dismiss) private var dismiss
    @State private var entered = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    ForEach(Array(document.sections.enumerated()), id: \.offset) { index, section in
                        legalSection(index: index + 1, title: section.0, body: section.1)
                    }
                    Text("last updated for this demo build.")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(NotebookTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 6)
                }
                .padding(20)
            }
            .background(LivingPaperBackground().ignoresSafeArea())
            .navigationTitle(document.title)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.softTap()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(NotebookTheme.ink)
                            .frame(width: 38, height: 38)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .onAppear {
                withAnimation(.spring(response: 0.58, dampingFraction: 0.84)) {
                    entered = true
                }
            }
        }
    }

    private var header: some View {
        GlassSurface(radius: 28, padding: 18, interactive: true) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(NotebookTheme.ink)
                    Image(systemName: document == .terms ? "doc.text.fill" : "hand.raised.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 5) {
                    Text(document.title)
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .foregroundStyle(NotebookTheme.ink)
                    Text(document.summary)
                        .font(.system(.footnote, design: .rounded, weight: .medium))
                        .foregroundStyle(NotebookTheme.muted)
                        .lineSpacing(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(entered ? 1 : 0)
        .offset(y: entered ? 0 : 10)
    }

    private func legalSection(index: Int, title: String, body: String) -> some View {
        GlassSurface(radius: 22, padding: 16, interactive: true) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    Text("\(index)")
                        .font(.system(.caption, design: .monospaced, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(NotebookTheme.ink, in: Circle())
                    Text(title)
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(NotebookTheme.ink)
                }
                Text(body)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(NotebookTheme.muted)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(entered ? 1 : 0)
        .offset(y: entered ? 0 : 12)
        .animation(.spring(response: 0.58, dampingFraction: 0.86).delay(Double(index) * 0.035), value: entered)
    }
}

struct ContainerTextFlip: View {
    var words: [String]
    private let designs: [Font.Design] = [.serif, .rounded, .monospaced, .default, .rounded, .serif, .default, .monospaced, .rounded, .serif, .default]
    private let weights: [Font.Weight] = [.semibold, .medium, .regular, .semibold, .bold, .light, .medium, .semibold, .regular, .bold, .light]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2.4)) { timeline in
            let wordIndex = Int(timeline.date.timeIntervalSinceReferenceDate / 2.4) % max(words.count, 1)
            let word = words.isEmpty ? "" : words[wordIndex]
            Text(word)
                .id(wordIndex)
                .font(.system(.callout, design: designs[wordIndex % designs.count], weight: weights[wordIndex % weights.count]))
                .foregroundStyle(NotebookTheme.ink)
                .padding(.horizontal, 2)
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(NotebookTheme.ink.opacity(0.18))
                        .frame(height: 3)
                        .offset(y: 4)
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.92)),
                    removal: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 1.04))
                ))
                .animation(.spring(response: 0.64, dampingFraction: 0.86), value: wordIndex)
        }
        .frame(minWidth: 126, minHeight: 34)
        .clipped()
    }
}
