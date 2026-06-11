import SwiftUI

struct CompositionNotebookCard: View {
    let notebook: SubjectNotebook
    var namespace: Namespace.ID?
    var onOpen: (() -> Void)?

    @State private var dragOffset: CGSize = .zero
    @State private var isPressed = false
    @State private var float = false
    @State private var didPressHaptic = false

    private var rotationX: Double { -Double(dragOffset.height / 7.4) + (float ? 1.35 : -1.15) }
    private var rotationY: Double { Double(dragOffset.width / 6.8) + (float ? -1.5 : 1.2) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                pageBlockDepth

                CompositionCoverFace(
                    subject: notebook.subject,
                    cornerRadius: 20,
                    spineWidth: 4.25,
                    labelWidth: 142,
                    labelHeight: 108,
                    labelOffsetY: 30
                )
                    .shadow(color: .black.opacity(isPressed ? 0.12 : 0.28), radius: isPressed ? 5 : 16, y: isPressed ? 4 : 16)

                movingSheen
                DirectionAwareTouchHighlight(offset: dragOffset, isActive: isPressed, cornerRadius: 20)
                    .blendMode(.screen)
                parallaxEdgeLight
            }
            .aspectRatio(0.72, contentMode: .fit)
            .rotation3DEffect(.degrees(rotationX), axis: (x: 1, y: 0, z: 0), perspective: 0.62)
            .rotation3DEffect(.degrees(rotationY), axis: (x: 0, y: 1, z: 0), perspective: 0.62)
            .scaleEffect(isPressed ? 0.975 : 1)
            .offset(y: float ? -5 : 4)
            .shadow(color: .black.opacity(isPressed ? 0.14 : 0.24), radius: isPressed ? 10 : 20, x: dragOffset.width / -18, y: isPressed ? 8 : 18)
            .animation(.spring(response: 0.52, dampingFraction: 0.84), value: dragOffset)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: isPressed)
            .animation(.easeInOut(duration: 5.8).repeatForever(autoreverses: true), value: float)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !didPressHaptic {
                            Haptics.press()
                            didPressHaptic = true
                        }
                        isPressed = true
                        dragOffset = CGSize(
                            width: max(min(value.translation.width, 46), -46),
                            height: max(min(value.translation.height, 46), -46)
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
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.9, green: 0.88, blue: 0.81),
                            Color(red: 0.68, green: 0.66, blue: 0.6)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .offset(x: 8, y: 5)
                .overlay(alignment: .trailing) {
                    PageEdgeStack(lineCount: 22)
                        .frame(width: 16)
                        .offset(x: 10, y: 5)
                }
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
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var parallaxEdgeLight: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
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
    var paperGrainDensity: Int = 90

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.04, green: 0.04, blue: 0.038),
                            Color(red: 0.115, green: 0.115, blue: 0.105),
                            Color(red: 0.045, green: 0.045, blue: 0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            SpeckledCompositionTexture()
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .opacity(0.98)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.18), .black.opacity(0.28)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.1
                )

            if paperGrainDensity > 0 {
                PaperGrain(density: paperGrainDensity)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .opacity(0.08)
            }

            VStack {
                Spacer()
                RoundedRectangle(cornerRadius: max(12, cornerRadius - 4), style: .continuous)
                    .fill(.black.opacity(0.22))
                    .frame(height: 12)
                    .blur(radius: 1)
                    .offset(y: 6)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            HStack(spacing: 0) {
                CompositionSpine(cornerRadius: cornerRadius, width: spineWidth)
                Spacer()
            }

            HStack {
                Spacer()
                CoverPageEdge(cornerRadius: cornerRadius)
                    .frame(width: 10)
            }
            .padding(.vertical, 12)
            .allowsHitTesting(false)

            VStack {
                HStack {
                    Spacer(minLength: spineWidth + 8)
                    CompositionCoverLabel(subject: subject, isLarge: labelWidth > 124)
                        .frame(width: labelWidth, height: labelHeight)
                    Spacer()
                }
                .padding(.top, labelOffsetY)
                Spacer()
            }
        }
    }
}

private struct CompositionSpine: View {
    var cornerRadius: CGFloat
    var width: CGFloat

    var body: some View {
        UnevenRoundedRectangle(cornerRadii: .init(topLeading: cornerRadius, bottomLeading: cornerRadius), style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.006, green: 0.006, blue: 0.005),
                        Color(red: 0.034, green: 0.032, blue: 0.029),
                        Color(red: 0.01, green: 0.01, blue: 0.009)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: width)
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(cornerRadii: .init(topLeading: cornerRadius, bottomLeading: cornerRadius), style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.055), .clear, .black.opacity(0.24)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(2.5, width * 0.42))
            }
            .overlay(alignment: .trailing) {
                Capsule()
                    .fill(.white.opacity(0.11))
                    .frame(width: 0.9)
                    .padding(.vertical, 14)
            }
    }
}

struct MinimalAppLogo: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: proxy.size.width * 0.28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.945, green: 0.955, blue: 0.95),
                                Color(red: 0.89, green: 0.9, blue: 0.88),
                                Color(red: 0.98, green: 0.94, blue: 0.87)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: proxy.size.width * 0.28, style: .continuous)
                            .stroke(.white.opacity(0.82), lineWidth: 1)
                    }

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: proxy.size.width * 0.16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.995, green: 0.99, blue: 0.94),
                                    Color(red: 0.9, green: 0.925, blue: 0.92)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            Canvas(rendersAsynchronously: true) { context, size in
                                let blue = Color(red: 0.53, green: 0.72, blue: 0.86).opacity(0.52)
                                let red = Color(red: 0.94, green: 0.44, blue: 0.46).opacity(0.45)
                                for index in 0..<6 {
                                    let y = size.height * (0.27 + CGFloat(index) * 0.092)
                                    var line = Path()
                                    line.move(to: CGPoint(x: size.width * 0.23, y: y))
                                    line.addCurve(
                                        to: CGPoint(x: size.width * 0.86, y: y + sin(CGFloat(index)) * 1.2),
                                        control1: CGPoint(x: size.width * 0.42, y: y - 1.2),
                                        control2: CGPoint(x: size.width * 0.68, y: y + 1.4)
                                    )
                                    context.stroke(line, with: .color(blue), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
                                }
                                var margin = Path()
                                margin.move(to: CGPoint(x: size.width * 0.32, y: size.height * 0.16))
                                margin.addCurve(
                                    to: CGPoint(x: size.width * 0.31, y: size.height * 0.86),
                                    control1: CGPoint(x: size.width * 0.34, y: size.height * 0.36),
                                    control2: CGPoint(x: size.width * 0.28, y: size.height * 0.64)
                                )
                                context.stroke(margin, with: .color(red), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: proxy.size.width * 0.11, topTrailing: proxy.size.width * 0.15), style: .continuous)
                                .fill(Color.white.opacity(0.74))
                                .frame(width: proxy.size.width * 0.22, height: proxy.size.width * 0.22)
                                .shadow(color: .black.opacity(0.08), radius: 2, x: -1, y: 1)
                        }

                    RoundedRectangle(cornerRadius: proxy.size.width * 0.07, style: .continuous)
                        .fill(NotebookTheme.ink)
                        .frame(width: proxy.size.width * 0.13)
                        .overlay {
                            PaperGrain(density: 52)
                                .opacity(0.25)
                                .clipShape(RoundedRectangle(cornerRadius: proxy.size.width * 0.07, style: .continuous))
                        }
                }
                .frame(width: proxy.size.width * 0.58, height: proxy.size.width * 0.68)
                .rotationEffect(.degrees(-7))
                .shadow(color: .black.opacity(0.16), radius: 6, x: 0, y: 5)
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
            spineWidth: 5.25,
            labelWidth: 102,
            labelHeight: 88,
            labelOffsetY: 30
        )
    }
}

private struct CompositionCoverLabel: View {
    var subject: String?
    var isLarge: Bool

    var body: some View {
        VStack(spacing: isLarge ? 7 : 6) {
            HStack(alignment: .top, spacing: 6) {
                Text("composition\nbook")
                    .font(.system(size: isLarge ? 12.2 : 9.2, weight: .semibold, design: .rounded))
                    .lineSpacing(-1)
                    .lineLimit(2)
                    .fixedSize(horizontal: true, vertical: true)
                Spacer(minLength: 4)
                Text("vellum")
                    .font(.system(size: isLarge ? 6.7 : 5.2, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
                    .frame(width: isLarge ? 42 : 32, height: isLarge ? 21 : 16)
                    .background(.black.opacity(0.84), in: RoundedRectangle(cornerRadius: isLarge ? 5 : 4, style: .continuous))
            }
            HStack(spacing: isLarge ? 7 : 6) {
                CompositionBadge(text: "80\nsheets", size: isLarge ? 30 : 25)
                CompositionBadge(text: "college\nruled", size: isLarge ? 30 : 25)
                Spacer()
            }
            VStack(spacing: isLarge ? 5 : 4) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(.black.opacity(0.22))
                        .frame(height: 1)
                }
            }
            if let subject {
                Text(subject)
                    .font(.system(size: isLarge ? 13 : 10.5, weight: .semibold, design: .serif))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .padding(.horizontal, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(.black.opacity(0.78))
        .padding(.horizontal, isLarge ? 11 : 9)
        .padding(.vertical, isLarge ? 9 : 8)
        .background(
            LinearGradient(
                colors: [.white, Color(red: 0.965, green: 0.96, blue: 0.93)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.black.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 1.5, y: 1)
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
            .padding(4)
            .frame(width: size, height: size)
            .foregroundStyle(.white)
            .background(.black.opacity(0.78), in: Circle())
            .overlay {
                Circle().stroke(.black.opacity(0.72), lineWidth: 1)
            }
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.22), lineWidth: 0.6)
                    .padding(2)
            }
    }
}

private struct CoverPageEdge: View {
    var cornerRadius: CGFloat

    var body: some View {
        UnevenRoundedRectangle(cornerRadii: .init(bottomTrailing: cornerRadius, topTrailing: cornerRadius), style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.92, green: 0.9, blue: 0.82).opacity(0.65),
                        Color(red: 0.64, green: 0.61, blue: 0.55).opacity(0.58)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .overlay {
                PageEdgeStack(lineCount: 18)
                    .opacity(0.78)
                    .padding(.vertical, 6)
            }
    }
}

private struct PageEdgeStack: View {
    var lineCount: Int

    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<lineCount, id: \.self) { index in
                Capsule()
                    .fill(Color.black.opacity(index.isMultiple(of: 2) ? 0.14 : 0.07))
                    .frame(height: 0.8)
                    .padding(.leading, CGFloat(index % 3))
            }
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
        Canvas(rendersAsynchronously: true) { context, size in
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
