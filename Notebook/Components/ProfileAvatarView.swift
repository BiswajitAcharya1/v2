import SwiftUI

struct ProfileAvatarView: View {
    var avatar: AvatarProfile
    var size: CGFloat = 48
    var animated = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(0.92),
                            NotebookTheme.accent(avatar.base).opacity(0.48),
                            NotebookTheme.accent(avatar.accent).opacity(0.38)
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: size
                    )
                )
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.72), lineWidth: max(0.8, size * 0.018))
                }

            AvatarDetailLayer(detail: avatar.detail, accent: NotebookTheme.accent(avatar.accent), animated: animated)
                .padding(size * 0.1)
                .clipShape(Circle())

            Image(systemName: avatar.symbol)
                .font(.system(size: size * 0.34, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(NotebookTheme.ink.opacity(0.88))
                .scaleEffect(animated ? 1.04 : 0.98)
        }
        .frame(width: size, height: size)
        .shadow(color: NotebookTheme.accent(avatar.base).opacity(0.18), radius: size * 0.16, y: size * 0.09)
        .accessibilityHidden(true)
    }
}

private struct AvatarDetailLayer: View {
    var detail: AvatarDetail
    var accent: Color
    var animated: Bool

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            switch detail {
            case .spark:
                for index in 0..<6 {
                    let angle = CGFloat(index) * .pi / 3 + (animated ? 0.2 : -0.2)
                    var path = Path()
                    path.move(to: CGPoint(x: center.x + cos(angle) * size.width * 0.18, y: center.y + sin(angle) * size.height * 0.18))
                    path.addLine(to: CGPoint(x: center.x + cos(angle) * size.width * 0.42, y: center.y + sin(angle) * size.height * 0.42))
                    context.stroke(path, with: .color(accent.opacity(0.36)), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
                }
            case .orbit:
                for index in 0..<3 {
                    var path = Path(ellipseIn: CGRect(
                        x: size.width * 0.18,
                        y: size.height * (0.28 + CGFloat(index) * 0.08),
                        width: size.width * 0.64,
                        height: size.height * 0.32
                    ))
                    let angle = Angle.degrees(Double(index) * 54 + (animated ? 12 : -12))
                    context.translateBy(x: center.x, y: center.y)
                    context.rotate(by: angle)
                    context.translateBy(x: -center.x, y: -center.y)
                    context.stroke(path, with: .color(accent.opacity(0.28)), lineWidth: 1)
                    context.translateBy(x: center.x, y: center.y)
                    context.rotate(by: -angle)
                    context.translateBy(x: -center.x, y: -center.y)
                    path = Path()
                }
            case .notes:
                var y = size.height * 0.28
                while y < size.height * 0.76 {
                    var path = Path()
                    path.move(to: CGPoint(x: size.width * 0.23, y: y))
                    path.addLine(to: CGPoint(x: size.width * 0.77, y: y + (animated ? 1 : -1)))
                    context.stroke(path, with: .color(accent.opacity(0.3)), lineWidth: 0.9)
                    y += size.height * 0.12
                }
            case .prism:
                var path = Path()
                path.move(to: CGPoint(x: center.x, y: size.height * 0.18))
                path.addLine(to: CGPoint(x: size.width * 0.78, y: center.y))
                path.addLine(to: CGPoint(x: center.x, y: size.height * 0.82))
                path.addLine(to: CGPoint(x: size.width * 0.22, y: center.y))
                path.closeSubpath()
                context.stroke(path, with: .color(accent.opacity(0.34)), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
            case .wave:
                for row in 0..<3 {
                    var path = Path()
                    let y = size.height * (0.32 + CGFloat(row) * 0.15)
                    path.move(to: CGPoint(x: size.width * 0.2, y: y))
                    path.addCurve(
                        to: CGPoint(x: size.width * 0.8, y: y),
                        control1: CGPoint(x: size.width * 0.36, y: y + (animated ? -6 : 6)),
                        control2: CGPoint(x: size.width * 0.62, y: y + (animated ? 6 : -6))
                    )
                    context.stroke(path, with: .color(accent.opacity(0.32)), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
                }
            case .grid:
                for index in 0..<4 {
                    let x = size.width * (0.24 + CGFloat(index) * 0.17)
                    var vertical = Path()
                    vertical.move(to: CGPoint(x: x, y: size.height * 0.24))
                    vertical.addLine(to: CGPoint(x: x + (animated ? 1 : -1), y: size.height * 0.76))
                    context.stroke(vertical, with: .color(accent.opacity(0.24)), lineWidth: 0.8)
                    let y = size.height * (0.24 + CGFloat(index) * 0.17)
                    var horizontal = Path()
                    horizontal.move(to: CGPoint(x: size.width * 0.24, y: y))
                    horizontal.addLine(to: CGPoint(x: size.width * 0.76, y: y + (animated ? -1 : 1)))
                    context.stroke(horizontal, with: .color(accent.opacity(0.24)), lineWidth: 0.8)
                }
            case .constellation:
                let points = [
                    CGPoint(x: size.width * 0.26, y: size.height * 0.34),
                    CGPoint(x: size.width * 0.46, y: size.height * 0.24),
                    CGPoint(x: size.width * 0.68, y: size.height * 0.42),
                    CGPoint(x: size.width * 0.55, y: size.height * 0.66),
                    CGPoint(x: size.width * 0.3, y: size.height * 0.58)
                ]
                var path = Path()
                for (index, point) in points.enumerated() {
                    if index == 0 {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                    let dot = CGRect(x: point.x - 1.8, y: point.y - 1.8, width: 3.6, height: 3.6)
                    context.fill(Path(ellipseIn: dot), with: .color(accent.opacity(0.52)))
                }
                context.stroke(path, with: .color(accent.opacity(0.3)), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
            case .bloom:
                for index in 0..<8 {
                    let angle = CGFloat(index) * .pi / 4 + (animated ? 0.14 : -0.14)
                    var petal = Path()
                    petal.addEllipse(in: CGRect(
                        x: center.x + cos(angle) * size.width * 0.18 - size.width * 0.075,
                        y: center.y + sin(angle) * size.height * 0.18 - size.height * 0.04,
                        width: size.width * 0.15,
                        height: size.height * 0.08
                    ))
                    context.stroke(petal, with: .color(accent.opacity(0.26)), lineWidth: 1)
                }
                context.fill(Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)), with: .color(accent.opacity(0.44)))
            case .contour:
                for index in 0..<4 {
                    let inset = CGFloat(index) * size.width * 0.07
                    var path = Path(ellipseIn: CGRect(
                        x: size.width * 0.2 + inset,
                        y: size.height * 0.22 + inset * 0.8,
                        width: size.width * 0.6 - inset * 1.4,
                        height: size.height * 0.54 - inset
                    ))
                    let angle = Angle.degrees(Double(index) * 11 + (animated ? 5 : -5))
                    context.translateBy(x: center.x, y: center.y)
                    context.rotate(by: angle)
                    context.translateBy(x: -center.x, y: -center.y)
                    context.stroke(path, with: .color(accent.opacity(0.18 + Double(index) * 0.035)), lineWidth: 0.9)
                    context.translateBy(x: center.x, y: center.y)
                    context.rotate(by: -angle)
                    context.translateBy(x: -center.x, y: -center.y)
                    path = Path()
                }
            }
        }
    }
}
