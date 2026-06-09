import SwiftUI

struct CompositionNotebookCard: View {
    let notebook: SubjectNotebook
    var namespace: Namespace.ID?

    @State private var dragOffset: CGSize = .zero
    @State private var isPressed = false

    private var rotationX: Double { -Double(dragOffset.height / 12) }
    private var rotationY: Double { Double(dragOffset.width / 10) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(NotebookTheme.graphite)
                    .shadow(color: .black.opacity(isPressed ? 0.12 : 0.22), radius: isPressed ? 4 : 10, y: isPressed ? 3 : 9)

                MarbleTexture()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .opacity(0.94)

                notebookSpine

                VStack(spacing: 10) {
                    Text("composition book")
                        .font(.system(.caption2, design: .serif, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.72))
                    labelPlate
                    Spacer()
                    HStack {
                        progressStamp
                        Spacer()
                        Image(systemName: notebook.isPinned ? "pin.fill" : "sparkle.magnifyingglass")
                            .foregroundStyle(.black.opacity(0.58))
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                }
                .padding(.top, 16)
                .offset(x: dragOffset.width / 22, y: dragOffset.height / 22)
            }
            .aspectRatio(0.72, contentMode: .fit)
            .rotation3DEffect(.degrees(rotationX), axis: (x: 1, y: 0, z: 0), perspective: 0.62)
            .rotation3DEffect(.degrees(rotationY), axis: (x: 0, y: 1, z: 0), perspective: 0.62)
            .scaleEffect(isPressed ? 0.975 : 1)
            .animation(.spring(response: 0.35, dampingFraction: 0.72), value: dragOffset)
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isPressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isPressed = true
                        dragOffset = CGSize(
                            width: max(min(value.translation.width, 40), -40),
                            height: max(min(value.translation.height, 40), -40)
                        )
                    }
                    .onEnded { _ in
                        isPressed = false
                        dragOffset = .zero
                    }
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(notebook.lastActivity)
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(NotebookTheme.muted)
                ProgressView(value: notebook.progress)
                    .tint(NotebookTheme.accent(notebook.accent))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(notebook.subject) notebook")
    }

    private var notebookSpine: some View {
        HStack {
            Rectangle()
                .fill(.black.opacity(0.68))
                .frame(width: 18)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(.white.opacity(0.2))
                        .frame(width: 1)
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
            Rectangle()
                .fill(NotebookTheme.redRule.opacity(0.45))
                .frame(height: 1)
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

    private var progressStamp: some View {
        Text("\(Int(notebook.progress * 100))%")
            .font(.system(.caption, design: .monospaced, weight: .semibold))
            .foregroundStyle(.black.opacity(0.72))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.white.opacity(0.6), in: Capsule())
    }
}

struct MarbleTexture: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(0.88)))
            for index in 0..<54 {
                var path = Path()
                let y = size.height * CGFloat(index) / 54
                path.move(to: CGPoint(x: -18, y: y))
                for step in 0...18 {
                    let x = size.width * CGFloat(step) / 18
                    let wave = sin(CGFloat(step) * 0.9 + CGFloat(index) * 0.63) * 12
                    let drift = cos(CGFloat(index) * 0.37) * 9
                    path.addLine(to: CGPoint(x: x, y: y + wave + drift))
                }
                context.stroke(path, with: .color(.black.opacity(index.isMultiple(of: 3) ? 0.22 : 0.11)), lineWidth: index.isMultiple(of: 4) ? 2.1 : 1.1)
            }
            for index in 0..<34 {
                let rect = CGRect(
                    x: size.width * CGFloat((index * 17) % 100) / 100,
                    y: size.height * CGFloat((index * 29) % 100) / 100,
                    width: CGFloat(16 + (index % 5) * 7),
                    height: CGFloat(5 + (index % 3) * 3)
                )
                context.fill(Path(ellipseIn: rect), with: .color(.black.opacity(0.08)))
            }
        }
    }
}
