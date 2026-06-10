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

                RoundedRectangle(cornerRadius: 22, style: .continuous)
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
                    .shadow(color: .black.opacity(isPressed ? 0.12 : 0.28), radius: isPressed ? 5 : 16, y: isPressed ? 4 : 16)

                SpeckledCompositionTexture()
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .opacity(0.88)

                CoverFiberTexture()
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .blendMode(.softLight)

                PaperGrain(density: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .blendMode(.softLight)

                movingSheen
                notebookSpine
                coverDepth
                parallaxEdgeLight

                VStack(spacing: 10) {
                    labelPlate
                    SubjectTape(subject: notebook.subject, accent: NotebookTheme.accent(notebook.accent))
                        .padding(.top, 18)
                    Spacer()
                    OpenCornerCue(isPressed: isPressed)
                        .padding(.trailing, 14)
                        .padding(.bottom, 14)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.top, 16)
                .offset(x: dragOffset.width / 22, y: dragOffset.height / 22)
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

    private var notebookSpine: some View {
        HStack {
            UnevenRoundedRectangle(cornerRadii: .init(topLeading: 22, bottomLeading: 22), style: .continuous)
                .fill(Color(red: 0.035, green: 0.034, blue: 0.032))
                .frame(width: 40)
                .overlay {
                    LinearGradient(
                        colors: [.white.opacity(0.08), .clear, .black.opacity(0.24)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.05))
                        .frame(width: 2)
                        .padding(.vertical, 16)
                }
                .overlay(alignment: .trailing) {
                    Capsule()
                        .fill(.black.opacity(0.58))
                        .frame(width: 2)
                        .padding(.vertical, 12)
                        .offset(x: -2)
                }
            Spacer()
        }
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

    private var labelPlate: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("composition")
                    Text("book")
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                Spacer()
            }
            HStack(spacing: 8) {
                CompositionBadge(text: "80\nsheets")
                CompositionBadge(text: "college\nruled")
                Spacer()
            }
            VStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule()
                        .fill(.black.opacity(0.22))
                        .frame(height: 1)
                }
            }
        }
        .foregroundStyle(.black.opacity(0.76))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 148)
        .background(.white, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.black.opacity(0.22), lineWidth: 1)
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

    private var coverDepth: some View {
        VStack {
            Spacer()
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.black.opacity(0.22))
                .frame(height: 12)
                .blur(radius: 1)
                .offset(y: 6)
        }
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

private struct SubjectTape: View {
    var subject: String
    var accent: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(NotebookTheme.paper.opacity(0.96))
                .overlay {
                    PaperGrain(density: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .opacity(0.36)
                }
            HStack(spacing: 8) {
                Circle()
                    .fill(accent.opacity(0.86))
                    .frame(width: 9, height: 9)
                Text(subject)
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundStyle(NotebookTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.64)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13)
        }
        .frame(width: 160, height: 42)
        .rotationEffect(.degrees(-4))
        .shadow(color: .black.opacity(0.16), radius: 7, y: 4)
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(.black.opacity(0.13), lineWidth: 0.8)
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
            .fill(.white.opacity(isPressed ? 0.78 : 0.58))
            .frame(width: 54, height: 54)
            .rotationEffect(.degrees(isPressed ? -8 : 0))

            Image(systemName: "arrow.up.forward")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(NotebookTheme.ink.opacity(0.78))
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isPressed)
    }
}

private struct CoverFiberTexture: View {
    var body: some View {
        Canvas { context, size in
            for index in 0..<180 {
                let y = size.height * CGFloat((index * 29) % 101) / 100
                let x = size.width * CGFloat((index * 17) % 103) / 102
                var path = Path()
                path.move(to: CGPoint(x: x, y: y))
                path.addCurve(
                    to: CGPoint(x: x + CGFloat(26 + index % 22), y: y + CGFloat((index % 5) - 2)),
                    control1: CGPoint(x: x + 8, y: y - 2),
                    control2: CGPoint(x: x + 18, y: y + 2)
                )
                context.stroke(
                    path,
                    with: .color(.white.opacity(index.isMultiple(of: 3) ? 0.08 : 0.035)),
                    style: StrokeStyle(lineWidth: 0.45, lineCap: .round)
                )
            }
        }
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
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(NotebookTheme.graphite)
            SpeckledCompositionTexture()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            HStack {
                UnevenRoundedRectangle(cornerRadii: .init(topLeading: 18, bottomLeading: 18), style: .continuous)
                    .fill(.black.opacity(0.88))
                    .frame(width: 18)
                    .overlay(alignment: .trailing) {
                        Capsule().fill(.white.opacity(0.18)).frame(width: 1)
                    }
                Spacer()
            }
            CompositionCoverLabel(subject: nil)
                .frame(width: 112, height: 104)
                .offset(y: -46)
        }
    }
}

private struct CompositionCoverLabel: View {
    var subject: String?

    var body: some View {
        VStack(spacing: 7) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("composition")
                    Text("book")
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                Spacer()
            }
            HStack(spacing: 7) {
                CompositionBadge(text: "80\nsheets")
                CompositionBadge(text: "college\nruled")
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
                    .font(.system(.caption, design: .serif, weight: .semibold))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.black.opacity(0.78))
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.black.opacity(0.18), lineWidth: 1)
        }
    }
}

private struct CompositionBadge: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 5.6, weight: .bold, design: .rounded))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.72)
            .frame(width: 31, height: 31)
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
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.96)))

            for index in 0..<920 {
                let x = size.width * CGFloat((index * 37) % 101) / 100
                let y = size.height * CGFloat((index * 61) % 103) / 102
                let length = CGFloat(3 + (index % 13))
                let angle = CGFloat((index * 17) % 180) * .pi / 180
                var mark = Path()
                mark.move(to: CGPoint(x: x - cos(angle) * length * 0.45, y: y - sin(angle) * length * 0.45))
                mark.addCurve(
                    to: CGPoint(x: x + cos(angle) * length, y: y + sin(angle) * length),
                    control1: CGPoint(x: x + sin(angle) * 2, y: y - cos(angle) * 2),
                    control2: CGPoint(x: x + cos(angle) * length * 0.4 - sin(angle) * 1.4, y: y + sin(angle) * length * 0.4 + cos(angle) * 1.4)
                )
                context.stroke(
                    mark,
                    with: .color(.white.opacity(index.isMultiple(of: 5) ? 0.96 : 0.72)),
                    style: StrokeStyle(lineWidth: CGFloat(0.75 + Double(index % 4) * 0.34), lineCap: .round, lineJoin: .round)
                )
            }

            for index in 0..<280 {
                let x = size.width * CGFloat((index * 19) % 97) / 96
                let y = size.height * CGFloat((index * 43) % 99) / 98
                let width = CGFloat(3 + index % 9)
                let height = CGFloat(2 + index % 5)
                let rect = CGRect(x: x, y: y, width: width, height: height)
                context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(index.isMultiple(of: 3) ? 0.34 : 0.18)))
            }

            for index in 0..<190 {
                let x = size.width * CGFloat((index * 71) % 103) / 102
                let y = size.height * CGFloat((index * 29) % 107) / 106
                let side = CGFloat(2 + index % 6)
                var chip = Path()
                chip.move(to: CGPoint(x: x, y: y))
                chip.addLine(to: CGPoint(x: x + side, y: y + side * 0.2))
                chip.addLine(to: CGPoint(x: x + side * 0.68, y: y + side))
                chip.addLine(to: CGPoint(x: x - side * 0.24, y: y + side * 0.7))
                chip.closeSubpath()
                context.fill(chip, with: .color(.white.opacity(0.68)))
            }
        }
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
