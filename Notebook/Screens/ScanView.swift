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
                    colors: [
                        scannerTopColor,
                        scannerMidColor,
                        scannerBottomColor
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                TimelineView(.periodic(from: .now, by: 1.0 / 12.0)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    ZStack {
                        ScanAtmosphere(
                            seconds: t,
                            phase: store.scanPhase,
                            calm: store.comfortSettings.scannerIsQuiet
                        )
                        scannerStage(seconds: t)
                    }
                }

                VStack(spacing: 22) {
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
            RoundedRectangle(cornerRadius: 42, style: .continuous)
                .fill(.white.opacity(store.comfortSettings.scannerIsQuiet ? 0.035 : 0.045))
                .frame(width: 336, height: 466)
                .overlay {
                    RoundedRectangle(cornerRadius: 42, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                }

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(NotebookTheme.paper.opacity(0.92))
                .frame(width: 278, height: 394)
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
                .frame(width: 306, height: 422)
                .offset(y: -16)

            if store.scanPhase != .framing, !store.comfortSettings.isEnabled(.scannerQuietProcessing) {
                CaptureGlow(seconds: seconds)
                    .frame(width: 278, height: 394)
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .offset(y: -16)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.spring(response: 0.75, dampingFraction: 0.8), value: pageFlying)
        .animation(store.comfortSettings.reducesMotion ? nil : .spring(response: 0.55, dampingFraction: 0.86), value: store.scanPhase)
    }

    private var scannerTopColor: Color {
        store.comfortSettings.scannerIsQuiet
            ? Color(red: 0.105, green: 0.102, blue: 0.09)
            : Color(red: 0.045, green: 0.047, blue: 0.044)
    }

    private var scannerMidColor: Color {
        store.comfortSettings.scannerIsQuiet
            ? Color(red: 0.2, green: 0.188, blue: 0.16)
            : Color(red: 0.16, green: 0.155, blue: 0.14)
    }

    private var scannerBottomColor: Color {
        store.comfortSettings.scannerIsQuiet
            ? Color(red: 0.13, green: 0.122, blue: 0.105)
            : Color(red: 0.08, green: 0.078, blue: 0.072)
    }

    private var phasePanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 11) {
                Image(systemName: icon(for: store.scanPhase))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.86), in: Circle())
                    .contentTransition(.symbolEffect(.replace))

                VStack(alignment: .leading, spacing: 3) {
                    Text(store.scanPhase.caption)
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(phaseDetail)
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(.white.opacity(0.66))
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.14))
                    Capsule()
                        .fill(.white.opacity(0.84))
                        .frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 5)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.22), lineWidth: 0.8)
        }
        .animation(.spring(response: 0.48, dampingFraction: 0.84), value: store.scanPhase)
    }

    private var progress: CGFloat {
        guard let index = ScanPhase.allCases.firstIndex(of: store.scanPhase) else { return 0.2 }
        return CGFloat(index + 1) / CGFloat(ScanPhase.allCases.count)
    }

    private var phaseDetail: String {
        switch store.scanPhase {
        case .framing: "place the page inside the frame"
        case .capturing: "holding the edges"
        case .processing: "cleaning the page"
        case .organizing: "placing the page"
        case .sorted: "saved to notebook"
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
        case .capturing: "camera.aperture"
        case .processing: "text.viewfinder"
        case .organizing: "tray.and.arrow.down"
        case .sorted: "checkmark"
        }
    }

}

private struct FloatingScanButton: View {
    var isRunning: Bool
    var phase: ScanPhase

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(.white.opacity(isRunning ? 0.16 : 0.06), lineWidth: 1)
                    .frame(width: 82 + CGFloat(index * 16), height: 82 + CGFloat(index * 16))
                    .scaleEffect(isRunning ? 1.05 + CGFloat(index) * 0.035 : 0.94)
                    .opacity(isRunning ? 0.72 - Double(index) * 0.16 : 0.34)
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
                .frame(width: 76, height: 76)
                .overlay {
                    Circle().stroke(.white.opacity(0.86), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.2), radius: 16, y: 10)

            Image(systemName: isRunning ? "arrow.counterclockwise" : icon)
                .font(.system(size: 23, weight: .semibold))
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
        case .capturing: "camera.aperture"
        case .processing: "text.viewfinder"
        case .organizing: "tray.and.arrow.down"
        case .sorted: "checkmark"
        }
    }
}

private struct ScanAtmosphere: View {
    var seconds: TimeInterval
    var phase: ScanPhase
    var calm: Bool

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            for index in 0..<(calm ? 4 : 7) {
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
                    with: .color(.white.opacity(calm ? 0.025 : (phase == .framing ? 0.035 : 0.055))),
                    style: StrokeStyle(lineWidth: index.isMultiple(of: 3) ? 1 : 0.6, lineCap: .round)
                )
            }

            for index in 0..<(calm ? 3 : 9) {
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
