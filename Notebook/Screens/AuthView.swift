import SwiftUI

struct AuthView: View {
    @Environment(NotebookStore.self) private var store
    @State private var appeared = false
    @State private var drift = false

    var body: some View {
        ZStack {
            NotebookTheme.field.ignoresSafeArea()

            TimelineView(.animation) { timeline in
                let seconds = timeline.date.timeIntervalSinceReferenceDate
                AuthMotionField(seconds: seconds)
                    .opacity(0.75)
                    .ignoresSafeArea()
            }

            VStack(spacing: 28) {
                Spacer()

                ZStack {
                    ForEach(0..<3) { index in
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(index == 0 ? NotebookTheme.ink : NotebookTheme.paper)
                            .frame(width: 214, height: 286)
                            .rotationEffect(.degrees(Double(index - 1) * 7 + (drift ? 1.4 : -1.2)))
                            .offset(x: CGFloat(index - 1) * 18, y: CGFloat(index) * 8)
                            .shadow(color: .black.opacity(0.11), radius: 18, y: 9)
                    }

                    VStack(spacing: 10) {
                        Text("notebook")
                            .font(.notebookTitle)
                            .foregroundStyle(NotebookTheme.ink)
                        Text("smart composition books for studying")
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(NotebookTheme.muted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(22)
                    .frame(width: 170)
                    .background(NotebookTheme.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(.black.opacity(0.16), lineWidth: 1)
                    }
                }
                .scaleEffect(appeared ? 1 : 0.92)
                .opacity(appeared ? 1 : 0)

                GlassSurface(radius: 24, padding: 18, interactive: true) {
                    VStack(spacing: 14) {
                        Text("your shelf starts here")
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                            .foregroundStyle(NotebookTheme.ink)
                        Text("scan notes, sort them into notebooks, and study only what matters.")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(NotebookTheme.muted)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)

                        Button {
                            store.signIn()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "apple.logo")
                                Text("sign in with apple")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PillButtonStyle())
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 26)
                .offset(y: appeared ? 0 : 24)
                .opacity(appeared ? 1 : 0)

                Spacer()
            }
            .padding(.bottom, 24)
        }
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.82).delay(0.1)) {
                appeared = true
            }
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }
}

private struct AuthMotionField: View {
    var seconds: TimeInterval

    var body: some View {
        Canvas { context, size in
            for index in 0..<9 {
                let phase = CGFloat(seconds) * 0.22 + CGFloat(index)
                let x = size.width * (0.12 + CGFloat(index % 3) * 0.34) + sin(phase) * 22
                let y = size.height * (0.12 + CGFloat(index / 3) * 0.26) + cos(phase * 0.8) * 18
                let rect = CGRect(x: x, y: y, width: 118, height: 2)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(NotebookTheme.blueLine.opacity(0.28)))
            }
        }
    }
}
