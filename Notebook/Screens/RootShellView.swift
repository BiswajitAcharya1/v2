import SwiftUI

struct RootShellView: View {
    @Environment(NotebookStore.self) private var store

    var body: some View {
        Group {
            if store.isAuthenticated {
                if store.hasCompletedOnboarding {
                    appTabs
                } else {
                    SetupFlowView()
                }
            } else {
                AuthView()
            }
        }
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.985)),
            removal: .opacity.combined(with: .scale(scale: 1.015))
        ))
        .animation(.spring(response: 0.72, dampingFraction: 0.84), value: store.isAuthenticated)
        .animation(.spring(response: 0.72, dampingFraction: 0.84), value: store.hasCompletedOnboarding)
        .comfortDisplay(store.comfortSettings)
        .preferredColorScheme(.light)
    }

    private var appTabs: some View {
        NavigationStack {
            HomeView()
        }
        .tint(NotebookTheme.ink)
    }
}

private struct SetupFlowView: View {
    @Environment(NotebookStore.self) private var store
    @State private var subjectDraft = ""
    @State private var subjects: [String] = []
    @State private var canvasDomain = ""
    @State private var canvasToken = ""
    @State private var canvasExpanded = false
    @State private var recordTaskActive = false
    @State private var retakeRotation = 0.0
    @State private var subjectCheckRotation = 0.0
    @State private var themeCheckRotation = 0.0
    private let prompts = [
        "today i will study with calm focus.",
        "explain this page like a patient tutor.",
        "help me remember only what matters."
    ]
    var body: some View {
        ZStack {
            LivingPaperBackground().ignoresSafeArea()
            ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                NotebookLogo()
                    .frame(width: store.setupStep == .subjects ? 112 : 104, height: store.setupStep == .subjects ? 146 : 136)
                    .rotationEffect(.degrees(store.setupStep == .theme ? -4 : 3))
                    .animation(.spring(response: 0.55, dampingFraction: 0.75), value: store.setupStep)

                Group {
                    switch store.setupStep {
                    case .voiceRecording:
                        subjectChoice
                    case .theme:
                        themeChoice
                    case .subjects:
                        subjectChoice
                    case .avatar:
                        avatarChoice
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.98)),
                    removal: .move(edge: .leading).combined(with: .opacity).combined(with: .scale(scale: 1.02))
                ))
                .animation(.spring(response: 0.62, dampingFraction: 0.84), value: store.setupStep)
            }
            .padding(20)
            .padding(.top, 82)
            .padding(.bottom, 34)
            }

        }
    }

    private var voiceRecording: some View {
        GlassSurface(radius: 30, padding: 18, interactive: true) {
            VStack(spacing: 14) {
                Text("audio")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)
                Text(voiceInstructionText)
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(NotebookTheme.muted)
                    .multilineTextAlignment(.center)

                Text(currentVoicePrompt)
                    .font(.system(.callout, design: .serif, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                if let message = store.voiceSetupMessage {
                    Text(message)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(NotebookTheme.muted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.52), in: Capsule())
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                HStack(spacing: 12) {
                    Button {
                        Haptics.softTap()
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.72)) {
                            retakeRotation -= 90
                        }
                        store.retakeVoicePrompt()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 36, height: 36)
                            .rotationEffect(.degrees(retakeRotation))
                    }
                    .buttonStyle(CircleButtonStyle(tint: NotebookTheme.muted.opacity(0.6), foreground: NotebookTheme.ink))
                    .disabled(store.voiceProfile.samples.isEmpty || store.isRecordingVoice || store.isPreparingVoiceRecording)
                    .opacity(store.voiceProfile.samples.isEmpty || store.isRecordingVoice || store.isPreparingVoiceRecording ? 0.38 : 1)

                    Button {
                        recordCurrentPrompt()
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(.white.opacity(0.24), lineWidth: 5)
                                .scaleEffect(store.isRecordingVoice ? 1.1 + store.voiceRecordingLevel * 0.08 : 1)
                                .opacity(store.isRecordingVoice ? 1 : 0)
                            Image(systemName: voiceRecordSymbol)
                                .font(.system(size: 14, weight: .bold))
                                .frame(width: 36, height: 36)
                        }
                    }
                    .buttonStyle(CircleButtonStyle(tint: NotebookTheme.ink, foreground: .white))
                    .disabled(store.isPreparingVoiceRecording || recordTaskActive)
                    .scaleEffect(store.isPreparingVoiceRecording || recordTaskActive ? 0.96 : 1)
                    .accessibilityLabel(store.isRecordingVoice ? "finish recording" : "start recording")

                    Button {
                        Haptics.softTap()
                        store.skipVoiceSetup()
                    } label: {
                        Text("skip")
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .foregroundStyle(NotebookTheme.ink)
                            .padding(.horizontal, 15)
                            .frame(height: 36)
                            .background(.white.opacity(0.58), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Capsule())
                }
            }
        }
    }

    private func recordCurrentPrompt() {
        guard !recordTaskActive, !store.isPreparingVoiceRecording else { return }
        Haptics.open()
        Task {
            await MainActor.run {
                recordTaskActive = true
            }
            if store.isRecordingVoice {
                store.finishCurrentVoicePrompt()
            } else {
                await store.recordVoicePrompt(currentVoicePrompt)
            }
            await MainActor.run {
                recordTaskActive = false
            }
        }
    }

    private var currentVoicePrompt: String {
        prompts[min(store.voiceProfile.samples.count, prompts.count - 1)]
    }

    private var voiceInstructionText: String {
        if store.isPreparingVoiceRecording {
            return "opening microphone."
        }
        if store.isRecordingVoice && !store.voiceRecognitionAvailable {
            return "read naturally, then tap again to save."
        }
        return "read each sentence once. words darken only when they are matched."
    }

    private var voiceRecordSymbol: String {
        if store.isPreparingVoiceRecording || recordTaskActive { return "ellipsis" }
        return store.isRecordingVoice ? "stop.fill" : "mic.fill"
    }

    private var subjectChoice: some View {
        GlassSurface(radius: 34, padding: 20, interactive: true) {
            VStack(spacing: 16) {
                Text("subjects")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)

                HStack(alignment: .bottom, spacing: 10) {
                    GooeyInput(
                        label: "subject",
                        systemName: "magnifyingglass",
                        text: $subjectDraft,
                        onSubmit: addSubject
                    )

                    Button(action: addSubject) {
                    Image(systemName: "plus")
                            .font(.system(size: 15, weight: .bold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(FloatingCircleButtonStyle())
                    .disabled(bestSubjectMatch == nil)
                    .opacity(bestSubjectMatch == nil ? 0.42 : 1)
                }

                SubjectSuggestionRibbon(subjects: subjectSuggestions, selected: subjects, draft: subjectDraft, add: addSubject)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.86, dampingFraction: 0.88), value: subjectSuggestions)

                SelectedSubjectShelf(subjects: subjects) { subject in
                    subjects.removeAll { $0 == subject }
                }
                .animation(.spring(response: 0.48, dampingFraction: 0.82), value: subjects)

                canvasImportCard

                Button {
                    Haptics.success()
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
                        subjectCheckRotation += 90
                    }
                    store.setSubjects(subjects)
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 46, height: 46)
                        .rotationEffect(.degrees(subjectCheckRotation))
                }
                .buttonStyle(CircleButtonStyle())
                .disabled(subjects.isEmpty)
            }
        }
    }

    private var canvasImportCard: some View {
        VStack(spacing: 12) {
            Button {
                Haptics.open()
                withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                    canvasExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "studentdesk")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.58), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("connect canvas")
                            .font(.system(.subheadline, design: .serif, weight: .semibold))
                        Text("make notebooks from real courses")
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(NotebookTheme.muted)
                    }
                    Spacer()
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .rotationEffect(.degrees(canvasExpanded ? 45 : 0))
                }
                .foregroundStyle(NotebookTheme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.white.opacity(0.5), in: Capsule())
            }
            .buttonStyle(.plain)

            if canvasExpanded {
                VStack(spacing: 10) {
                    GooeyInput(label: "canvas domain", systemName: "link", text: $canvasDomain, keyboardType: .URL)
                    GooeyInput(label: "access token", systemName: "key.fill", text: $canvasToken, isSecure: true)
                    Button {
                        importCanvasCourses()
                    } label: {
                        HStack(spacing: 9) {
                            if store.isImportingCanvas {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "arrow.down.doc.fill")
                            }
                            Text(store.isImportingCanvas ? "connecting" : "import courses")
                        }
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(NotebookTheme.ink, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isImportingCanvas)
                    if let message = store.canvasImportMessage {
                        Text(message)
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(NotebookTheme.muted)
                            .multilineTextAlignment(.center)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(13)
                .background(.white.opacity(0.34), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .transition(.scale(scale: 0.94, anchor: .top).combined(with: .opacity))
            }
        }
    }

    private var themeChoice: some View {
        GlassSurface(radius: 34, padding: 20, interactive: true) {
            VStack(spacing: 17) {
                Text("display")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)
                Text("choose the surface your notebooks live on.")
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(NotebookTheme.muted)
                    .multilineTextAlignment(.center)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                    ForEach(ComfortPreset.allCases) { preset in
                        ComfortChoiceCard(
                            preset: preset,
                            active: store.comfortSettings.enabledFeatures == preset.features
                        ) {
                            Haptics.selection()
                            store.applyComfortPreset(preset)
                        }
                    }
                }

                Button {
                    Haptics.success()
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
                        themeCheckRotation += 90
                    }
                    store.continueToAvatar()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 46, height: 46)
                        .rotationEffect(.degrees(themeCheckRotation))
                }
                .buttonStyle(CircleButtonStyle())
            }
        }
    }

    private func importCanvasCourses() {
        Haptics.open()
        Task {
            await store.importCanvasCourses(domain: canvasDomain, token: canvasToken)
        }
    }

    private func addSubject() {
        guard let subject = bestSubjectMatch else { return }
        addSubject(subject)
    }

    private func addSubject(_ subject: String) {
        guard !subject.isEmpty, !subjects.contains(subject) else { return }
        Haptics.selection()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
            subjects.append(subject)
            subjectDraft = ""
        }
    }

    private var subjectSuggestions: [String] {
        SubjectCatalog.suggestions(for: subjectDraft, excluding: Set(subjects), limit: subjectDraft.isEmpty ? 6 : 4)
    }

    private var bestSubjectMatch: String? {
        SubjectCatalog.bestMatch(for: subjectDraft, excluding: Set(subjects))
    }

    private var avatarChoice: some View {
        SetupAvatarChoice {
            store.finishOnboarding()
        }
    }

}

private struct SetupAvatarChoice: View {
    @Environment(NotebookStore.self) private var store
    @State private var draft = AvatarProfile.default
    @State private var float = false
    @State private var checkRotation = 0.0

    private let symbols = ["book.closed.fill", "sparkles", "brain.head.profile", "graduationcap.fill", "function", "atom"]

    var body: some View {
        GlassSurface(radius: 34, padding: 20, interactive: true) {
            VStack(spacing: 18) {
                Text("avatar")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)

                ProfileAvatarView(avatar: draft, size: 128, animated: false)
                    .rotation3DEffect(.degrees(float ? 5 : -5), axis: (x: 0.18, y: 1, z: 0), perspective: 0.8)
                    .scaleEffect(float ? 1.03 : 0.98)

                HStack(spacing: 10) {
                    ForEach(ColorToken.allCases.prefix(6), id: \.self) { token in
                        Button {
                            Haptics.selection()
                            withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
                                draft.base = token
                                let index = ColorToken.allCases.firstIndex(of: token) ?? 0
                                draft.accent = ColorToken.allCases[(index + 2) % ColorToken.allCases.count]
                            }
                        } label: {
                            Circle()
                                .fill(NotebookTheme.accent(token))
                                .frame(width: draft.base == token ? 42 : 34, height: draft.base == token ? 42 : 34)
                                .overlay { Circle().stroke(.white.opacity(0.76), lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                    }
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(symbols, id: \.self) { symbol in
                        Button {
                            Haptics.selection()
                            withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
                                draft.symbol = symbol
                            }
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(draft.symbol == symbol ? .white : NotebookTheme.ink)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(draft.symbol == symbol ? NotebookTheme.ink : .white.opacity(0.56), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    Haptics.success()
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
                        checkRotation += 90
                    }
                    store.updateAvatar(draft)
                    done()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 46, height: 46)
                        .rotationEffect(.degrees(checkRotation))
                }
                .buttonStyle(CircleButtonStyle())
            }
        }
        .onAppear {
            draft = store.user.avatar
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                float = true
            }
        }
    }

    var done: () -> Void
}

private struct ComfortChoiceCard: View {
    var preset: ComfortPreset
    var active: Bool
    var action: () -> Void
    @State private var glow = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: preset.symbol)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(active ? .white : NotebookTheme.ink)
                        .frame(width: 36, height: 36)
                        .background(active ? NotebookTheme.ink : .white.opacity(0.62), in: Circle())
                    Spacer()
                    if active {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(NotebookTheme.ink, in: Circle())
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                Text(preset.title)
                    .font(.system(.headline, design: .serif, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)
                Text(detail)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(NotebookTheme.muted)
                    .lineLimit(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(active ? .white.opacity(0.74) : .white.opacity(0.46))
                    .overlay(alignment: glow ? .bottomTrailing : .topLeading) {
                        Circle()
                            .fill(NotebookTheme.accent(.blue).opacity(active ? 0.2 : 0.1))
                            .frame(width: 74, height: 74)
                            .blur(radius: 16)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(active ? NotebookTheme.ink.opacity(0.28) : .white.opacity(0.52), lineWidth: active ? 1.2 : 0.8)
            }
            .scaleEffect(active ? 1.02 : 1)
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                glow = true
            }
        }
    }

    private var detail: String {
        switch preset {
        case .paper:
            "soft e ink paper for long reading"
        case .focus:
            "calm margins and study contrast"
        case .evening:
            "warm low glare night review"
        case .performance:
            "lighter motion for older phones"
        }
    }
}

private struct VoiceProgress: View {
    var count: Int
    var total: Int
    var recording: Bool
    var preparing: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(NotebookTheme.muted.opacity(0.16), lineWidth: 10)
            Circle()
                .trim(from: 0, to: CGFloat(count) / CGFloat(total))
                .stroke(NotebookTheme.ink, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: preparing ? "ellipsis" : recording ? "waveform" : "mic")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(NotebookTheme.ink)
        }
        .frame(width: 86, height: 86)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: count)
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: preparing)
    }
}

private struct VoiceRecognitionStatus: View {
    var sentenceIndex: Int
    var totalSentences: Int
    var heardWords: Int
    var totalWords: Int
    var isRecording: Bool
    var isPreparing: Bool
    var voiceActive: Bool
    var recognitionAvailable: Bool
    var level: Double

    var body: some View {
        HStack(spacing: 10) {
            Text("sentence \(sentenceIndex) of \(totalSentences)")
                .font(.system(.caption, design: .rounded, weight: .semibold))
            Capsule()
                .fill(NotebookTheme.muted.opacity(0.16))
                .frame(width: 1, height: 18)
            HStack(spacing: 5) {
                Circle()
                    .fill(isRecording && voiceActive ? NotebookTheme.accent(.green) : NotebookTheme.muted.opacity(0.35))
                    .frame(width: 7, height: 7)
                    .scaleEffect(isRecording && voiceActive ? 1.35 : 1)
                Text(statusText)
                    .font(.system(.caption, design: .rounded, weight: .medium))
            }
        }
        .foregroundStyle(NotebookTheme.muted)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white.opacity(0.52), in: Capsule())
        .animation(.spring(response: 0.28, dampingFraction: 0.74), value: heardWords)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: voiceActive)
    }

    private var statusText: String {
        if isPreparing { return "opening microphone" }
        guard isRecording else { return "\(min(heardWords, totalWords)) of \(totalWords) words" }
        if voiceActive && recognitionAvailable {
            return "\(min(heardWords, totalWords)) of \(totalWords) heard"
        }
        if voiceActive {
            return "audio captured"
        }
        return recognitionAvailable ? "listening for words" : "listening"
    }
}

private struct VoicePromptText: View {
    var prompt: String
    var progress: Int
    var recording: Bool
    var voiceActive: Bool

    var body: some View {
        VoicePromptWordsView(
            prompt: prompt,
            progress: progress,
            recording: recording,
            voiceActive: voiceActive
        )
    }
}

private struct VoiceRecordingReadout: View {
    var elapsed: TimeInterval
    var level: Double
    var paused: Bool
    var samples: [VoiceSample]

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text(durationText(elapsed))
                    .font(.system(.title3, design: .monospaced, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)
                    .contentTransition(.numericText())
                if paused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(NotebookTheme.muted)
                }
            }

            HStack(alignment: .center, spacing: 4) {
                ForEach(0..<18, id: \.self) { index in
                    Capsule()
                        .fill(NotebookTheme.ink.opacity(barOpacity(index)))
                        .frame(width: 5, height: barHeight(index))
                }
            }
            .frame(height: 34)
            .animation(.spring(response: 0.22, dampingFraction: 0.68), value: level)

            if !samples.isEmpty {
                HStack(spacing: 6) {
                    ForEach(samples) { sample in
                        VStack(spacing: 4) {
                            Text(durationText(sample.duration))
                                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                            if let transcript = sample.transcript {
                                Text(transcript)
                                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                        .foregroundStyle(NotebookTheme.muted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.58), in: Capsule())
                    }
                }
            }
        }
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let wave = 0.5 + 0.5 * sin(Double(index) * 0.88 + level * 9)
        return 7 + CGFloat(max(0.06, level) * wave) * 28
    }

    private func barOpacity(_ index: Int) -> Double {
        paused ? 0.2 : 0.24 + min(0.7, level + Double(index % 3) * 0.04)
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

private struct SubjectToken: View {
    var subject: String
    var remove: () -> Void
    @State private var rotation = 0.0

    var body: some View {
        Button {
            Haptics.softTap()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                rotation += 90
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    remove()
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(subject)
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .rotationEffect(.degrees(rotation))
            }
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(NotebookTheme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("remove \(subject)")
    }
}

private struct SubjectSuggestionRibbon: View {
    var subjects: [String]
    var selected: [String]
    var draft: String
    var add: (String) -> Void

    var body: some View {
        if !subjects.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 11) {
                    ForEach(Array(subjects.enumerated()), id: \.element) { index, subject in
                        SubjectSuggestionNotebook(subject: subject, active: isBest(subject), delay: Double(index) * 0.045) {
                            add(subject)
                        }
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 1)
            }
            .frame(height: 116)
        }
    }

    private func isBest(_ subject: String) -> Bool {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return SubjectCatalog.bestMatch(for: draft, excluding: Set(selected)) == subject
    }
}

private struct SubjectSuggestionNotebook: View {
    var subject: String
    var active: Bool
    var delay: Double
    var add: () -> Void
    @State private var entered = false
    @State private var shimmer = false

    var body: some View {
        Button {
            Haptics.selection()
            add()
        } label: {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(NotebookTheme.ink)
                    .overlay {
                        SpeckledCompositionTexture()
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .opacity(0.72)
                    }
                    .overlay(alignment: .leading) {
                        UnevenRoundedRectangle(
                            cornerRadii: .init(topLeading: 18, bottomLeading: 18),
                            style: .continuous
                        )
                        .fill(.black.opacity(0.86))
                        .frame(width: 8)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(active ? .white.opacity(0.76) : .white.opacity(0.28), lineWidth: active ? 1.4 : 0.8)
                    }
                    .overlay {
                        DirectionAwareTouchHighlight(
                            offset: CGSize(width: shimmer ? 16 : -12, height: shimmer ? -10 : 8),
                            isActive: active || shimmer,
                            cornerRadius: 18
                        )
                        .blendMode(.screen)
                        .opacity(active ? 0.34 : 0.2)
                    }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: symbol)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(NotebookTheme.ink)
                            .frame(width: 26, height: 26)
                            .background(.white, in: Circle())
                        Spacer(minLength: 0)
                    }

                    Spacer(minLength: 0)

                    Text(subject)
                        .font(.system(size: 12, weight: .semibold, design: .serif))
                        .foregroundStyle(NotebookTheme.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(9)
                .background(.white, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .frame(width: 88, height: 74)
                .offset(x: 18, y: 16)
            }
            .frame(width: 128, height: 104)
            .rotationEffect(.degrees(entered ? (active ? -1.8 : 0.8) : 6))
            .rotation3DEffect(.degrees(active ? 7 : -3), axis: (x: 0.18, y: 1, z: 0), perspective: 0.82)
            .scaleEffect(active ? 1.03 : 1)
            .opacity(entered ? 1 : 0)
            .offset(y: entered ? 0 : 14)
            .shadow(color: .black.opacity(active ? 0.16 : 0.09), radius: active ? 10 : 7, y: active ? 8 : 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("add \(subject)")
        .onAppear {
            withAnimation(.spring(response: 0.58, dampingFraction: 0.82).delay(delay)) {
                entered = true
            }
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true).delay(delay)) {
                shimmer = true
            }
        }
    }

    private var symbol: String {
        switch subject {
        case let text where text.contains("math") || text.contains("calculus") || text.contains("algebra") || text.contains("geometry"):
            "function"
        case let text where text.contains("biology") || text.contains("anatomy"):
            "leaf.fill"
        case let text where text.contains("chemistry"):
            "atom"
        case let text where text.contains("physics"):
            "scope"
        case let text where text.contains("computer") || text.contains("coding"):
            "chevron.left.forwardslash.chevron.right"
        case let text where text.contains("history") || text.contains("government"):
            "building.columns.fill"
        case let text where text.contains("english") || text.contains("literature") || text.contains("writing"):
            "text.book.closed.fill"
        default:
            "book.closed.fill"
        }
    }
}

private struct SelectedSubjectShelf: View {
    var subjects: [String]
    var remove: (String) -> Void

    var body: some View {
        if !subjects.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(subjects, id: \.self) { subject in
                        SubjectToken(subject: subject) {
                            remove(subject)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}
