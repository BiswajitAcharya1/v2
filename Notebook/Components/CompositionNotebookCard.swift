import SwiftUI

struct CompositionNotebookCard: View {
    let notebook: SubjectNotebook
    var namespace: Namespace.ID?
    var onOpen: (() -> Void)?

    @State private var dragOffset: CGSize = .zero
    @State private var isPressed = false
    @State private var float = false
    @State private var didPressHaptic = false

    private var rotationX: Double { -Double(dragOffset.height / 6.8) + (float ? 1.5 : -1.3) }
    private var rotationY: Double { Double(dragOffset.width / 6.2) + (float ? -1.7 : 1.4) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                pageBlockDepth

                CompositionCoverFace(
                    subject: notebook.subject,
                    cornerRadius: 22,
                    spineWidth: 42,
                    labelWidth: 158,
                    labelHeight: 126,
                    labelOffsetY: 16,
                    showCornerLift: true,
                    isPressed: isPressed
                )
                    .shadow(color: .black.opacity(isPressed ? 0.12 : 0.28), radius: isPressed ? 5 : 16, y: isPressed ? 4 : 16)

                movingSheen
                DirectionAwareTouchHighlight(offset: dragOffset, isActive: isPressed, cornerRadius: 22)
                    .blendMode(.screen)
                parallaxEdgeLight
            }
            .aspectRatio(0.72, contentMode: .fit)
            .rotation3DEffect(.degrees(rotationX), axis: (x: 1, y: 0, z: 0), perspective: 0.62)
            .rotation3DEffect(.degrees(rotationY), axis: (x: 0, y: 1, z: 0), perspective: 0.62)
            .scaleEffect(isPressed ? 0.96 : 1)
            .offset(y: float ? -5 : 4)
            .shadow(color: .black.opacity(isPressed ? 0.14 : 0.24), radius: isPressed ? 10 : 20, x: dragOffset.width / -18, y: isPressed ? 8 : 18)
            .animation(.spring(response: 0.35, dampingFraction: 0.72), value: dragOffset)
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isPressed)
            .animation(.easeInOut(duration: 4.2).repeatForever(autoreverses: true), value: float)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !didPressHaptic {
                            Haptics.press()
                            didPressHaptic = true
                        }
                        isPressed = true
                        dragOffset = CGSize(
                            width: max(min(value.translation.width, 40), -40),
                            height: max(min(value.translation.height, 40), -40)
                        )
                    }
                    .onEnded { value in
                        let moved = hypot(value.translation.width, value.translation.height)
                        isPressed = false
                        didPressHaptic = false
                        dragOffset = .zero
                        if moved < 10 {
                            Haptics.open()
                            onOpen?()
                        }
                    }
            )
            .onAppear {
                float = true
            }

        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(notebook.subject) notebook")
    }

    private var pageBlockDepth: some View {
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.82, green: 0.79, blue: 0.71))
                .offset(x: 6, y: 4)
            VStack(spacing: 4) {
                ForEach(0..<9, id: \.self) { index in
                    Capsule()
                        .fill(.black.opacity(index.isMultiple(of: 2) ? 0.11 : 0.06))
                        .frame(width: 8, height: 1)
                }
            }
            .padding(.trailing, -4)
        }
    }

    private var movingSheen: some View {
        LinearGradient(
            colors: [.clear, .white.opacity(0.2), .clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .rotationEffect(.degrees(18))
        .offset(x: dragOffset.width * 0.7 + (float ? 34 : -34))
        .blendMode(.screen)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var parallaxEdgeLight: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [.white.opacity(isPressed ? 0.36 : 0.18), .clear, .black.opacity(0.2)],
                    startPoint: UnitPoint(x: dragOffset.width > 0 ? 0 : 1, y: 0),
                    endPoint: UnitPoint(x: dragOffset.width > 0 ? 1 : 0, y: 1)
                ),
                lineWidth: 1.2
            )
            .padding(0.5)
    }
}

struct CompositionCoverFace: View {
    var subject: String?
    var cornerRadius: CGFloat
    var spineWidth: CGFloat
    var labelWidth: CGFloat
    var labelHeight: CGFloat
    var labelOffsetY: CGFloat
    var showCornerLift: Bool
    var isPressed: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.08, green: 0.08, blue: 0.075),
                            NotebookTheme.graphite,
                            Color(red: 0.12, green: 0.12, blue: 0.11)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            SpeckledCompositionTexture()
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .opacity(1)

            PaperGrain(density: 90)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .opacity(0.08)

            VStack {
                Spacer()
                RoundedRectangle(cornerRadius: max(12, cornerRadius - 4), style: .continuous)
                    .fill(.black.opacity(0.22))
                    .frame(height: 12)
                    .blur(radius: 1)
                    .offset(y: 6)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            HStack {
                CompositionSpine(cornerRadius: cornerRadius, width: spineWidth)
                Spacer()
            }

            VStack {
                CompositionCoverLabel(subject: subject, isLarge: labelWidth > 130)
                    .frame(width: labelWidth, height: labelHeight)
                    .padding(.top, labelOffsetY)
                Spacer()
                if showCornerLift {
                    OpenCornerCue(isPressed: isPressed)
                        .padding(.trailing, 14)
                        .padding(.bottom, 14)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }
}

private struct CompositionSpine: View {
    var cornerRadius: CGFloat
    var width: CGFloat

    var body: some View {
        UnevenRoundedRectangle(cornerRadii: .init(topLeading: cornerRadius, bottomLeading: cornerRadius), style: .continuous)
            .fill(Color(red: 0.012, green: 0.011, blue: 0.01))
            .frame(width: width)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.028))
                    .frame(width: max(1, width * 0.05))
                    .padding(.vertical, max(10, cornerRadius * 0.75))
            }
            .overlay(alignment: .trailing) {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(.black.opacity(0.96))
                        .frame(width: max(1.2, width * 0.07))
                    Rectangle()
                        .fill(.white.opacity(0.2))
                        .frame(width: max(1, width * 0.04))
                }
            }
    }
}

private struct OpenCornerCue: View {
    var isPressed: Bool

    var body: some View {
        ZStack {
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 18, bottomTrailing: 20),
                style: .continuous
            )
            .fill(
                LinearGradient(
                    colors: [
                        .white.opacity(isPressed ? 0.82 : 0.58),
                        .white.opacity(isPressed ? 0.42 : 0.24),
                        .black.opacity(0.1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 48, height: 48)
            .overlay(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: 12, y: 31))
                    path.addQuadCurve(to: CGPoint(x: 31, y: 12), control: CGPoint(x: 16, y: 15))
                }
                .stroke(.black.opacity(0.16), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
                .frame(width: 48, height: 48)
            }
            .shadow(color: .black.opacity(isPressed ? 0.16 : 0.1), radius: isPressed ? 4 : 2, x: -1, y: 2)
            .rotationEffect(.degrees(isPressed ? -11 : -4))
        }
        .opacity(isPressed ? 0.9 : 0.64)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isPressed)
    }
}

struct MinimalAppLogo: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.9),
                                Color(red: 0.89, green: 0.9, blue: 0.92)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Circle().stroke(.white.opacity(0.86), lineWidth: 1)
                    }
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(NotebookTheme.ink)
                    .frame(width: 38, height: 44)
                    .rotationEffect(.degrees(-8))
                    .overlay(alignment: .topTrailing) {
                        UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 10, topTrailing: 14), style: .continuous)
                            .fill(Color(red: 0.92, green: 0.93, blue: 0.95))
                            .frame(width: 16, height: 16)
                            .overlay {
                                PaperGrain(density: 24).opacity(0.18)
                            }
                    }
                    .overlay {
                        Canvas { context, size in
                            for index in 0..<9 {
                                let y = size.height * (0.24 + CGFloat(index) * 0.06)
                                var line = Path()
                                line.move(to: CGPoint(x: size.width * 0.25, y: y))
                                line.addLine(to: CGPoint(x: size.width * 0.66, y: y + CGFloat(index % 2) * 0.8))
                                context.stroke(line, with: .color(.white.opacity(0.28)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                            }
                            var mark = Path()
                            mark.move(to: CGPoint(x: size.width * 0.29, y: size.height * 0.72))
                            mark.addCurve(
                                to: CGPoint(x: size.width * 0.7, y: size.height * 0.66),
                                control1: CGPoint(x: size.width * 0.4, y: size.height * 0.58),
                                control2: CGPoint(x: size.width * 0.58, y: size.height * 0.82)
                            )
                            context.stroke(mark, with: .color(.white.opacity(0.72)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        }
                        .padding(5)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 5, y: 4)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct NotebookLogo: View {
    var isOpen = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(NotebookTheme.paper)
                .overlay {
                    VStack(spacing: 10) {
                        ForEach(0..<7, id: \.self) { index in
                            Capsule()
                                .fill(index == 0 ? NotebookTheme.redRule.opacity(0.38) : NotebookTheme.blueLine.opacity(0.42))
                                .frame(height: 1)
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .scaleEffect(isOpen ? 1 : 0.92)
                .offset(x: isOpen ? 22 : 0, y: isOpen ? 5 : 0)
                .rotation3DEffect(.degrees(isOpen ? -7 : 0), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.72)
                .shadow(color: .black.opacity(isOpen ? 0.12 : 0), radius: 8, y: 5)

            cover
                .rotation3DEffect(.degrees(isOpen ? -42 : 0), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.72)
                .offset(x: isOpen ? -18 : 0, y: isOpen ? 3 : 0)
                .shadow(color: .black.opacity(isOpen ? 0.18 : 0), radius: isOpen ? 12 : 0, x: -4, y: 8)
        }
        .animation(.spring(response: 0.78, dampingFraction: 0.76), value: isOpen)
    }

    private var cover: some View {
        CompositionCoverFace(
            subject: nil,
            cornerRadius: 18,
            spineWidth: 20,
            labelWidth: 112,
            labelHeight: 104,
            labelOffsetY: 24,
            showCornerLift: false
        )
    }
}

private struct CompositionCoverLabel: View {
    var subject: String?
    var isLarge: Bool

    var body: some View {
        VStack(spacing: isLarge ? 8 : 7) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("composition")
                    Text("book")
                }
                .font(.system(size: isLarge ? 13 : 11, weight: .semibold, design: .rounded))
                Spacer()
            }
            HStack(spacing: isLarge ? 8 : 7) {
                CompositionBadge(text: "80\nsheets", size: isLarge ? 34 : 31)
                CompositionBadge(text: "college\nruled", size: isLarge ? 34 : 31)
                Spacer()
            }
            VStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule()
                        .fill(.black.opacity(0.22))
                        .frame(height: 1)
                }
            }
            if let subject {
                Text(subject)
                    .font(.system(size: isLarge ? 13 : 11, weight: .semibold, design: .serif))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .padding(.horizontal, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(.black.opacity(0.78))
        .padding(.horizontal, isLarge ? 12 : 10)
        .padding(.vertical, isLarge ? 10 : 9)
        .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.black.opacity(0.18), lineWidth: 1)
        }
    }
}

private struct CompositionBadge: View {
    var text: String
    var size: CGFloat = 31

    var body: some View {
        Text(text)
            .font(.system(size: size > 31 ? 6.1 : 5.6, weight: .bold, design: .rounded))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.68)
            .padding(3)
            .frame(width: size, height: size)
            .overlay {
                Circle().stroke(.black.opacity(0.62), lineWidth: 1)
            }
    }
}

struct LeatherNotebook: View {
    var color: Color
    var ribbon: Color

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(color)
                .overlay(LeatherTexture().clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                        .padding(6)
                }
                .shadow(color: .black.opacity(0.16), radius: 16, y: 10)

            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(ribbon)
                .frame(width: 10, height: 58)
                .offset(x: 28, y: 24)
        }
    }
}

struct SpeckledCompositionTexture: View {
    var body: some View {
        Image("CompositionMarble")
            .resizable()
            .scaledToFill()
            .overlay(Color.black.opacity(0.04).blendMode(.multiply))
    }
}

private struct LeatherTexture: View {
    var body: some View {
        Canvas { context, size in
            for index in 0..<150 {
                var path = Path()
                let x = size.width * CGFloat((index * 29) % 101) / 100
                let y = size.height * CGFloat((index * 47) % 101) / 100
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x + CGFloat(index % 17) - 8, y: y + CGFloat((index * 3) % 13) - 6))
                context.stroke(path, with: .color(.white.opacity(0.045)), lineWidth: 0.7)
            }
        }
    }
}
