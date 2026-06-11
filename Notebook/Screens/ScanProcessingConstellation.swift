import SwiftUI

struct ProcessingModelConstellation: View {
    let phase: ScanPhase
    let active: Bool

    private var enabled: Bool {
        guard let index = ScanPhase.allCases.firstIndex(of: phase) else { return false }
        return index >= (ScanPhase.allCases.firstIndex(of: .processing) ?? 2)
    }

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height * 0.48)
            let alpha = enabled ? 1.0 : 0.34
            let drift = active ? CGFloat(6) : CGFloat(-6)
            let points = [
                CGPoint(x: size.width * 0.22, y: size.height * 0.25 + drift),
                CGPoint(x: size.width * 0.82, y: size.height * 0.34 - drift * 0.5),
                CGPoint(x: size.width * 0.76, y: size.height * 0.78 + drift * 0.35),
                CGPoint(x: size.width * 0.2, y: size.height * 0.72 - drift)
            ]

            for (index, point) in points.enumerated() {
                var connection = Path()
                connection.move(to: center)
                connection.addQuadCurve(
                    to: point,
                    control: CGPoint(
                        x: (center.x + point.x) / 2 + CGFloat(index.isMultiple(of: 2) ? 18 : -18),
                        y: (center.y + point.y) / 2 + CGFloat(index == 1 ? -16 : 12)
                    )
                )
                context.stroke(connection, with: .color(.white.opacity(0.2 * alpha)), style: StrokeStyle(lineWidth: 1, lineCap: .round))

                let radius = CGFloat([19, 17, 21, 18][index])
                let circle = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
                context.fill(circle, with: .color(.white.opacity(0.12 * alpha)))
                context.stroke(circle, with: .color(.white.opacity(0.28 * alpha)), lineWidth: 0.8)

                let label = Text(["ocr", "tbl", "3d", "ai"][index])
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8 * alpha))
                context.draw(label, at: point)
            }

            let core = Path(ellipseIn: CGRect(x: center.x - 12, y: center.y - 12, width: 24, height: 24))
            context.fill(core, with: .color(.white.opacity(0.16 * alpha)))
            context.stroke(core, with: .color(.white.opacity(0.34 * alpha)), lineWidth: 0.9)
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: active)
        .animation(.spring(response: 0.56, dampingFraction: 0.82), value: phase)
    }
}
