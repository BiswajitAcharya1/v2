import SwiftUI

struct LivingPaperBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    NotebookTheme.field,
                    Color(red: 0.91, green: 0.895, blue: 0.85),
                    Color(red: 0.94, green: 0.925, blue: 0.89)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LiquidLightField()
                .blendMode(.plusLighter)
                .opacity(0.7)

            PaperGrain()
                .opacity(0.36)
                .blendMode(.multiply)
        }
    }
}

struct LiquidLightField: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let first = CGPoint(
                    x: size.width * (0.18 + 0.18 * sin(t * 0.12)),
                    y: size.height * (0.16 + 0.08 * cos(t * 0.17))
                )
                let second = CGPoint(
                    x: size.width * (0.78 + 0.12 * cos(t * 0.1)),
                    y: size.height * (0.66 + 0.12 * sin(t * 0.14))
                )
                glow(context: context, center: first, radius: min(size.width, size.height) * 0.42, color: Color.white.opacity(0.46))
                glow(context: context, center: second, radius: min(size.width, size.height) * 0.36, color: Color(red: 0.72, green: 0.82, blue: 0.78).opacity(0.22))
            }
        }
    }

    private func glow(context: GraphicsContext, center: CGPoint, radius: CGFloat, color: Color) {
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .radialGradient(
                Gradient(colors: [color, .clear]),
                center: center,
                startRadius: 0,
                endRadius: radius
            )
        )
    }
}

struct PaperGrain: View {
    var density: Int = 520

    var body: some View {
        Canvas { context, size in
            for index in 0..<density {
                let x = size.width * CGFloat((index * 47) % 103) / 103
                let y = size.height * CGFloat((index * 83) % 107) / 107
                let alpha = index.isMultiple(of: 3) ? 0.08 : 0.045
                let rect = CGRect(x: x, y: y, width: 0.8, height: 0.8)
                context.fill(Path(ellipseIn: rect), with: .color(NotebookTheme.ink.opacity(alpha)))
            }
        }
    }
}

struct InteractiveSheen: View {
    var progress: CGFloat
    var cornerRadius: CGFloat

    var body: some View {
        LinearGradient(
            colors: [.clear, .white.opacity(0.32), .clear],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: 90)
        .rotationEffect(.degrees(22))
        .offset(x: -160 + progress * 320)
        .blur(radius: 0.3)
        .blendMode(.screen)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
