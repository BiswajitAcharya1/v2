import SwiftUI

struct CompositionNotebookCard: View {
    let notebook: SubjectNotebook
    var namespace: Namespace.ID?
    var onOpen: (() -> Void)?

    @State private var dragOffset: CGSize = .zero
    @State private var isPressed = false
    @State private var float = false

    private var rotationX: Double { -Double(dragOffset.height / 8) + (float ? 1.4 : -1.2) }
    private var rotationY: Double { Double(dragOffset.width / 7) + (float ? -1.6 : 1.3) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(NotebookTheme.graphite)
                    .shadow(color: .black.opacity(isPressed ? 0.12 : 0.28), radius: isPressed ? 5 : 16, y: isPressed ? 4 : 16)

                SpeckledCompositionTexture()
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .opacity(0.94)

                movingSheen
                notebookSpine
                coverDepth

                VStack(spacing: 10) {
                    Text("composition book")
                        .font(.system(.caption2, design: .serif, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.72))
                    labelPlate
                    Spacer()
                    Image(systemName: "arrow.up.forward.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white.opacity(isPressed ? 0.95 : 0.56))
                        .padding(.bottom, 16)
                }
                .padding(.top, 16)
                .offset(x: dragOffset.width / 22, y: dragOffset.height / 22)
            }
            .aspectRatio(0.72, contentMode: .fit)
            .rotation3DEffect(.degrees(rotationX), axis: (x: 1, y: 0, z: 0), perspective: 0.62)
            .rotation3DEffect(.degrees(rotationY), axis: (x: 0, y: 1, z: 0), perspective: 0.62)
            .scaleEffect(isPressed ? 0.96 : 1)
            .offset(y: float ? -5 : 4)
            .animation(.spring(response: 0.35, dampingFraction: 0.72), value: dragOffset)
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isPressed)
            .animation(.easeInOut(duration: 4.2).repeatForever(autoreverses: true), value: float)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isPressed = true
                        dragOffset = CGSize(
                            width: max(min(value.translation.width, 40), -40),
                            height: max(min(value.translation.height, 40), -40)
                        )
                    }
                    .onEnded { value in
                        let moved = hypot(value.translation.width, value.translation.height)
                        isPressed = false
                        dragOffset = .zero
                        if moved < 10 {
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
                .fill(.black.opacity(0.68))
                .frame(width: 28)
                .overlay(alignment: .trailing) {
                    Capsule()
                        .fill(.white.opacity(0.2))
                        .frame(width: 1)
                }
                .overlay {
                    VStack(spacing: 14) {
                        ForEach(0..<7, id: \.self) { _ in
                            Capsule()
                                .fill(.white.opacity(0.18))
                                .frame(width: 6, height: 18)
                        }
                    }
                    .padding(.vertical, 22)
                }
            Spacer()
        }
    }

    private var labelPlate: some View {
        VStack(spacing: 5) {
            Text("subject")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.black.opacity(0.55))
            Text(notebook.subject)
                .font(.system(.title2, design: .serif, weight: .semibold))
                .foregroundStyle(.black)
                .minimumScaleFactor(0.72)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 130)
        .background(NotebookTheme.paper, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
}

struct MinimalAppLogo: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.74))
                .overlay {
                    Circle().stroke(.white.opacity(0.82), lineWidth: 1)
                }
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(NotebookTheme.graphite)
                .frame(width: 28, height: 38)
                .overlay {
                    SpeckledCompositionTexture()
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(.black.opacity(0.8))
                        .frame(width: 5)
                }
                .rotationEffect(.degrees(-7))
                .shadow(color: .black.opacity(0.16), radius: 4, y: 3)
        }
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
                    .frame(width: 12)
                    .overlay(alignment: .trailing) {
                        Capsule().fill(.white.opacity(0.18)).frame(width: 1)
                    }
                Spacer()
            }
            VStack(spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("composition")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                        Text("book")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                    }
                    Spacer()
                    Image(systemName: "calendar")
                        .font(.system(size: 14, weight: .semibold))
                }
                HStack(spacing: 8) {
                    Circle().stroke(.black.opacity(0.72), lineWidth: 1.2).frame(width: 18, height: 18)
                    Circle().stroke(.black.opacity(0.72), lineWidth: 1.2).frame(width: 18, height: 18)
                    Spacer()
                }
            }
            .foregroundStyle(.black.opacity(0.78))
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(width: 104, height: 74)
            .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(.black.opacity(0.18), lineWidth: 1)
            }
            .offset(y: -38)
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

            Rectangle()
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

            for index in 0..<760 {
                let x = size.width * CGFloat((index * 37) % 101) / 100
                let y = size.height * CGFloat((index * 61) % 103) / 102
                let w = CGFloat(1 + (index % 5))
                let h = CGFloat(1 + ((index * 3) % 5))
                let angle = CGFloat(index % 12) * .pi / 7
                let transform = CGAffineTransform(translationX: x, y: y).rotated(by: angle)
                let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
                let path = Path(roundedRect: rect, cornerRadius: 1).applying(transform)
                context.fill(path, with: .color(.white.opacity(index.isMultiple(of: 4) ? 0.96 : 0.72)))
            }

            for index in 0..<160 {
                let x = size.width * CGFloat((index * 19) % 97) / 96
                let y = size.height * CGFloat((index * 43) % 99) / 98
                let rect = CGRect(x: x, y: y, width: CGFloat(8 + index % 7), height: CGFloat(2 + index % 4))
                context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.24)))
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
