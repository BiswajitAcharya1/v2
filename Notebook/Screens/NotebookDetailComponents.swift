import SwiftUI

struct PageTermFocus: Identifiable, Hashable {
    let id = UUID()
    var term: String
    var page: NotebookPage
}

struct TermLensSheet: View {
    @Environment(NotebookStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let focus: PageTermFocus
    @State private var answer = ""
    @State private var awake = false

    private var livePage: NotebookPage {
        store.page(with: focus.page.id) ?? focus.page
    }

    var body: some View {
        ZStack {
            NotebookTheme.field.ignoresSafeArea()
            LivingPaperBackground().ignoresSafeArea().opacity(0.35)

            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(NotebookTheme.ink)
                        Image(systemName: symbol)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 52, height: 52)
                    .rotation3DEffect(.degrees(awake ? 10 : -8), axis: (x: 0.2, y: 1, z: 0), perspective: 0.8)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(focus.term.lowercased())
                            .font(.system(.title3, design: .serif, weight: .semibold))
                            .foregroundStyle(NotebookTheme.ink)
                            .lineLimit(2)
                        Text("page lens")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(NotebookTheme.muted)
                    }

                    Spacer(minLength: 0)

                    Button {
                        Haptics.softTap()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(CircleButtonStyle(tint: .white.opacity(0.72), foreground: NotebookTheme.ink))
                }

                NotebookPaperView(cornerRadius: 24) {
                    Text(answer)
                        .font(.system(.body, design: .rounded, weight: .regular))
                        .foregroundStyle(NotebookTheme.ink)
                        .lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
                .frame(minHeight: 140)

                HStack(spacing: 10) {
                    lensButton(symbol: "wand.and.rays", label: "prepare") {
                        Haptics.success()
                        store.preparePageForStudy(pageID: focus.page.id)
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                            answer = store.answer("explain \(focus.term)", for: livePage)
                        }
                    }

                    lensButton(symbol: "rectangle.stack.fill", label: "cards") {
                        Haptics.selection()
                        answer = store.flashcards(for: livePage)
                            .first { $0.front.localizedCaseInsensitiveContains(focus.term) || $0.back.localizedCaseInsensitiveContains(focus.term) }?
                            .back ?? store.explain(focus.term)
                    }

                    lensButton(symbol: "sparkles", label: "ask") {
                        Haptics.selection()
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                            answer = store.answer("what should i know about \(focus.term)", for: livePage)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .onAppear {
            answer = store.answer("explain \(focus.term)", for: livePage)
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                awake = true
            }
        }
    }

    private var symbol: String {
        if focus.term.contains("=") { return "function" }
        if focus.term.count > 42 { return "text.quote" }
        return "sparkle.magnifyingglass"
    }

    private func lensButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.48), in: Circle())
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(NotebookTheme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(.white.opacity(0.3), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.5), lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
    }
}

struct InteractiveStudyText: View {
    let text: String
    let keywords: [String]
    let formulas: [String]
    let scale: Double
    var onFocus: (String) -> Void
    @State private var awake = false

    private var lines: [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var terms: [String] {
        var seen = Set<String>()
        let visibleKeywords = keywords.filter { keyword in
            text.localizedCaseInsensitiveContains(keyword) && seen.insert(keyword.lowercased()).inserted
        }
        let visibleFormulas = formulas.filter { formula in
            text.localizedCaseInsensitiveContains(formula) && seen.insert(formula.lowercased()).inserted
        }
        return Array((visibleKeywords + visibleFormulas).prefix(8))
    }

    private var importantLineIndexes: Set<Int> {
        Set(lines.enumerated().compactMap { index, line in
            let hasKeyword = keywords.contains { line.localizedCaseInsensitiveContains($0) }
            let hasFormula = formulas.contains { line.localizedCaseInsensitiveContains($0) }
            return (hasKeyword || hasFormula || line.count > 48) && line.count < 140 ? index : nil
        }.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if !terms.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(terms, id: \.self) { term in
                        Button {
                            onFocus(term)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: term.contains("=") ? "function" : "tag.fill")
                                    .font(.system(size: 9 * scale, weight: .bold))
                                Text(term.lowercased())
                                    .font(.system(size: 10 * scale, weight: .semibold, design: .rounded))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .foregroundStyle(NotebookTheme.ink.opacity(0.76))
                            .padding(.horizontal, 8)
                            .frame(height: 28)
                            .background(.white.opacity(0.4), in: Capsule())
                            .overlay {
                                Capsule().stroke(.white.opacity(0.48), lineWidth: 0.6)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    if importantLineIndexes.contains(index) {
                        Button {
                            onFocus(line)
                        } label: {
                            Text(line)
                                .font(.system(size: 16 * scale, weight: .regular, design: .rounded))
                                .foregroundStyle(NotebookTheme.ink)
                                .lineSpacing(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(.white.opacity(awake ? 0.28 : 0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(line)
                            .font(.system(size: 16 * scale, weight: .regular, design: .rounded))
                            .foregroundStyle(NotebookTheme.ink)
                            .lineSpacing(6)
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.3).repeatForever(autoreverses: true)) {
                awake = true
            }
        }
    }
}

struct NotebookDetailAtmosphere: View {
    let accent: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 8.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas(rendersAsynchronously: true) { context, size in
                for index in 0..<9 {
                    var path = Path()
                    let y = size.height * (0.1 + CGFloat(index) * 0.105)
                    let drift = CGFloat(sin(t * 0.16 + Double(index))) * 18
                    path.move(to: CGPoint(x: -30, y: y + drift))
                    path.addCurve(
                        to: CGPoint(x: size.width + 40, y: y + CGFloat(cos(t * 0.12 + Double(index))) * 14),
                        control1: CGPoint(x: size.width * 0.28, y: y - 22 + drift),
                        control2: CGPoint(x: size.width * 0.68, y: y + 24 - drift)
                    )
                    context.stroke(path, with: .color(NotebookTheme.ink.opacity(0.025 + Double(index % 3) * 0.01)), lineWidth: 1)
                }

                for index in 0..<18 {
                    let x = size.width * CGFloat((index * 37) % 101) / 100
                    let y = size.height * CGFloat((index * 53) % 97) / 100
                    let offset = CGFloat(sin(t * 0.22 + Double(index))) * 5
                    let rect = CGRect(x: x + offset, y: y, width: 2.4, height: 2.4)
                    context.fill(Path(ellipseIn: rect), with: .color(accent.opacity(index.isMultiple(of: 3) ? 0.16 : 0.07)))
                }
            }
        }
    }
}

struct PageSignalDot: View {
    let symbol: String
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(NotebookTheme.ink.opacity(0.72))
        .padding(.horizontal, 7)
        .frame(height: 24)
        .background(.white.opacity(0.44), in: Capsule())
        .overlay {
            Capsule().stroke(.white.opacity(0.5), lineWidth: 0.6)
        }
    }
}

struct ScanRouteToast: View {
    let notice: ScanRouteNotice
    @State private var awake = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(NotebookTheme.ink)
                SpeckledCompositionTexture()
                    .clipShape(Circle())
                    .opacity(0.26)
                Image(systemName: notice.moved ? "arrow.turn.up.right" : "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)
            .rotation3DEffect(.degrees(awake ? 8 : -8), axis: (x: 0.2, y: 1, z: 0), perspective: 0.8)

            VStack(alignment: .leading, spacing: 3) {
                Text(notice.moved ? "filed in \(notice.toSubject)" : "saved in \(notice.toSubject)")
                    .font(.system(.subheadline, design: .serif, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)
                    .lineLimit(1)
                Text("\(notice.pageCount) \(notice.pageCount == 1 ? "page" : "pages")")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(NotebookTheme.muted)
            }

            Spacer(minLength: 0)

            MiniRouteNotebook(active: awake)
                .frame(width: 44, height: 54)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule().stroke(.white.opacity(0.62), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.1), radius: 16, y: 9)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                awake = true
            }
        }
    }
}

struct MiniRouteNotebook: View {
    let active: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(NotebookTheme.ink)
                .overlay {
                    SpeckledCompositionTexture()
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .opacity(0.72)
                }
                .overlay(alignment: .leading) {
                    UnevenRoundedRectangle(
                        cornerRadii: .init(topLeading: 8, bottomLeading: 8),
                        style: .continuous
                    )
                    .fill(.black.opacity(0.86))
                    .frame(width: 7)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(0.42), lineWidth: 0.8)
                }
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(.white)
                .frame(width: 22, height: 16)
                .offset(x: 14, y: -10)
        }
        .rotationEffect(.degrees(active ? 2.5 : -2.5))
        .scaleEffect(active ? 1.03 : 0.98)
    }
}

struct SmartPageActionDock: View {
    let page: NotebookPage
    let scale: Double
    let cardCount: Int
    let textScale: Double
    var onBoost: () -> Void
    var onStudy: () -> Void
    var onModel: () -> Void
    var onInk: () -> Void
    var onResize: () -> Void
    @State private var entered = false
    @State private var shimmer = false

    private var insight: SmartPageInsight {
        page.content.insight
    }

    private var styleSymbol: String {
        switch insight.handwriting.noteStyle {
        case .linear: "text.alignleft"
        case .diagram: "cube.transparent"
        case .table: "tablecells"
        case .formula: "function"
        case .mixed: "sparkles.rectangle.stack"
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 9) {
                IntelligenceScorePill(
                    symbol: styleSymbol,
                    value: "\(Int((insight.clarityScore * 100).rounded()))",
                    label: "clarity",
                    tint: NotebookTheme.accent(.green),
                    scale: scale
                )
                IntelligenceScorePill(
                    symbol: "pencil.and.scribble",
                    value: "\(Int((insight.handwriting.legibility * 100).rounded()))",
                    label: "writing",
                    tint: NotebookTheme.accent(.blue),
                    scale: scale
                )
                IntelligenceScorePill(
                    symbol: "cube.transparent",
                    value: "\(page.content.models.count)",
                    label: "models",
                    tint: NotebookTheme.accent(.plum),
                    scale: scale
                )
            }

            HStack(spacing: 10) {
                actionButton(symbol: "wand.and.rays", tint: NotebookTheme.accent(.amber), action: onBoost)
                    .accessibilityLabel("prepare page")

                actionButton(symbol: "sparkles", tint: NotebookTheme.ink, action: onStudy)
                    .accessibilityLabel("study page")

                actionButton(symbol: "waveform.path.ecg", tint: NotebookTheme.accent(.blue), action: onInk)
                    .accessibilityLabel("handwriting coach")

                actionButton(symbol: page.content.models.isEmpty ? "cube.transparent" : "arkit", tint: NotebookTheme.accent(.plum), action: onModel)
                    .accessibilityLabel("generate model")

                if let reconstruction = page.content.models.first?.reconstruction {
                    MiniModelOrbit(reconstruction: reconstruction)
                        .frame(width: 58, height: 38)
                        .transition(.scale(scale: 0.82).combined(with: .opacity))
                }

                actionButton(symbol: "textformat.size", tint: NotebookTheme.accent(.amber), action: onResize)
                    .accessibilityLabel("resize text")
                    .accessibilityValue("\(Int((textScale * 100).rounded())) percent")

                HStack(spacing: 6) {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 11 * scale, weight: .bold))
                    Text("\(cardCount)")
                        .font(.system(size: 12 * scale, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(NotebookTheme.ink.opacity(0.74))
                .frame(height: 38)
                .padding(.horizontal, 12)
                .background(.white.opacity(0.44), in: Capsule())
                .overlay {
                    Capsule().stroke(.white.opacity(0.5), lineWidth: 0.7)
                }

                Spacer(minLength: 0)

                if !insight.nextBestStep.isEmpty {
                    Text(insight.nextBestStep)
                        .font(.system(size: 11 * scale, weight: .semibold, design: .rounded))
                        .foregroundStyle(NotebookTheme.ink.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(.white.opacity(0.32), in: Capsule())
                        .overlay {
                            Capsule().stroke(.white.opacity(shimmer ? 0.66 : 0.34), lineWidth: 0.7)
                        }
                }
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.white.opacity(0.28))
                .overlay(alignment: shimmer ? .trailing : .leading) {
                    Capsule()
                        .fill(.white.opacity(0.22))
                        .frame(width: 80, height: 58)
                        .blur(radius: 16)
                        .offset(x: shimmer ? 24 : -24)
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.58), lineWidth: 0.8)
        }
        .scaleEffect(entered ? 1 : 0.97)
        .opacity(entered ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.58, dampingFraction: 0.84)) {
                entered = true
            }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                shimmer = true
            }
        }
    }

    private func actionButton(symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14 * scale, weight: .bold))
                .frame(width: 38, height: 38)
        }
        .buttonStyle(FloatingCircleButtonStyle(tint: tint, foreground: .white))
    }
}

struct MiniModelOrbit: View {
    let reconstruction: ModelReconstruction
    @State private var active = false

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let anchors = Array(reconstruction.anchors.prefix(5))
            ZStack {
                Capsule()
                    .fill(.white.opacity(0.36))
                    .overlay {
                        Capsule().stroke(.white.opacity(0.56), lineWidth: 0.7)
                    }

                Canvas(rendersAsynchronously: true) { context, size in
                    let radius = min(size.width, size.height) * 0.34
                    for index in anchors.indices {
                        let phase = Double(index) / Double(max(anchors.count, 1))
                        let angle = phase * .pi * 2 + (active ? 0.32 : -0.32)
                        let point = CGPoint(
                            x: center.x + cos(angle) * radius,
                            y: center.y + sin(angle) * radius * 0.58
                        )
                        var path = Path()
                        path.move(to: center)
                        path.addLine(to: point)
                        context.stroke(path, with: .color(NotebookTheme.ink.opacity(0.14)), lineWidth: 0.8)
                        context.fill(
                            Path(ellipseIn: CGRect(x: point.x - 2.4, y: point.y - 2.4, width: 4.8, height: 4.8)),
                            with: .color(NotebookTheme.ink.opacity(0.56))
                        )
                    }
                }

                Image(systemName: reconstruction.shape.symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(NotebookTheme.ink)
                    .frame(width: 24, height: 24)
                    .background(.white.opacity(0.62), in: Circle())
                    .rotation3DEffect(.degrees(active ? 12 : -12), axis: (x: 0.15, y: 1, z: 0), perspective: 0.8)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                    active = true
                }
            }
        }
        .accessibilityLabel("model ready")
    }
}

struct ModelForgeStrip: View {
    let plan: ModelForgePlan
    let scale: Double
    var action: () -> Void
    @State private var awake = false
    @State private var pressed = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.72)) {
                pressed = true
            }
            action()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(160))
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                    pressed = false
                }
            }
        } label: {
            HStack(spacing: 11) {
                ZStack {
                    Circle()
                        .fill(NotebookTheme.accent(plan.tint).opacity(0.15))
                    Circle()
                        .trim(from: 0, to: max(0.08, min(1, plan.score)))
                        .stroke(NotebookTheme.accent(plan.tint), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(awake ? -72 : -96))
                    Image(systemName: plan.symbol)
                        .font(.system(size: 15 * scale, weight: .bold))
                        .foregroundStyle(NotebookTheme.ink)
                        .rotation3DEffect(.degrees(awake ? 9 : -9), axis: (x: 0.2, y: 1, z: 0), perspective: 0.82)
                }
                .frame(width: 52, height: 52)
                .scaleEffect(pressed ? 0.93 : (awake ? 1.025 : 0.98))

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(plan.title)
                            .font(.system(size: 15 * scale, weight: .semibold, design: .serif))
                            .foregroundStyle(NotebookTheme.ink)
                            .lineLimit(1)
                        Text(plan.detail)
                            .font(.system(size: 10 * scale, weight: .semibold, design: .rounded))
                            .foregroundStyle(NotebookTheme.ink.opacity(0.66))
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                            .padding(.horizontal, 8)
                            .frame(height: 23)
                            .background(.white.opacity(0.38), in: Capsule())
                    }

                    HStack(spacing: 8) {
                        ForEach(Array(plan.steps.enumerated()), id: \.element.id) { index, step in
                            ModelForgeStepDot(step: step, scale: scale, awake: awake, index: index)
                        }
                    }
                }

                Spacer(minLength: 0)

                ZStack {
                    Circle()
                        .fill(plan.isReady ? NotebookTheme.ink : NotebookTheme.accent(plan.tint))
                    Image(systemName: plan.isReady ? "play.fill" : "sparkles")
                        .font(.system(size: 12 * scale, weight: .bold))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(pressed ? 18 : 0))
                }
                .frame(width: 38, height: 38)
            }
            .padding(10)
            .background(.white.opacity(0.42), in: Capsule())
            .overlay {
                Capsule().stroke(.white.opacity(0.64), lineWidth: 0.8)
            }
            .shadow(color: NotebookTheme.accent(plan.tint).opacity(0.1), radius: 12, y: 7)
        }
        .buttonStyle(.plain)
        .scaleEffect(pressed ? 0.985 : 1)
        .accessibilityLabel(plan.title)
        .onAppear {
            withAnimation(.spring(response: 0.72, dampingFraction: 0.84).delay(0.06)) {
                awake = true
            }
        }
    }
}

struct ModelForgeStepDot: View {
    let step: ModelForgeStep
    let scale: Double
    var awake: Bool
    var index: Int

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(step.isComplete ? NotebookTheme.accent(step.tint) : .white.opacity(0.46))
                Circle()
                    .trim(from: 0.08, to: 0.08 + min(0.84, max(0.08, step.progress * 0.84)))
                    .stroke(step.isComplete ? .white.opacity(0.5) : NotebookTheme.accent(step.tint), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .rotationEffect(.degrees(awake ? 118 + Double(index * 22) : -20))
                    .padding(4)
                Image(systemName: step.symbol)
                    .font(.system(size: 9 * scale, weight: .bold))
                    .foregroundStyle(step.isComplete ? .white : NotebookTheme.ink)
            }
            .frame(width: 30, height: 30)
            .offset(y: awake ? 0 : 4)

            Text(step.title)
                .font(.system(size: 9 * scale, weight: .semibold, design: .rounded))
                .foregroundStyle(NotebookTheme.ink.opacity(0.62))
                .lineLimit(1)
                .frame(width: 42)
        }
    }
}

struct InkCoachSheet: View {
    let page: NotebookPage
    var onPolish: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var awake = false

    private var handwriting: HandwritingAnalysis {
        page.content.insight.handwriting
    }

    private var alerts: [String] {
        let combined = page.content.insight.confusionAlerts + page.content.insight.cleanupSuggestions
        return Array(combined.prefix(5))
    }

    var body: some View {
        ZStack {
            NotebookTheme.field.ignoresSafeArea()
            LivingPaperBackground().ignoresSafeArea().opacity(0.42)

            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    InkFingerprint(handwriting: handwriting, active: awake)
                        .frame(width: 86, height: 86)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("ink coach")
                            .font(.system(.title2, design: .serif, weight: .semibold))
                            .foregroundStyle(NotebookTheme.ink)
                        Text(handwriting.coaching.isEmpty ? "page is ready to study." : handwriting.coaching)
                            .font(.system(.footnote, design: .rounded, weight: .medium))
                            .foregroundStyle(NotebookTheme.ink.opacity(0.68))
                            .lineLimit(3)
                    }

                    Spacer(minLength: 0)

                    Button {
                        Haptics.softTap()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(CircleButtonStyle(tint: .white.opacity(0.76), foreground: NotebookTheme.ink))
                }

                VStack(spacing: 10) {
                    InkMetricRow(label: "legibility", value: handwriting.legibility, symbol: "eye")
                    InkMetricRow(label: "spacing", value: handwriting.spacing, symbol: "arrow.left.and.right")
                    InkMetricRow(label: "structure", value: handwriting.structure, symbol: "square.stack.3d.up")
                    InkMetricRow(label: "ink", value: handwriting.inkDensity, symbol: "drop.fill")
                }

                HStack(spacing: 10) {
                    InkTrait(symbol: handwriting.noteStyle.symbolForInk, text: handwriting.noteStyle.rawValue)
                    InkTrait(symbol: "speedometer", text: handwriting.pace.rawValue)
                    InkTrait(symbol: "scribble.variable", text: handwriting.pressure.rawValue)
                }

                if let signature = handwriting.signature {
                    InkSignatureCard(signature: signature)
                }

                if !alerts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(alerts, id: \.self) { alert in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(NotebookTheme.ink.opacity(0.18))
                                    .frame(width: 6, height: 6)
                                Text(alert)
                                    .font(.system(.caption, design: .rounded, weight: .medium))
                                    .foregroundStyle(NotebookTheme.ink.opacity(0.72))
                                    .lineLimit(2)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.white.opacity(0.36), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(.white.opacity(0.55), lineWidth: 0.8)
                    }
                }

                Button {
                    onPolish()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "wand.and.rays")
                            .font(.system(size: 17, weight: .bold))
                        Text("clean page")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                }
                .buttonStyle(PillButtonStyle(tint: NotebookTheme.ink, foreground: .white))

                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                awake = true
            }
        }
    }
}

struct InkFingerprint: View {
    let handwriting: HandwritingAnalysis
    let active: Bool

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let rings = 7
            for index in 0..<rings {
                let progress = Double(index) / Double(max(rings - 1, 1))
                let radius = size.width * (0.17 + CGFloat(progress) * 0.32)
                var path = Path()
                let segments = 90
                for step in 0...segments {
                    let phase = Double(step) / Double(segments)
                    let angle = phase * .pi * 2
                    let wave = sin(angle * (2.4 + handwriting.structure * 3.0) + Double(index) + (active ? 0.45 : -0.45))
                    let pressure = 1 + wave * (0.045 + handwriting.inkDensity * 0.07)
                    let point = CGPoint(
                        x: center.x + cos(angle) * radius * pressure,
                        y: center.y + sin(angle) * radius * pressure * (0.78 + handwriting.spacing * 0.16)
                    )
                    if step == 0 {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }
                context.stroke(
                    path,
                    with: .color(NotebookTheme.ink.opacity(0.16 + handwriting.legibility * 0.08)),
                    style: StrokeStyle(lineWidth: 1 + handwriting.inkDensity * 1.4, lineCap: .round, lineJoin: .round)
                )
            }

            context.fill(
                Path(ellipseIn: CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)),
                with: .color(NotebookTheme.ink.opacity(0.22))
            )
        }
        .padding(8)
        .background(.white.opacity(0.42), in: Circle())
        .overlay {
            Circle().stroke(.white.opacity(0.62), lineWidth: 0.8)
        }
        .rotation3DEffect(.degrees(active ? 8 : -8), axis: (x: 0.2, y: 1, z: 0), perspective: 0.8)
    }
}

struct InkMetricRow: View {
    let label: String
    let value: Double
    let symbol: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(NotebookTheme.ink)
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.46), in: Circle())

            Text(label)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(NotebookTheme.ink)
                .frame(width: 78, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(NotebookTheme.ink.opacity(0.08))
                    Capsule()
                        .fill(NotebookTheme.ink.opacity(0.52))
                        .frame(width: proxy.size.width * min(1, max(0, value)))
                }
            }
            .frame(height: 8)

            Text("\(Int((value * 100).rounded()))")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(NotebookTheme.ink.opacity(0.58))
                .frame(width: 30, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(.white.opacity(0.32), in: Capsule())
        .overlay {
            Capsule().stroke(.white.opacity(0.5), lineWidth: 0.7)
        }
    }
}

struct InkTrait: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(NotebookTheme.ink.opacity(0.74))
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(.white.opacity(0.38), in: Capsule())
        .overlay {
            Capsule().stroke(.white.opacity(0.52), lineWidth: 0.7)
        }
    }
}

struct InkSignatureCard: View {
    let signature: HandwritingSignature
    @State private var awake = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(readinessColor.opacity(0.16))
                    Circle()
                        .trim(from: 0, to: awake ? max(0.08, signature.studyReadiness) : 0.08)
                        .stroke(readinessColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(NotebookTheme.ink)
                }
                .frame(width: 48, height: 48)
                .rotation3DEffect(.degrees(awake ? 8 : -8), axis: (x: 0.2, y: 1, z: 0), perspective: 0.8)

                VStack(alignment: .leading, spacing: 3) {
                    Text(signature.identity)
                        .font(.system(.headline, design: .serif, weight: .semibold))
                        .foregroundStyle(NotebookTheme.ink)
                    Text(signature.predictedIssue)
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(NotebookTheme.muted)
                        .lineLimit(2)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                signatureMetric("rhythm", signature.rhythm, NotebookTheme.accent(.blue))
                signatureMetric("steady", signature.consistency, NotebookTheme.accent(.green))
                signatureMetric("ready", signature.studyReadiness, readinessColor)
            }

            HStack(spacing: 6) {
                ForEach(signature.strengths.prefix(3), id: \.self) { strength in
                    InkTrait(symbol: "checkmark", text: strength)
                }
            }
        }
        .padding(14)
        .background(.white.opacity(0.36), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.58), lineWidth: 0.8)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                awake = true
            }
        }
    }

    private func signatureMetric(_ title: String, _ value: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(NotebookTheme.muted)
            Capsule()
                .fill(color.opacity(0.16))
                .frame(height: 7)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(color.opacity(0.82))
                        .frame(width: 68 * max(0.08, min(1, value)), height: 7)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var readinessColor: Color {
        if signature.studyReadiness > 0.72 { return NotebookTheme.accent(.green) }
        if signature.correctionNeed > 0.48 { return NotebookTheme.accent(.amber) }
        return NotebookTheme.ink
    }
}

extension NoteStyle {
    var symbolForInk: String {
        switch self {
        case .linear: "text.alignleft"
        case .diagram: "cube.transparent"
        case .table: "tablecells"
        case .formula: "function"
        case .mixed: "sparkles.rectangle.stack"
        }
    }
}

struct IntelligenceScorePill: View {
    let symbol: String
    let value: String
    let label: String
    let tint: Color
    let scale: Double
    @State private var awake = false

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.18))
                Image(systemName: symbol)
                    .font(.system(size: 11 * scale, weight: .bold))
            }
            .frame(width: 28, height: 28)
            .rotation3DEffect(.degrees(awake ? 7 : -7), axis: (x: 0.2, y: 1, z: 0), perspective: 0.7)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 14 * scale, weight: .semibold, design: .rounded))
                Text(label)
                    .font(.system(size: 9 * scale, weight: .medium, design: .rounded))
                    .foregroundStyle(NotebookTheme.ink.opacity(0.5))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(NotebookTheme.ink)
        .padding(.leading, 7)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, minHeight: 42)
        .background(.white.opacity(0.38), in: Capsule())
        .overlay {
            Capsule().stroke(.white.opacity(0.5), lineWidth: 0.7)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                awake = true
            }
        }
    }
}

struct PageInsightStrip: View {
    let insight: SmartPageInsight
    let scale: Double
    var onStudy: (String) -> Void
    @State private var glow = false

    var body: some View {
        if !insight.onlyWhatMatters.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    insightPill(symbol: "checkmark.seal.fill", text: percent(insight.clarityScore))
                    insightPill(symbol: "pencil.and.scribble", text: insight.handwriting.pace.rawValue)
                    insightPill(symbol: "clock.fill", text: "\(insight.estimatedReadMinutes)m")
                    ForEach(insight.detectedFeatures.prefix(4), id: \.self) { feature in
                        insightPill(symbol: symbol(for: feature), text: feature)
                    }
                    Button {
                        onStudy(insight.nextBestStep)
                    } label: {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13 * scale, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(NotebookTheme.ink, in: Circle())
                            .overlay {
                                Circle()
                                    .stroke(.white.opacity(glow ? 0.8 : 0.22), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 2)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    glow = true
                }
            }
        }
    }

    private func insightPill(symbol: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 10 * scale, weight: .bold))
            Text(text)
                .font(.system(size: 11 * scale, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(NotebookTheme.ink.opacity(0.78))
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(.white.opacity(0.42), in: Capsule())
        .overlay {
            Capsule().stroke(.white.opacity(0.5), lineWidth: 0.6)
        }
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func symbol(for feature: String) -> String {
        switch feature {
        case "formulas": "function"
        case "tables": "tablecells"
        case "models", "sketch": "cube.transparent"
        case "outline": "list.bullet"
        case "balanced page": "circle.grid.cross"
        default: "tag.fill"
        }
    }
}

struct PageCaptureDeck: View {
    let page: NotebookPage
    let cardCount: Int
    let scale: Double
    var onInk: () -> Void
    var onModel: () -> Void
    var onStudy: () -> Void
    var onRepair: () -> Void
    @State private var awake = false

    private var insight: SmartPageInsight {
        page.content.insight
    }

    private var primaryModel: DetectedModel? {
        page.content.models.first
    }

    var body: some View {
        VStack(spacing: 10) {
            if !insight.onlyWhatMatters.isEmpty {
                Button {
                    onStudy()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.system(size: 14 * scale, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(NotebookTheme.ink, in: Circle())
                            .rotation3DEffect(.degrees(awake ? 10 : -8), axis: (x: 0.2, y: 1, z: 0), perspective: 0.8)

                        Text(insight.onlyWhatMatters)
                            .font(.system(size: 13 * scale, weight: .semibold, design: .serif))
                            .foregroundStyle(NotebookTheme.ink)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)

                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(.white.opacity(0.38), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(.white.opacity(0.56), lineWidth: 0.8)
                    }
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 9) {
                CaptureMetricOrb(
                    symbol: "eye",
                    label: "ink",
                    value: insight.handwriting.legibility,
                    tint: NotebookTheme.accent(.blue),
                    awake: awake,
                    action: onInk
                )
                CaptureMetricOrb(
                    symbol: primaryModel == nil ? "cube.transparent" : "arkit",
                    label: "model",
                    value: primaryModel == nil ? 0 : primaryModel?.reconstruction?.confidence ?? 0.62,
                    tint: NotebookTheme.accent(.plum),
                    awake: awake,
                    action: onModel
                )
                CaptureMetricOrb(
                    symbol: "rectangle.stack.fill",
                    label: "\(cardCount)",
                    value: min(1, Double(cardCount) / 10.0),
                    tint: NotebookTheme.accent(.green),
                    awake: awake,
                    action: onStudy
                )
                CaptureMetricOrb(
                    symbol: "exclamationmark.triangle.fill",
                    label: "risk",
                    value: 1 - insight.retentionRisk,
                    tint: NotebookTheme.accent(.amber),
                    awake: awake,
                    action: onStudy
                )
            }

            scanReceipt

            if !page.content.tables.isEmpty || primaryModel != nil || !page.content.formulas.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if !page.content.tables.isEmpty {
                            captureChip(symbol: "tablecells", text: "\(page.content.tables.count)")
                        }
                        if !page.content.formulas.isEmpty {
                            captureChip(symbol: "function", text: "\(page.content.formulas.count)")
                        }
                        if let model = primaryModel {
                            captureChip(symbol: model.reconstruction?.shape.symbol ?? "cube.transparent", text: model.reconstruction?.shape.rawValue ?? "model")
                        }
                        ForEach(insight.memoryHooks.prefix(2), id: \.self) { hook in
                            captureChip(symbol: "pin.fill", text: hook)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.white.opacity(0.22))
                .overlay(alignment: awake ? .trailing : .leading) {
                    Capsule()
                        .fill(.white.opacity(0.2))
                        .frame(width: 72, height: 116)
                        .blur(radius: 18)
                        .offset(x: awake ? 22 : -22)
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.5), lineWidth: 0.8)
        }
        .scaleEffect(awake ? 1 : 0.97)
        .opacity(awake ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.68, dampingFraction: 0.84)) {
                awake = true
            }
        }
    }

    private var scanReceipt: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(confidenceTint.opacity(0.18))
                Circle()
                    .trim(from: 0.08, to: 0.08 + min(0.82, max(0.12, page.content.confidence * 0.82)))
                    .stroke(confidenceTint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(awake ? 126 : -22))
                    .padding(5)
                Image(systemName: page.content.sourceEngine == "typed" ? "pencil.line" : "text.viewfinder")
                    .font(.system(size: 11 * scale, weight: .bold))
                    .foregroundStyle(NotebookTheme.ink)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(engineLabel)
                    .font(.system(size: 12 * scale, weight: .semibold, design: .rounded))
                    .foregroundStyle(NotebookTheme.ink)
                    .lineLimit(1)
                Text(scanDetail)
                    .font(.system(size: 10 * scale, weight: .medium, design: .rounded))
                    .foregroundStyle(NotebookTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }

            Spacer(minLength: 0)

            if scanCanRepair {
                Button {
                    onRepair()
                } label: {
                    Image(systemName: "wand.and.rays")
                        .font(.system(size: 11 * scale, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(NotebookTheme.ink, in: Circle())
                        .rotation3DEffect(.degrees(awake ? 9 : -9), axis: (x: 0.2, y: 1, z: 0), perspective: 0.78)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("repair scan")
            } else {
                Text(scanIsRepaired ? "repaired" : "\(Int((page.content.confidence * 100).rounded()))")
                    .font(.system(size: 11 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(NotebookTheme.ink.opacity(0.72))
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(.white.opacity(0.4), in: Capsule())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white.opacity(0.32), in: Capsule())
        .overlay {
            Capsule().stroke(.white.opacity(0.48), lineWidth: 0.65)
        }
    }

    private var engineLabel: String {
        let engine = page.content.sourceEngine.lowercased()
        if engine.contains("surya") { return "surya ocr" }
        if engine.contains("fused") { return "vision fused" }
        if engine.contains("vision") { return "vision ocr" }
        if engine.contains("typed") { return "written notes" }
        if engine.contains("repaired") { return "layout repaired" }
        return engine.isEmpty ? "local ocr" : engine
    }

    private var scanDetail: String {
        let lines = max(1, page.content.cleanedText.split(separator: "\n").count)
        let pieces = [
            "\(lines) lines",
            page.content.tables.isEmpty ? nil : "\(page.content.tables.count) tables",
            page.content.models.isEmpty ? nil : "\(page.content.models.count) objects"
        ].compactMap(\.self)
        return pieces.joined(separator: "  ")
    }

    private var confidenceTint: Color {
        if page.content.confidence > 0.76 { return NotebookTheme.accent(.green) }
        if page.content.confidence > 0.48 { return NotebookTheme.accent(.amber) }
        return NotebookTheme.redRule
    }

    private var scanIsRepaired: Bool {
        page.content.sourceEngine.contains("repaired") || page.content.insight.detectedFeatures.contains("repaired")
    }

    private var scanCanRepair: Bool {
        !scanIsRepaired && page.content.sourceEngine != "typed" && (
            page.content.confidence < 0.72 ||
                page.content.insight.clarityScore < 0.72 ||
                page.content.insight.cleanupSuggestions.count > 1 ||
                page.content.sections.count <= 1
        )
    }

    private func captureChip(symbol: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 10 * scale, weight: .bold))
            Text(text)
                .font(.system(size: 10 * scale, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.66)
        }
        .foregroundStyle(NotebookTheme.ink.opacity(0.76))
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(.white.opacity(0.38), in: Capsule())
        .overlay {
            Capsule().stroke(.white.opacity(0.48), lineWidth: 0.6)
        }
    }
}

struct CaptureMetricOrb: View {
    let symbol: String
    let label: String
    let value: Double
    let tint: Color
    let awake: Bool
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(NotebookTheme.ink.opacity(0.08), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: min(1, max(0, value)))
                        .stroke(tint.opacity(0.86), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(NotebookTheme.ink)
                }
                .frame(width: 42, height: 42)
                .rotation3DEffect(.degrees(awake ? 8 : -7), axis: (x: 0.15, y: 1, z: 0), perspective: 0.8)

                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(NotebookTheme.ink.opacity(0.68))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(.white.opacity(0.34), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.48), lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct PageStackBackdrop: View {
    var pageCount: Int

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(NotebookTheme.paper.opacity(0.72 - Double(index) * 0.12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(.white.opacity(0.42), lineWidth: 0.8)
                    }
                    .offset(x: CGFloat(index + 1) * 5, y: CGFloat(index + 1) * 7)
                    .scaleEffect(1 - CGFloat(index) * 0.012)
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 4)
                    .opacity(pageCount > index ? 1 : 0)
            }
        }
        .allowsHitTesting(false)
    }
}

struct NotebookSpreadView<LeftContent: View, RightContent: View>: View {
    let left: NotebookPage
    let right: NotebookPage?
    let singlePage: Bool
    let leftContent: LeftContent
    let rightContent: RightContent
    let onSelect: (NotebookPage) -> Void
    @State private var touchOffset: CGSize = .zero
    @State private var touching = false

    init(
        left: NotebookPage,
        right: NotebookPage?,
        singlePage: Bool = false,
        @ViewBuilder leftContent: () -> LeftContent,
        @ViewBuilder rightContent: () -> RightContent,
        onSelect: @escaping (NotebookPage) -> Void
    ) {
        self.left = left
        self.right = right
        self.singlePage = singlePage
        self.leftContent = leftContent()
        self.rightContent = rightContent()
        self.onSelect = onSelect
    }

    var body: some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width > 560
            let pageGap = singlePage ? 0.0 : (isWide ? 18.0 : 2.0)

            ZStack {
                OpenCompositionSpreadBackground(singlePage: singlePage)

                HStack(spacing: pageGap) {
                    leftContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.leading, singlePage ? 30 : (isWide ? 34 : 18))
                        .padding(.trailing, singlePage ? 24 : (isWide ? 14 : 10))
                        .padding(.top, 38)
                        .padding(.bottom, 18)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelect(left)
                        }

                    if !singlePage {
                        rightContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(.leading, isWide ? 12 : 6)
                            .padding(.trailing, isWide ? 34 : 18)
                            .padding(.top, 38)
                            .padding(.bottom, 18)
                            .opacity(right == nil ? 0.42 : 1)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let right {
                                    onSelect(right)
                                }
                            }
                    }
                }
                .padding(.horizontal, isWide ? 4 : 0)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay {
                DirectionAwareTouchHighlight(offset: touchOffset, isActive: touching, cornerRadius: 30)
                    .opacity(0.42)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(.white.opacity(0.55), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.07), radius: 7, y: 4)
            .scaleEffect(touching ? 0.995 : 1)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !touching {
                            Haptics.softTap()
                        }
                        touching = true
                        touchOffset = CGSize(
                            width: max(min(value.translation.width, 46), -46),
                            height: max(min(value.translation.height, 46), -46)
                        )
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                            touching = false
                            touchOffset = .zero
                        }
                    }
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.78), value: touching)
            .animation(.spring(response: 0.32, dampingFraction: 0.78), value: touchOffset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 0)
        .padding(.vertical, 0)
    }
}

struct OpenCompositionSpreadBackground: View {
    var singlePage = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let gap: CGFloat = singlePage ? 0 : (size.width > 560 ? 18 : 2)
            let pageWidth = singlePage ? size.width : max(0, (size.width - gap) / 2)
            ZStack {
                bottomPageStack(size: size)
                if singlePage {
                    pageSurface(isLeft: true, singlePage: true)
                        .frame(width: pageWidth)
                        .padding(.horizontal, 0)
                } else {
                    HStack(spacing: gap) {
                        pageSurface(isLeft: true)
                            .frame(width: pageWidth)
                        pageSurface(isLeft: false)
                            .frame(width: pageWidth)
                    }
                    .padding(.horizontal, 0)
                }
                if !singlePage {
                    centerFold
                }
                pageCrown(size: size)
                bottomPageCurl(size: size)
                HStack {
                    sidePageEdges()
                    Spacer()
                    sidePageEdges()
                }
            }
        }
    }

    private func bottomPageStack(size: CGSize) -> some View {
        ZStack {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color(red: 0.72, green: 0.74, blue: 0.78).opacity(0.2 - Double(index) * 0.025))
                    .frame(width: max(0, size.width - CGFloat(index * 6)), height: max(0, size.height - CGFloat(index * 4)))
                    .offset(x: CGFloat(index % 2 == 0 ? -1 : 1) * CGFloat(index + 4), y: CGFloat(index + 3) * 3)
            }
        }
    }

    private func pageSurface(isLeft: Bool, singlePage: Bool = false) -> some View {
        let shape = UnevenRoundedRectangle(
            cornerRadii: singlePage
                ? .init(topLeading: 32, bottomLeading: 32, bottomTrailing: 32, topTrailing: 32)
                : .init(
                    topLeading: isLeft ? 30 : 10,
                    bottomLeading: isLeft ? 30 : 10,
                    bottomTrailing: isLeft ? 10 : 30,
                    topTrailing: isLeft ? 10 : 30
                ),
            style: .continuous
        )
        return shape
        .fill(
            LinearGradient(
                colors: [
                    Color(red: 0.965, green: 0.968, blue: 0.982),
                    Color(red: 0.94, green: 0.948, blue: 0.968),
                    Color(red: 0.905, green: 0.915, blue: 0.94)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(OpenCompositionRules(isLeft: isLeft))
        .overlay {
            if isLeft {
                ClassProgramInset()
                    .padding(.top, 38)
                    .padding(.leading, 34)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .overlay(PaperGrain(density: 420).opacity(0.16))
        .overlay(alignment: isLeft ? .trailing : .leading) {
            LinearGradient(
                colors: [.black.opacity(0.08), .clear],
                startPoint: isLeft ? .trailing : .leading,
                endPoint: isLeft ? .leading : .trailing
            )
            .frame(width: 34)
            .allowsHitTesting(false)
        }
        .overlay {
            shape
            .stroke(.white.opacity(0.72), lineWidth: 0.8)
        }
    }

    private var centerFold: some View {
        ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.black.opacity(0.13), .white.opacity(0.42), .black.opacity(0.1)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 28)
                .blur(radius: 2.4)
            Capsule()
                .fill(.black.opacity(0.13))
                .frame(width: 1.1)
            Capsule()
                .stroke(.white.opacity(0.5), lineWidth: 0.7)
                .frame(width: 8)
        }
        .allowsHitTesting(false)
    }

    private func pageCrown(size: CGSize) -> some View {
        VStack {
            HStack(spacing: 0) {
                UnevenRoundedRectangle(
                    cornerRadii: .init(topLeading: 30, bottomLeading: 6, bottomTrailing: 0, topTrailing: 8),
                    style: .continuous
                )
                .fill(.white.opacity(0.38))
                .frame(width: size.width * 0.5, height: 10)
                .offset(y: -2)
                UnevenRoundedRectangle(
                    cornerRadii: .init(topLeading: 8, bottomLeading: 0, bottomTrailing: 6, topTrailing: 30),
                    style: .continuous
                )
                .fill(.white.opacity(0.34))
                .frame(width: size.width * 0.5, height: 10)
                .offset(y: -2)
            }
            Spacer()
        }
        .allowsHitTesting(false)
    }

    private func bottomPageCurl(size: CGSize) -> some View {
        VStack {
            Spacer()
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(
                    cornerRadii: .init(topLeading: 8, bottomLeading: 30, bottomTrailing: 30, topTrailing: 8),
                    style: .continuous
                )
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.78, green: 0.8, blue: 0.84).opacity(0.26),
                            .white.opacity(0.28),
                            Color(red: 0.55, green: 0.58, blue: 0.64).opacity(0.18)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size.width - 10, height: 18)
                .offset(y: 7)

                HStack(spacing: 5) {
                    ForEach(0..<38, id: \.self) { index in
                        Capsule()
                            .fill(Color(red: 0.54, green: 0.6, blue: 0.68).opacity(index.isMultiple(of: 2) ? 0.22 : 0.12))
                            .frame(width: 1, height: 6 + CGFloat(index % 4))
                    }
                }
                .frame(width: size.width - 44)
                .offset(y: 7)
            }
        }
        .allowsHitTesting(false)
    }

    private func sidePageEdges() -> some View {
        VStack(spacing: 4) {
            ForEach(0..<26, id: \.self) { index in
                Capsule()
                    .fill(Color(red: 0.58, green: 0.62, blue: 0.68).opacity(index.isMultiple(of: 2) ? 0.34 : 0.2))
                    .frame(width: 8 + CGFloat(index % 3), height: 1)
            }
        }
        .frame(width: 16)
        .padding(.vertical, 30)
        .frame(maxHeight: .infinity)
    }
}

struct OpenCompositionRules: View {
    var isLeft: Bool

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let margin = isLeft ? size.width * 0.16 : size.width * 0.14
            let farMargin = size.width * 0.9

            for x in [margin, farMargin] {
                var vertical = Path()
                vertical.move(to: CGPoint(x: x, y: 0))
                vertical.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(vertical, with: .color(NotebookTheme.redRule.opacity(0.32)), lineWidth: 0.75)
            }

            var y: CGFloat = 72
            while y < size.height - 22 {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y + (isLeft ? -0.8 : 0.8)))
                context.stroke(line, with: .color(NotebookTheme.blueLine.opacity(0.48)), lineWidth: 0.65)
                y += 18
            }

            var top = Path()
            top.move(to: CGPoint(x: 0, y: 56))
            top.addLine(to: CGPoint(x: size.width, y: 56))
            context.stroke(top, with: .color(NotebookTheme.blueLine.opacity(0.38)), lineWidth: 0.8)
        }
    }
}

struct EmptyNotebookCapturePortal: View {
    var active: Bool

    var body: some View {
        ZStack {
            capturePaper
                .frame(width: 246, height: 294)
                .rotation3DEffect(.degrees(active ? 4.5 : -3.5), axis: (x: 0.18, y: 1, z: 0), perspective: 0.76)
                .offset(y: active ? -4 : 4)

            EdgeLockCorners()
                .stroke(NotebookTheme.ink.opacity(0.46), style: StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round))
                .frame(width: 218, height: 266)
                .scaleEffect(active ? 1.035 : 0.982)
                .opacity(0.9)

            ScannerGlow()
                .frame(width: 202, height: 20)
                .offset(y: active ? 102 : -108)
                .opacity(active ? 0.68 : 0.38)

            CaptureOrbitGlyphs(active: active)
                .frame(width: 292, height: 316)
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true), value: active)
    }

    private var capturePaper: some View {
        RoundedRectangle(cornerRadius: 32, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        NotebookTheme.paper,
                        Color(red: 0.97, green: 0.965, blue: 0.92)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                OpenCompositionRules(isLeft: false)
                    .opacity(0.78)
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            }
            .overlay(alignment: .topLeading) {
                ClassProgramInset()
                    .scaleEffect(0.72, anchor: .topLeading)
                    .padding(.leading, 26)
                    .padding(.top, 28)
                    .opacity(0.92)
            }
            .overlay {
                CaptureGuideDoodles(active: active)
                    .padding(22)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.82),
                                NotebookTheme.ink.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.1), radius: 12, y: 8)
    }
}

private struct CaptureGuideDoodles: View {
    var active: Bool

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let ink = NotebookTheme.ink.opacity(0.2)
            let blue = NotebookTheme.blueLine.opacity(0.48)
            let lift = active ? CGFloat(-5) : CGFloat(5)

            var curve = Path()
            curve.move(to: CGPoint(x: size.width * 0.18, y: size.height * 0.72 + lift))
            curve.addCurve(
                to: CGPoint(x: size.width * 0.82, y: size.height * 0.56 - lift),
                control1: CGPoint(x: size.width * 0.34, y: size.height * 0.56),
                control2: CGPoint(x: size.width * 0.62, y: size.height * 0.76)
            )
            context.stroke(curve, with: .color(ink), style: StrokeStyle(lineWidth: 1.7, lineCap: .round))

            var underline = Path()
            underline.move(to: CGPoint(x: size.width * 0.34, y: size.height * 0.82))
            underline.addCurve(
                to: CGPoint(x: size.width * 0.72, y: size.height * 0.82 + lift * 0.4),
                control1: CGPoint(x: size.width * 0.44, y: size.height * 0.78),
                control2: CGPoint(x: size.width * 0.58, y: size.height * 0.86)
            )
            context.stroke(underline, with: .color(blue), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))

            for index in 0..<3 {
                let center = CGPoint(
                    x: size.width * (0.76 - CGFloat(index) * 0.12),
                    y: size.height * (0.28 + CGFloat(index) * 0.1)
                )
                var dot = Path()
                dot.addEllipse(in: CGRect(x: center.x, y: center.y + lift * 0.35, width: 4, height: 4))
                context.fill(dot, with: .color(ink.opacity(0.72)))
            }
        }
        .allowsHitTesting(false)
    }
}

private struct CaptureOrbitGlyphs: View {
    var active: Bool

    private let glyphs = [
        ("text.viewfinder", CGPoint(x: 0.18, y: 0.2)),
        ("tablecells", CGPoint(x: 0.88, y: 0.42)),
        ("cube.transparent", CGPoint(x: 0.2, y: 0.82))
    ]

    var body: some View {
        GeometryReader { proxy in
            ForEach(Array(glyphs.enumerated()), id: \.offset) { index, item in
                Image(systemName: item.0)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(active ? .white : NotebookTheme.ink.opacity(0.72))
                    .frame(width: 40, height: 40)
                    .background(active ? NotebookTheme.ink.opacity(0.88) : .white.opacity(0.56), in: Circle())
                    .overlay {
                        Circle().stroke(.white.opacity(0.58), lineWidth: 0.8)
                    }
                    .position(
                        x: proxy.size.width * item.1.x,
                        y: proxy.size.height * item.1.y + (active ? CGFloat(index - 1) * 5 : CGFloat(1 - index) * 5)
                    )
                    .rotationEffect(.degrees(active ? Double(index * 16) : Double(index * -12)))
                    .scaleEffect(active ? 1.02 : 0.94)
            }
        }
        .allowsHitTesting(false)
    }
}

struct ClassProgramInset: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("class program")
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(NotebookTheme.ink.opacity(0.52))
            VStack(spacing: 3) {
                ForEach(0..<7, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(0..<4, id: \.self) { column in
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .stroke(NotebookTheme.ink.opacity(row == 0 || column == 0 ? 0.26 : 0.16), lineWidth: 0.45)
                                .frame(width: column == 0 ? 22 : 28, height: row == 0 ? 10 : 13)
                        }
                    }
                }
            }
            Text("notes")
                .font(.system(size: 7, weight: .medium, design: .rounded))
                .foregroundStyle(NotebookTheme.muted.opacity(0.62))
                .padding(.top, 1)
        }
        .padding(9)
        .background(.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(NotebookTheme.ink.opacity(0.14), lineWidth: 0.6)
        }
        .frame(width: 140, alignment: .leading)
        .allowsHitTesting(false)
    }
}

struct ScanProcessingOverlay: View {
    let phase: ScanPhase
    @State private var entered = false
    @State private var sweep = false
    @State private var fold = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .overlay {
                    DetailScanAtmosphere(phase: phase, active: sweep)
                }

            VStack(spacing: 20) {
                ZStack(alignment: .bottom) {
                    ProcessingNotebookPocket(phase: phase, active: fold)
                        .offset(y: phase == .sorted ? 34 : 58)
                        .opacity(phase == .capturing ? 0.48 : 1)

                    ProcessingPage(phase: phase, sweep: sweep)
                        .frame(width: 178, height: 238)
                        .rotationEffect(.degrees(pageRotation))
                        .scaleEffect(pageScale)
                        .offset(x: pageOffset.width, y: pageOffset.height)
                        .shadow(color: .black.opacity(0.18), radius: 12, y: 8)
                        .animation(.spring(response: 0.7, dampingFraction: 0.78), value: phase)
                        .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: sweep)
                }
                .frame(width: 242, height: 292)

                VStack(spacing: 9) {
                    Text(phase.caption)
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.opacity)
                    Text(phaseDetail)
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .frame(width: 230)
                }

                ScanPhaseRail(current: phase)
                ScanIntelligenceRibbon(phase: phase, active: sweep)
                ScanModelStackRibbon(phase: phase)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 26)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .stroke(.white.opacity(0.55), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.2), radius: 24, y: 16)
            .scaleEffect(entered ? 1 : 0.94)
            .opacity(entered ? 1 : 0)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .animation(.spring(response: 0.58, dampingFraction: 0.84), value: entered)
        .animation(.spring(response: 0.62, dampingFraction: 0.82), value: phase)
        .onAppear {
            entered = true
            sweep = true
            fold = true
        }
    }

    private var pageScale: CGFloat {
        switch phase {
        case .framing: 1
        case .capturing: 1.02
        case .processing: 0.96
        case .organizing: 0.86
        case .sorted: 0.42
        }
    }

    private var pageRotation: Double {
        switch phase {
        case .framing: 0
        case .capturing: -1.4
        case .processing: 1.8
        case .organizing: -7
        case .sorted: -14
        }
    }

    private var pageOffset: CGSize {
        switch phase {
        case .framing: .zero
        case .capturing: CGSize(width: 0, height: -5)
        case .processing: CGSize(width: 0, height: -12)
        case .organizing: CGSize(width: 18, height: 0)
        case .sorted: CGSize(width: 36, height: 66)
        }
    }

    private var phaseDetail: String {
        switch phase {
        case .framing:
            "lining up the page"
        case .capturing:
            "locking the page edges"
        case .processing:
            "surya reads ink while sam 3d and triposr rebuild diagrams"
        case .organizing:
            "gemma files the page by subject"
        case .sorted:
            "sliding it into your notebook"
        }
    }
}

struct ProcessingPage: View {
    let phase: ScanPhase
    let sweep: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(NotebookTheme.paper)
                .overlay {
                    PaperRules()
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .overlay {
                    PaperGrain(density: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule()
                        .fill(NotebookTheme.ink.opacity(index == 0 ? 0.34 : 0.18))
                        .frame(width: CGFloat(64 + (index * 17) % 76), height: index == 0 ? 5 : 4)
                }
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(NotebookTheme.ink.opacity(0.1 + Double(index) * 0.03))
                            .frame(width: 34, height: 28)
                    }
                }
                Spacer()
            }
            .padding(24)
            .opacity(phase == .capturing ? 0.5 : 1)

            ScanExtractionPreview(phase: phase, active: sweep)
                .padding(22)
                .opacity(extractionOpacity)
                .scaleEffect(phase == .sorted ? 0.92 : 1)
                .animation(.spring(response: 0.52, dampingFraction: 0.82), value: phase)

            EdgeLockCorners()
                .stroke(.white.opacity(phase == .capturing ? 0.96 : 0.58), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .padding(10)
                .scaleEffect(phase == .capturing && sweep ? 1.04 : 1)

            if phase == .processing || phase == .capturing {
                ScannerGlow()
                    .offset(y: sweep ? 92 : -92)
                    .opacity(phase == .processing ? 0.9 : 0.72)
            }

            if phase == .organizing || phase == .sorted {
                ProcessingParticles(active: sweep)
                    .padding(18)
                ReconstructedObjectGlyph(active: sweep)
                    .frame(width: 96, height: 96)
                    .transition(.opacity.combined(with: .scale(scale: 0.86)))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.82), .black.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }

    private var extractionOpacity: Double {
        switch phase {
        case .framing:
            return 0
        case .capturing:
            return 0.18
        case .processing:
            return 0.82
        case .organizing, .sorted:
            return 1
        }
    }
}

struct ScanExtractionPreview: View {
    let phase: ScanPhase
    let active: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(NotebookTheme.ink.opacity(isProcessing ? 0.34 : 0.18))
                        .frame(width: active ? CGFloat(34 + index * 13) : CGFloat(24 + index * 9), height: 5)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(NotebookTheme.ink.opacity(0.18 + Double(index) * 0.025))
                        .frame(width: active ? CGFloat(96 - index * 8) : CGFloat(64 + index * 7), height: 4)
                }
            }

            HStack(alignment: .top, spacing: 9) {
                ScanTablePreview(active: active, visible: phaseIndex >= 3)
                    .frame(width: 70, height: 58)
                ScanDiagramPreview(active: active, visible: phaseIndex >= 2)
                    .frame(width: 58, height: 58)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private var isProcessing: Bool {
        phase == .processing || phase == .organizing
    }

    private var phaseIndex: Int {
        ScanPhase.allCases.firstIndex(of: phase) ?? 0
    }
}

private struct ScanTablePreview: View {
    var active: Bool
    var visible: Bool

    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { column in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(NotebookTheme.ink.opacity(row == 0 ? 0.36 : 0.2), lineWidth: 0.8)
                            .background(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(row == 0 ? NotebookTheme.ink.opacity(0.06) : .white.opacity(0.08))
                            )
                            .frame(width: column == 0 ? 17 : 21, height: row == 0 ? 12 : 15)
                    }
                }
            }
        }
        .padding(6)
        .background(.white.opacity(0.32), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.46), lineWidth: 0.7)
        }
        .opacity(visible ? 1 : 0)
        .offset(y: visible ? 0 : 8)
        .scaleEffect(active ? 1.02 : 0.98)
        .animation(.spring(response: 0.46, dampingFraction: 0.8), value: visible)
        .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: active)
    }
}

private struct ScanDiagramPreview: View {
    var active: Bool
    var visible: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.3))
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(NotebookTheme.ink.opacity(0.12 + Double(index) * 0.05), lineWidth: 0.8)
                    .frame(width: CGFloat(24 + index * 12), height: CGFloat(15 + index * 8))
                    .rotationEffect(.degrees(active ? Double(index * 48 + 10) : Double(index * 48 - 10)))
            }
            Image(systemName: "cube.transparent")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(NotebookTheme.ink.opacity(0.74))
        }
        .opacity(visible ? 1 : 0)
        .scaleEffect(visible ? 1 : 0.78)
        .rotation3DEffect(.degrees(active ? 12 : -10), axis: (x: 0.2, y: 1, z: 0), perspective: 0.76)
        .animation(.spring(response: 0.5, dampingFraction: 0.78), value: visible)
        .animation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true), value: active)
    }
}

struct ScanIntelligenceRibbon: View {
    let phase: ScanPhase
    let active: Bool

    private let steps: [(ScanPhase, String, String)] = [
        (.capturing, "viewfinder", "capture"),
        (.processing, "text.viewfinder", "ocr"),
        (.organizing, "tablecells", "tables"),
        (.sorted, "cube.transparent", "models")
    ]

    var body: some View {
        HStack(spacing: 9) {
            ForEach(steps, id: \.2) { step in
                VStack(spacing: 6) {
                    Image(systemName: step.1)
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(isActive(step.0) ? .white.opacity(0.28) : .white.opacity(0.1), in: Circle())
                        .scaleEffect(isCurrent(step.0) && active ? 1.08 : 1)
                    Text(step.2)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white.opacity(isActive(step.0) ? 0.92 : 0.42))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.11), in: Capsule())
        .overlay {
            Capsule().stroke(.white.opacity(0.24), lineWidth: 0.7)
        }
    }

    private func isActive(_ target: ScanPhase) -> Bool {
        guard let currentIndex = ScanPhase.allCases.firstIndex(of: phase),
              let targetIndex = ScanPhase.allCases.firstIndex(of: target) else { return false }
        return targetIndex <= currentIndex
    }

    private func isCurrent(_ target: ScanPhase) -> Bool {
        phase == target
    }
}

struct ScanModelStackRibbon: View {
    let phase: ScanPhase

    private let models: [(ScanPhase, String, String)] = [
        (.processing, "surya", "text.viewfinder"),
        (.processing, "sam 3d", "scope"),
        (.processing, "triposr", "cube.transparent"),
        (.organizing, "gemma", "sparkle.magnifyingglass")
    ]

    var body: some View {
        HStack(spacing: 7) {
            ForEach(models, id: \.1) { model in
                HStack(spacing: 5) {
                    Image(systemName: model.2)
                        .font(.system(size: 10, weight: .bold))
                    Text(model.1)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white.opacity(isActive(model.0) ? 0.9 : 0.4))
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(.white.opacity(isActive(model.0) ? 0.16 : 0.07), in: Capsule())
                .overlay {
                    Capsule().stroke(.white.opacity(isActive(model.0) ? 0.26 : 0.12), lineWidth: 0.7)
                }
            }
        }
    }

    private func isActive(_ target: ScanPhase) -> Bool {
        guard let currentIndex = ScanPhase.allCases.firstIndex(of: phase),
              let targetIndex = ScanPhase.allCases.firstIndex(of: target) else { return false }
        return targetIndex <= currentIndex
    }
}

struct ReconstructedObjectGlyph: View {
    let active: Bool

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            Canvas(rendersAsynchronously: true) { context, size in
                let points = [
                    CGPoint(x: size.width * 0.5, y: size.height * 0.16),
                    CGPoint(x: size.width * 0.78, y: size.height * 0.36),
                    CGPoint(x: size.width * 0.68, y: size.height * 0.74),
                    CGPoint(x: size.width * 0.32, y: size.height * 0.74),
                    CGPoint(x: size.width * 0.22, y: size.height * 0.36)
                ]

                var shell = Path()
                shell.move(to: points[0])
                for point in points.dropFirst() {
                    shell.addLine(to: point)
                }
                shell.closeSubpath()
                context.stroke(shell, with: .color(.white.opacity(0.72)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))

                for point in points {
                    var line = Path()
                    line.move(to: center)
                    line.addLine(to: point)
                    context.stroke(line, with: .color(.white.opacity(0.24)), lineWidth: 1)
                }
            }
            .rotation3DEffect(.degrees(active ? 18 : -18), axis: (x: 0.2, y: 1, z: 0), perspective: 0.8)
            .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: active)
        }
        .padding(12)
        .background(.white.opacity(0.12), in: Circle())
        .overlay {
            Circle().stroke(.white.opacity(0.28), lineWidth: 0.8)
        }
        .allowsHitTesting(false)
    }
}

struct ScannerGlow: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [.clear, .white.opacity(0.86), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 18)
            .blur(radius: 0.4)
            .blendMode(.screen)
    }
}

struct EdgeLockCorners: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let length: CGFloat = 28

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))

        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))

        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))

        return path
    }
}

struct ProcessingParticles: View {
    let active: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(0..<11, id: \.self) { index in
                    Circle()
                        .fill(.white.opacity(index.isMultiple(of: 2) ? 0.74 : 0.42))
                        .frame(width: CGFloat(4 + index % 4), height: CGFloat(4 + index % 4))
                        .position(
                            x: proxy.size.width * CGFloat((index * 23) % 91) / 100,
                            y: proxy.size.height * CGFloat((index * 41) % 87) / 100
                        )
                        .offset(y: active ? CGFloat(-10 + index % 5) : CGFloat(8 - index % 4))
                        .blur(radius: index.isMultiple(of: 3) ? 0.6 : 0)
                }
            }
        }
    }
}

struct ProcessingNotebookPocket: View {
    let phase: ScanPhase
    let active: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.11))
                .frame(width: 168, height: 112)
                .overlay {
                    SpeckledCompositionTexture()
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .opacity(0.5)
                }
                .overlay(alignment: .leading) {
                    UnevenRoundedRectangle(cornerRadii: .init(topLeading: 22, bottomLeading: 22), style: .continuous)
                        .fill(.black.opacity(0.82))
                        .frame(width: 24)
                }
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(.white.opacity(phase == .sorted ? 0.48 : 0.2))
                        .frame(width: active ? 116 : 86, height: 2)
                        .offset(y: 12)
                }
                .rotation3DEffect(.degrees(phase == .sorted ? -8 : -2), axis: (x: 1, y: 0, z: 0), perspective: 0.8)
                .scaleEffect(phase == .sorted ? 1.08 : 1)
        }
        .animation(.spring(response: 0.62, dampingFraction: 0.78), value: phase)
        .allowsHitTesting(false)
    }
}

struct ScanPhaseRail: View {
    let current: ScanPhase
    private let phases: [ScanPhase] = [.capturing, .processing, .organizing, .sorted]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(phases) { phase in
                Capsule()
                    .fill(isActive(phase) ? .white.opacity(0.86) : .white.opacity(0.22))
                    .frame(width: current == phase ? 34 : 8, height: 8)
                    .animation(.spring(response: 0.4, dampingFraction: 0.78), value: current)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.12), in: Capsule())
    }

    private func isActive(_ phase: ScanPhase) -> Bool {
        guard let currentIndex = phases.firstIndex(of: current),
              let phaseIndex = phases.firstIndex(of: phase) else {
            return false
        }
        return phaseIndex <= currentIndex
    }
}

struct DetailScanAtmosphere: View {
    let phase: ScanPhase
    let active: Bool

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.42)
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - 170, y: center.y - 170, width: 340, height: 340)),
                with: .radialGradient(
                    Gradient(colors: [phaseColor.opacity(0.26), .clear]),
                    center: center,
                    startRadius: 0,
                    endRadius: active ? 210 : 150
                )
            )
        }
        .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: active)
    }

    private var phaseColor: Color {
        switch phase {
        case .framing: .white
        case .capturing: Color(red: 0.92, green: 0.82, blue: 0.56)
        case .processing: Color(red: 0.62, green: 0.72, blue: 0.88)
        case .organizing: Color(red: 0.72, green: 0.64, blue: 0.84)
        case .sorted: Color(red: 0.62, green: 0.78, blue: 0.62)
        }
    }
}

struct DetectedTableView: View {
    let table: DetectedTable

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(table.title)
                .font(.system(.subheadline, design: .serif, weight: .semibold))
                .foregroundStyle(NotebookTheme.ink.opacity(0.62))

            VStack(spacing: 0) {
                tableRow(table.headers, isHeader: true)
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    tableRow(row, isHeader: false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(NotebookTheme.ink.opacity(0.12), lineWidth: 0.8)
            )
        }
    }

    private func tableRow(_ cells: [String], isHeader: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                Text(cell)
                    .font(.system(.caption, design: .rounded, weight: isHeader ? .semibold : .regular))
                    .foregroundStyle(NotebookTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 8)
                    .background(isHeader ? NotebookTheme.ink.opacity(0.055) : .white.opacity(0.12))
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NotebookTheme.ink.opacity(0.08))
                .frame(height: 1)
        }
    }
}

struct DetectedModelView: View {
    let model: DetectedModel
    @State private var selectedNode: String?
    @State private var awake = false
    @State private var renderMode: ModelRenderMode = .orbit
    @State private var modelTilt: CGSize = .zero

    private var nodes: [String] {
        let modelNodes = model.nodes ?? []
        return modelNodes.isEmpty ? model.terms : modelNodes
    }

    private var reconstruction: ModelReconstruction {
        model.reconstruction ?? ModelReconstructionFactory.make(
            source: "local depth",
            confidence: 0.62,
            shape: .orbit,
            nodes: nodes,
            hint: "tap a node to inspect the connection."
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.white.opacity(0.92), .white.opacity(0.46)],
                                center: .topLeading,
                                startRadius: 0,
                                endRadius: 42
                            )
                        )
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(NotebookTheme.ink)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.title)
                        .font(.system(.subheadline, design: .serif, weight: .semibold))
                    Text(model.summary)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(NotebookTheme.ink.opacity(0.72))
                }
            }

            if !nodes.isEmpty {
                ReconstructionBadgeStrip(reconstruction: reconstruction)

                HStack(spacing: 8) {
                    ForEach(ModelRenderMode.allCases) { mode in
                        Button {
                            Haptics.selection()
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
                                renderMode = mode
                            }
                        } label: {
                            Image(systemName: mode.symbol)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(renderMode == mode ? .white : NotebookTheme.ink)
                                .frame(width: 34, height: 34)
                                .background(renderMode == mode ? NotebookTheme.ink : .white.opacity(0.48), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Text("\(nodes.count)")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(NotebookTheme.ink.opacity(0.68))
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.48), in: Circle())
                }

                InteractiveModelMap(nodes: nodes, reconstruction: reconstruction, selectedNode: $selectedNode, awake: awake, mode: renderMode)
                    .frame(height: renderMode == .mesh ? 212 : 188)
                    .rotation3DEffect(.degrees(awake ? Double(modelTilt.height / -18) : 16), axis: (x: 1, y: 0, z: 0), perspective: 0.8)
                    .rotation3DEffect(.degrees(Double(modelTilt.width / 18)), axis: (x: 0, y: 1, z: 0), perspective: 0.8)
                    .scaleEffect(modelTilt == .zero ? 1 : 1.018)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if modelTilt == .zero {
                                    Haptics.softTap()
                                }
                                modelTilt = CGSize(
                                    width: max(min(value.translation.width, 80), -80),
                                    height: max(min(value.translation.height, 80), -80)
                                )
                            }
                            .onEnded { _ in
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.76)) {
                                    modelTilt = .zero
                                }
                            }
                    )

                Text(selectedNode.map { "\($0) links to \(relatedNode(after: $0))." } ?? reconstruction.interactionHint)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(NotebookTheme.ink.opacity(0.72))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.white.opacity(0.42), in: Capsule())
                    .animation(.spring(response: 0.35, dampingFraction: 0.84), value: selectedNode)
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [.white.opacity(0.46), .white.opacity(0.22), NotebookTheme.ink.opacity(0.045)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.62), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 10, y: 6)
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.86).delay(0.08)) {
                awake = true
            }
        }
    }

    private func relatedNode(after node: String) -> String {
        guard let index = nodes.firstIndex(of: node), !nodes.isEmpty else { return "the page" }
        return nodes[(index + 1) % nodes.count]
    }
}

struct InteractiveModelMap: View {
    let nodes: [String]
    let reconstruction: ModelReconstruction
    @Binding var selectedNode: String?
    var awake: Bool
    var mode: ModelRenderMode
    @State private var orbit = false

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = min(proxy.size.width, proxy.size.height) * mode.radiusFactor
            let anchors = displayAnchors

            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.white.opacity(0.18))
                    .overlay {
                        ModelGridLines()
                            .opacity(awake ? 1 : 0)
                    }
                    .overlay {
                        ModelContourRings(shape: reconstruction.shape, active: orbit)
                            .opacity(awake ? 1 : 0)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(.white.opacity(0.44), lineWidth: 0.8)
                    }

                ForEach(0..<mode.orbitCount, id: \.self) { index in
                    Ellipse()
                        .stroke(NotebookTheme.ink.opacity(0.08 + Double(index) * 0.026), lineWidth: mode == .mesh ? 1.2 : 1)
                        .frame(
                            width: radius * CGFloat(mode == .mesh ? 2.5 + Double(index) * 0.28 : 2.1 + Double(index) * 0.32),
                            height: radius * CGFloat(mode == .stack ? 0.56 + Double(index) * 0.18 : 0.82 + Double(index) * 0.14)
                        )
                        .rotationEffect(.degrees(Double(index) * 58 + (orbit ? 12 : -12)))
                        .position(center)
                }

                ForEach(Array(anchors.enumerated()), id: \.element.id) { index, anchor in
                    let node = anchor.label
                    let point = point(for: anchor, in: proxy.size, center: center, radius: radius, index: index, count: anchors.count)
                    Path { path in
                        path.move(to: center)
                        path.addQuadCurve(
                            to: point,
                            control: CGPoint(x: (center.x + point.x) / 2, y: (center.y + point.y) / 2 - 10)
                        )
                    }
                    .stroke(NotebookTheme.ink.opacity(selectedNode == node ? 0.34 : 0.12), lineWidth: selectedNode == node ? 2 : 1)
                    .scaleEffect(1 + CGFloat(anchor.z) * 0.08, anchor: .center)
                    .opacity(awake ? 1 : 0)
                }

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white.opacity(0.92), .white.opacity(0.42)],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 44
                        )
                    )
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: reconstruction.shape.symbol)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(NotebookTheme.ink)
                    }
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                    .rotation3DEffect(.degrees(awake ? 8 : -10), axis: (x: 0.15, y: 1, z: 0), perspective: 0.8)
                    .scaleEffect(awake ? 1 : 0.82)
                    .overlay {
                        if mode == .mesh {
                            Image(systemName: "point.3.connected.trianglepath.dotted")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(NotebookTheme.ink.opacity(0.62))
                                .offset(x: 24, y: -20)
                        }
                    }
                    .position(center)

                ForEach(Array(anchors.enumerated()), id: \.element.id) { index, anchor in
                    let node = anchor.label
                    let point = point(for: anchor, in: proxy.size, center: center, radius: radius, index: index, count: anchors.count)
                    Button {
                        Haptics.selection()
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
                            selectedNode = node
                        }
                    } label: {
                        Text(node)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                            .foregroundStyle(NotebookTheme.ink)
                            .frame(width: selectedNode == node ? 86 : 68, height: selectedNode == node ? 44 : 36)
                            .background(.white.opacity(selectedNode == node ? 0.82 : 0.54), in: Capsule())
                            .overlay {
                                Capsule().stroke(.white.opacity(0.68), lineWidth: 0.8)
                            }
                            .rotation3DEffect(.degrees(selectedNode == node ? -10 : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.7)
                            .shadow(color: .black.opacity(selectedNode == node ? 0.12 : 0.06), radius: selectedNode == node ? 9 : 4, y: selectedNode == node ? 7 : 3)
                    }
                    .buttonStyle(.plain)
                    .position(awake ? point : center)
                    .scaleEffect(selectedNode == node ? 1.08 : 0.96 + CGFloat(anchor.z) * 0.12)
                    .offset(y: CGFloat(anchor.z) * -10)
                    .opacity(awake ? 1 : 0)
                    .zIndex(selectedNode == node ? 20 : 10 + anchor.z)
                }
            }
            .animation(.spring(response: 0.62, dampingFraction: 0.78), value: awake)
            .animation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true), value: orbit)
            .onAppear {
                orbit = true
            }
        }
    }

    private var displayAnchors: [ModelAnchor] {
        let anchors = reconstruction.anchors.isEmpty
            ? ModelReconstructionFactory.make(source: "local depth", confidence: reconstruction.confidence, shape: reconstruction.shape, nodes: nodes, hint: reconstruction.interactionHint).anchors
            : reconstruction.anchors
        return Array(anchors.prefix(8))
    }

    private func point(for anchor: ModelAnchor, in size: CGSize, center: CGPoint, radius: CGFloat, index: Int, count: Int) -> CGPoint {
        if mode == .orbit {
            let angle = (Double(index) / Double(max(1, count))) * .pi * 2 - .pi / 2 + (orbit ? 0.08 : -0.08)
            return CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius * mode.verticalSquash
            )
        }

        let shimmer = orbit ? 0.016 : -0.016
        let direction = index.isMultiple(of: 2) ? 1.0 : -1.0
        let x = min(0.88, max(0.12, anchor.x + shimmer * direction))
        let y = min(0.86, max(0.14, anchor.y))
        return CGPoint(x: size.width * x, y: size.height * y)
    }
}

struct ReconstructionBadgeStrip: View {
    let reconstruction: ModelReconstruction

    var body: some View {
        HStack(spacing: 8) {
            badge(systemName: reconstruction.shape.symbol, text: reconstruction.shape.rawValue)
            badge(systemName: "waveform.path.ecg", text: "\(Int((reconstruction.confidence * 100).rounded()))%")
            badge(systemName: "sparkle.magnifyingglass", text: reconstruction.source)
        }
    }

    private func badge(systemName: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .bold))
            Text(text)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(NotebookTheme.ink.opacity(0.74))
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.white.opacity(0.42), in: Capsule())
    }
}

enum ModelRenderMode: String, CaseIterable, Identifiable {
    case orbit
    case mesh
    case stack

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .orbit: "circle.dotted.circle"
        case .mesh: "point.3.connected.trianglepath.dotted"
        case .stack: "square.stack.3d.up.fill"
        }
    }

    var hint: String {
        switch self {
        case .orbit: "tap a node to inspect the connection."
        case .mesh: "mesh mode shows structure and linked terms."
        case .stack: "stack mode turns the model into a recall order."
        }
    }

    var radiusFactor: CGFloat {
        switch self {
        case .orbit: 0.34
        case .mesh: 0.38
        case .stack: 0.31
        }
    }

    var verticalSquash: CGFloat {
        switch self {
        case .orbit: 0.54
        case .mesh: 0.7
        case .stack: 0.42
        }
    }

    var orbitCount: Int {
        switch self {
        case .orbit: 3
        case .mesh: 5
        case .stack: 4
        }
    }
}

struct ModelContourRings: View {
    var shape: ModelShape
    var active: Bool

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
            let smallest = min(size.width, size.height)
            for index in 0..<5 {
                let phase = CGFloat(index) / 5
                let drift = active ? CGFloat(sin(Double(index) * 0.7)) * 2.8 : 0
                let rect = CGRect(
                    x: center.x - smallest * (0.14 + phase * 0.075),
                    y: center.y - smallest * (0.08 + phase * 0.046) + drift,
                    width: smallest * (0.28 + phase * 0.15),
                    height: smallest * (0.16 + phase * 0.092)
                )
                var path = Path(ellipseIn: rect)
                if shape == .stack {
                    path = Path(roundedRect: rect, cornerRadius: 18)
                }
                context.stroke(
                    path,
                    with: .color(NotebookTheme.ink.opacity(0.045 + Double(index) * 0.012)),
                    style: StrokeStyle(lineWidth: index == 0 ? 1.4 : 0.9, lineCap: .round)
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct ModelGridLines: View {
    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let color = NotebookTheme.ink.opacity(0.07)
            for index in 1..<5 {
                let x = size.width * CGFloat(index) / 5
                var vertical = Path()
                vertical.move(to: CGPoint(x: x, y: 0))
                vertical.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(vertical, with: .color(color), lineWidth: 0.6)
            }
            for index in 1..<4 {
                let y = size.height * CGFloat(index) / 4
                var horizontal = Path()
                horizontal.move(to: CGPoint(x: 0, y: y))
                horizontal.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(horizontal, with: .color(color), lineWidth: 0.6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
