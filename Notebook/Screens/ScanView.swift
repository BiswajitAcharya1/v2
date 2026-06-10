import SwiftUI

struct ScanView: View {
    @Environment(NotebookStore.self) private var store
    @State private var isRunning = false
    @State private var pageFlying = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.08, green: 0.08, blue: 0.075), Color(red: 0.28, green: 0.27, blue: 0.24)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    scannerStage(seconds: t)
                }

                VStack(spacing: 18) {
                    Spacer()
                    phasePanel
                    captureButton
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 34)
            }
            .navigationTitle("scan")
            .toolbarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    private func scannerStage(seconds: TimeInterval) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(NotebookTheme.paper.opacity(0.92))
                .frame(width: 292, height: 410)
                .rotationEffect(.degrees(pageFlying ? -9 : 1.5))
                .offset(y: pageFlying ? -210 : -16)
                .scaleEffect(pageFlying ? 0.54 : 1)
                .opacity(pageFlying ? 0.82 : 1)
                .overlay {
                    PaperRules()
                        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                        .opacity(0.9)
                }
                .shadow(color: .black.opacity(0.26), radius: 22, y: 16)

            EdgeGuide(seconds: seconds, phase: store.scanPhase)
                .frame(width: 318, height: 438)
                .offset(y: -16)

            if store.scanPhase != .framing {
                CaptureGlow(seconds: seconds)
                    .frame(width: 292, height: 410)
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .offset(y: -16)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.spring(response: 0.75, dampingFraction: 0.8), value: pageFlying)
        .animation(.spring(response: 0.55, dampingFraction: 0.86), value: store.scanPhase)
    }

    private var phasePanel: some View {
        GlassSurface(radius: 24, padding: 18, interactive: true) {
            VStack(spacing: 12) {
                HStack {
                    Label(store.scanPhase.caption, systemImage: icon(for: store.scanPhase))
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                    Spacer()
                    if store.scanPhase == .sorted {
                        Text("math")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(NotebookTheme.paper, in: Capsule())
                    }
                }
                .foregroundStyle(.white)

                HStack(spacing: 8) {
                    ForEach(ScanPhase.allCases) { phase in
                        Capsule()
                            .fill(stepIsActive(phase) ? .white : .white.opacity(0.2))
                            .frame(height: 5)
                    }
                }
            }
        }
    }

    private var captureButton: some View {
        Button {
            guard !isRunning else {
                store.resetScan()
                pageFlying = false
                isRunning = false
                return
            }
            isRunning = true
            pageFlying = false
            Task { @MainActor in
                await store.runDemoScan()
                pageFlying = true
                try? await Task.sleep(for: .seconds(1.2))
                isRunning = false
            }
        } label: {
            Image(systemName: isRunning ? "arrow.counterclockwise" : "camera.viewfinder")
                .font(.system(size: 24, weight: .bold))
                .frame(width: 74, height: 74)
        }
        .buttonStyle(CircleButtonStyle(tint: .white, foreground: NotebookTheme.ink))
        .accessibilityLabel(isRunning ? "reset scan" : "capture page")
    }

    private func icon(for phase: ScanPhase) -> String {
        switch phase {
        case .framing: "viewfinder"
        case .capturing: "sparkles"
        case .processing: "wand.and.rays"
        case .organizing: "tray.and.arrow.down.fill"
        case .sorted: "checkmark.seal.fill"
        }
    }

    private func stepIsActive(_ phase: ScanPhase) -> Bool {
        guard let current = ScanPhase.allCases.firstIndex(of: store.scanPhase),
              let target = ScanPhase.allCases.firstIndex(of: phase) else { return false }
        return target <= current
    }
}

private struct EdgeGuide: View {
    var seconds: TimeInterval
    var phase: ScanPhase

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 18
            let corner: CGFloat = 44
            let alpha = phase == .framing ? 0.88 : 0.55
            let color = Color.white.opacity(alpha)
            var path = Path()

            path.move(to: CGPoint(x: inset, y: inset + corner))
            path.addLine(to: CGPoint(x: inset, y: inset))
            path.addLine(to: CGPoint(x: inset + corner, y: inset))

            path.move(to: CGPoint(x: size.width - inset - corner, y: inset))
            path.addLine(to: CGPoint(x: size.width - inset, y: inset))
            path.addLine(to: CGPoint(x: size.width - inset, y: inset + corner))

            path.move(to: CGPoint(x: inset, y: size.height - inset - corner))
            path.addLine(to: CGPoint(x: inset, y: size.height - inset))
            path.addLine(to: CGPoint(x: inset + corner, y: size.height - inset))

            path.move(to: CGPoint(x: size.width - inset - corner, y: size.height - inset))
            path.addLine(to: CGPoint(x: size.width - inset, y: size.height - inset))
            path.addLine(to: CGPoint(x: size.width - inset, y: size.height - inset - corner))

            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

            let sweepY = inset + CGFloat((sin(seconds * 1.4) + 1) / 2) * (size.height - inset * 2)
            var sweep = Path()
            sweep.move(to: CGPoint(x: inset + 24, y: sweepY))
            sweep.addLine(to: CGPoint(x: size.width - inset - 24, y: sweepY))
            context.stroke(sweep, with: .color(Color.white.opacity(0.38)), lineWidth: 2)
        }
    }
}

private struct CaptureGlow: View {
    var seconds: TimeInterval

    var body: some View {
        Canvas { context, size in
            let y = CGFloat((seconds * 0.75).truncatingRemainder(dividingBy: 1)) * size.height
            let rect = CGRect(x: 0, y: y - 34, width: size.width, height: 68)
            context.fill(Path(rect), with: .linearGradient(
                Gradient(colors: [.clear, .white.opacity(0.22), .clear]),
                startPoint: CGPoint(x: 0, y: rect.minY),
                endPoint: CGPoint(x: 0, y: rect.maxY)
            ))
        }
    }
}
