import SwiftUI

struct ComfortDisplayModifier: ViewModifier {
    let settings: ComfortSettings

    func body(content: Content) -> some View {
        content
            .saturation(settings.saturation)
            .contrast(settings.contrast)
            .brightness(settings.brightness)
            .overlay {
                ComfortPaperWash(settings: settings)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .transaction { transaction in
                if settings.reducesMotion {
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            }
    }
}

private struct ComfortPaperWash: View {
    let settings: ComfortSettings

    var body: some View {
        ZStack {
            Color(red: 0.98, green: 0.94, blue: 0.82)
                .opacity(settings.warmth)
                .blendMode(.multiply)

            Color(red: 0.94, green: 0.935, blue: 0.885)
                .opacity(settings.paperWash)
                .blendMode(.multiply)

            if settings.isEnabled(.paperGrain) || settings.isEnabled(.pageTexture) {
                PaperGrain(density: settings.textureDensity)
                    .opacity(settings.isEnabled(.batterySaver) ? 0.12 : 0.22)
                    .blendMode(.multiply)
            }

            if settings.isEnabled(.focusVignette) || settings.isEnabled(.eveningShade) {
                ComfortVignette(strength: settings.isEnabled(.eveningShade) ? 0.18 : 0.1)
            }

            if settings.isEnabled(.readingRuler) {
                ComfortReadingRuler()
                    .opacity(settings.isEnabled(.batterySaver) ? 0.08 : 0.13)
                    .blendMode(.multiply)
            }
        }
        .ignoresSafeArea()
    }
}

private struct ComfortVignette: View {
    let strength: Double

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(
                Path(rect),
                with: .radialGradient(
                    Gradient(colors: [.clear, NotebookTheme.ink.opacity(strength)]),
                    center: CGPoint(x: size.width / 2, y: size.height * 0.42),
                    startRadius: min(size.width, size.height) * 0.18,
                    endRadius: max(size.width, size.height) * 0.72
                )
            )
        }
        .blendMode(.multiply)
    }
}

private struct ComfortReadingRuler: View {
    var body: some View {
        VStack(spacing: 34) {
            ForEach(0..<20, id: \.self) { _ in
                Capsule()
                    .fill(NotebookTheme.ink.opacity(0.12))
                    .frame(height: 1)
            }
        }
        .padding(.horizontal, 26)
    }
}

extension View {
    func comfortDisplay(_ settings: ComfortSettings) -> some View {
        modifier(ComfortDisplayModifier(settings: settings))
    }
}
