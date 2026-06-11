import SwiftUI

struct ScanView: View {
    @Environment(NotebookStore.self) private var store
    @State private var isRunning = false
    @State private var pageFlying = false
    @State private var showingScanner = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.08, green: 0.08, blue: 0.075), Color(red: 0.28, green: 0.27, blue: 0.24)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                TimelineView(.periodic(from: .now, by: 1.0 / 12.0)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    ZStack {
                        ScanAtmosphere(seconds: t, phase: store.scanPhase)
                        scannerStage(seconds: t)
                    }
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
            .sheet(isPresented: $showingScanner) {
                DocumentScannerView { images in
                    guard let notebook = store.notebooks.first else { return }
                    Task {
                        isRunning = true
                        pageFlying = false
                        await store.scanCapturedImages(images, into: notebook.id)
                        Haptics.success()
                        pageFlying = true
                        try? await Task.sleep(for: .seconds(0.8))
                        isRunning = false
                    }
                } onCancel: {
                    Haptics.softTap()
                    isRunning = false
                }
                .ignoresSafeArea()
            }
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
                HStack(spacing: 11) {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.18))
                        Image(systemName: icon(for: store.scanPhase))
                            .font(.system(size: 16, weight: .bold))
                    }
                    .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.scanPhase.caption)
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                        Text(phaseDetail)
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white)

                ScannerPhaseRail(activePhase: store.scanPhase)
                ScannerModelRibbon(activePhase: store.scanPhase)
            }
        }
    }

    private var phaseDetail: String {
        switch store.scanPhase {
        case .framing: "line up the page. capture as many sheets as you need."
        case .capturing: "visionkit locks page edges and keeps the scan native."
        case .processing: "surya reads handwriting while sam and triposr inspect diagrams."
        case .organizing: "gemma classifies the notes and page structure."
        case .sorted: "the notebook is ready."
        }
    }

    private var captureButton: some View {
        Button {
            guard !isRunning else {
                Haptics.softTap()
                store.resetScan()
                pageFlying = false
                isRunning = false
                return
            }
            Haptics.open()
            showingScanner = true
        } label: {
            FloatingScanButton(isRunning: isRunning, phase: store.scanPhase)
        }
        .buttonStyle(.plain)
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

}

private struct ScannerModelRibbon: View {
    var activePhase: ScanPhase

    private let models: [(ScanPhase, String, String)] = [
        (.capturing, "doc.viewfinder", "visionkit"),
        (.processing, "text.viewfinder", "surya"),
        (.processing, "scope", "sam 3d"),
        (.processing, "cube.transparent", "triposr"),
        (.organizing, "sparkle.magnifyingglass", "gemma")
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(models, id: \.2) { model in
                    HStack(spacing: 6) {
                        Image(systemName: model.1)
                            .font(.system(size: 11, weight: .bold))
                        Text(model.2)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white.opacity(isActive(model.0) ? 0.96 : 0.44))
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(.white.opacity(isActive(model.0) ? 0.18 : 0.08), in: Capsule())
                    .overlay {
                        Capsule().stroke(.white.opacity(isActive(model.0) ? 0.3 : 0.12), lineWidth: 0.7)
                    }
                    .scaleEffect(activePhase == model.0 ? 1.02 : 1)
                    .animation(.spring(response: 0.38, dampingFraction: 0.78), value: activePhase)
                }
            }
            .padding(.horizontal, 2)
        }
        .mask {
            LinearGradient(colors: [.clear, .white, .white, .clear], startPoint: .leading, endPoint: .trailing)
        }
    }

    private func isActive(_ target: ScanPhase) -> Bool {
        guard let current = ScanPhase.allCases.firstIndex(of: activePhase),
              let target = ScanPhase.allCases.firstIndex(of: target) else { return false }
        return target <= current
    }
}

private struct ScannerPhaseRail: View {
    var activePhase: ScanPhase

    var body: some View {
        HStack(spacing: 7) {
            ForEach(ScanPhase.allCases) { phase in
                let active = stepIsActive(phase)
                Capsule()
                    .fill(active ? .white : .white.opacity(0.18))
                    .frame(width: activePhase == phase ? 34 : 8, height: 6)
                    .overlay {
                        if activePhase == phase {
                            Capsule()
                                .fill(.white.opacity(0.36))
                                .blur(radius: 4)
                        }
                    }
                    .animation(.spring(response: 0.42, dampingFraction: 0.76), value: activePhase)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stepIsActive(_ phase: ScanPhase) -> Bool {
        guard let current = ScanPhase.allCases.firstIndex(of: activePhase),
              let target = ScanPhase.allCases.firstIndex(of: phase) else { return false }
        return target <= current
    }
}

private struct FloatingScanButton: View {
    var isRunning: Bool
    var phase: ScanPhase

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(.white.opacity(isRunning ? 0.18 : 0.08), lineWidth: 1)
                    .frame(width: 86 + CGFloat(index * 18), height: 86 + CGFloat(index * 18))
                    .scaleEffect(isRunning ? 1.08 + CGFloat(index) * 0.04 : 0.92)
                    .opacity(isRunning ? 1 - Double(index) * 0.24 : 0.45)
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .white,
                            Color(red: 0.92, green: 0.94, blue: 0.98),
                            Color(red: 0.78, green: 0.82, blue: 0.9)
                        ],
                        center: .topLeading,
                        startRadius: 4,
                        endRadius: 86
                    )
                )
                .frame(width: 80, height: 80)
                .overlay {
                    Circle().stroke(.white.opacity(0.86), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.22), radius: 18, y: 12)

            Image(systemName: isRunning ? "arrow.counterclockwise" : icon)
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(NotebookTheme.ink)
                .rotationEffect(.degrees(isRunning ? 180 : 0))
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: 124, height: 124)
        .scaleEffect(isRunning ? 0.94 : 1)
        .rotation3DEffect(.degrees(isRunning ? -7 : 0), axis: (x: 0.4, y: 1, z: 0), perspective: 0.72)
        .animation(.spring(response: 0.42, dampingFraction: 0.72), value: isRunning)
        .animation(.spring(response: 0.44, dampingFraction: 0.78), value: phase)
    }

    private var icon: String {
        switch phase {
        case .framing: "camera.viewfinder"
        case .capturing: "sparkles"
        case .processing: "wand.and.rays"
        case .organizing: "tray.and.arrow.down.fill"
        case .sorted: "checkmark"
        }
    }
}

private struct ScanAtmosphere: View {
    var seconds: TimeInterval
    var phase: ScanPhase

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            for index in 0..<12 {
                let y = size.height * CGFloat(index) / 11
                let drift = CGFloat(sin(seconds * 0.42 + Double(index))) * 18
                var path = Path()
                path.move(to: CGPoint(x: -40, y: y + drift))
                path.addCurve(
                    to: CGPoint(x: size.width + 40, y: y - drift * 0.4),
                    control1: CGPoint(x: size.width * 0.25, y: y - 38),
                    control2: CGPoint(x: size.width * 0.7, y: y + 38)
                )
                context.stroke(
                    path,
                    with: .color(.white.opacity(phase == .framing ? 0.045 : 0.075)),
                    style: StrokeStyle(lineWidth: index.isMultiple(of: 3) ? 1.2 : 0.7, lineCap: .round)
                )
            }

            for index in 0..<20 {
                let x = size.width * CGFloat((index * 37) % 101) / 100
                let y = size.height * CGFloat((index * 53) % 97) / 100
                let pulse = CGFloat((sin(seconds * 0.9 + Double(index)) + 1) / 2)
                let rect = CGRect(x: x, y: y, width: 2 + pulse * 3, height: 2 + pulse * 3)
                context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.06 + Double(pulse) * 0.05)))
            }
        }
        .blur(radius: phase == .processing ? 0 : 0.3)
        .allowsHitTesting(false)
    }
}

private struct EdgeGuide: View {
    var seconds: TimeInterval
    var phase: ScanPhase

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
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
        Canvas(rendersAsynchronously: true) { context, size in
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
