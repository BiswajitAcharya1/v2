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
            .background(tint, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
            .modifier(HapticPressFeedback(isPressed: configuration.isPressed))
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
            "clear rules for using marbled as a study notebook."
        case .privacy:
            "how marbled handles notes, account data, scans, and voice setup."
        }
    }

    var sections: [(String, String)] {
        switch self {
        case .terms:
            [
                ("your account", "use accurate sign up information, keep your password private, and only use accounts you are allowed to access."),
                ("your notes", "you keep ownership of notes you scan or type. marbled organizes them so you can study, search, listen, and review."),
                ("ai study tools", "ai explanations, flashcards, and only what matters are study aids. check important answers against your class materials."),
                ("acceptable use", "do not upload content you do not have the right to use, try to break the app, or use another person's account."),
                ("changes", "features may improve over time. when terms change, the app should make the updated version easy to review.")
            ]
        case .privacy:
            [
                ("data we save", "marbled stores your account session, subjects, notebooks, scanned pages, typed notes, study state, and optional voice samples on device for this demo build."),
                ("scans and text", "scanned notes are processed to extract readable text, tables, diagrams, and subject labels so pages can be filed into notebooks."),
                ("voice setup", "voice recording is optional. if you use it, the app stores short samples and transcripts so reading features can personalize playback."),
                ("sign in", "email sign in is local in this build. apple and google require production secrets before they can connect."),
                ("control", "you can skip voice setup, edit notes, add subjects, and review saved account information from settings.")
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

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.8)) { timeline in
            let wordIndex = Int(timeline.date.timeIntervalSinceReferenceDate / 1.8) % max(words.count, 1)
            let word = words.isEmpty ? "" : words[wordIndex]
            Text(word)
                .id(wordIndex)
                .font(.system(.callout, design: wordIndex.isMultiple(of: 2) ? .serif : .rounded, weight: .semibold))
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
                .animation(.spring(response: 0.48, dampingFraction: 0.78), value: wordIndex)
        }
        .frame(minWidth: 106, minHeight: 34)
        .clipped()
    }
}
