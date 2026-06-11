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
    private let prompts = [
        "today i will study with calm focus.",
        "explain this page like a patient tutor.",
        "help me remember only what matters."
    ]
    private let allowedSubjects = [
        "math", "pre algebra", "algebra", "geometry", "trigonometry", "precalculus", "calculus", "statistics",
        "science", "biology", "chemistry", "physics", "environmental science", "earth science", "anatomy",
        "history", "world history", "us history", "european history", "government", "civics",
        "english", "literature", "writing", "creative writing", "spanish", "french", "latin",
        "computer science", "coding", "data science", "robotics", "economics", "psychology", "sociology",
        "art", "music", "theater", "health", "business", "engineering"
    ]

    var body: some View {
        ZStack {
            LivingPaperBackground().ignoresSafeArea()
            if store.setupStep == .voiceRecording {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            Haptics.softTap()
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                                store.skipVoiceSetup()
                            }
                        } label: {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(NotebookTheme.ink)
                                .frame(width: 52, height: 52)
                                .background(.ultraThinMaterial, in: Circle())
                                .rotationEffect(.degrees(store.setupStep == .voiceRecording ? 0 : 90))
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 20)
                        .padding(.top, 18)
                    }
                    Spacer()
                }
            }
            VStack(spacing: 24) {
                Spacer()
                NotebookLogo()
                    .frame(width: 132, height: 172)
                    .rotationEffect(.degrees(store.setupStep == .theme ? -4 : 3))
                    .animation(.spring(response: 0.55, dampingFraction: 0.75), value: store.setupStep)

                Group {
                    switch store.setupStep {
                    case .voiceRecording:
                        voiceRecording
                    case .theme:
                        subjectChoice
                    case .subjects:
                        subjectChoice
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.98)),
                    removal: .move(edge: .leading).combined(with: .opacity).combined(with: .scale(scale: 1.02))
                ))
                .animation(.spring(response: 0.62, dampingFraction: 0.84), value: store.setupStep)

                Spacer()
            }
            .padding(22)
        }
    }

    private var voiceRecording: some View {
        GlassSurface(radius: 34, padding: 20, interactive: true) {
            VStack(spacing: 18) {
                Text("voice")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)
                Text(voiceInstructionText)
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(NotebookTheme.muted)
                    .multilineTextAlignment(.center)

                VoicePromptText(
                    prompt: currentVoicePrompt,
                    progress: store.voicePromptWordProgress,
                    recording: store.isRecordingVoice,
                    voiceActive: store.voiceSignalActive
                )

                VoiceRecognitionStatus(
                    sentenceIndex: min(store.voiceProfile.samples.count + 1, prompts.count),
                    totalSentences: prompts.count,
                    heardWords: store.voicePromptWordProgress,
                    totalWords: currentVoicePrompt.split(separator: " ").count,
                    isRecording: store.isRecordingVoice,
                    isPreparing: store.isPreparingVoiceRecording,
                    voiceActive: store.voiceSignalActive,
                    recognitionAvailable: store.voiceRecognitionAvailable,
                    level: store.voiceRecordingLevel
                )

                VoiceProgress(count: store.voiceProfile.samples.count, total: prompts.count, recording: store.isRecordingVoice, preparing: store.isPreparingVoiceRecording)
                VoiceRecordingReadout(
                    elapsed: store.voiceRecordingElapsed,
                    level: store.voiceRecordingLevel,
                    paused: store.isVoicePaused,
                    samples: store.voiceProfile.samples
                )

                HStack(spacing: 14) {
                    Button {
                        Haptics.softTap()
                        store.retakeVoicePrompt()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 18, weight: .bold))
                            .frame(width: 56, height: 56)
                    }
                    .buttonStyle(CircleButtonStyle(tint: NotebookTheme.muted.opacity(0.6), foreground: NotebookTheme.ink))
                    .disabled(store.voiceProfile.samples.isEmpty || store.isRecordingVoice || store.isPreparingVoiceRecording)
                    .opacity(store.voiceProfile.samples.isEmpty || store.isRecordingVoice || store.isPreparingVoiceRecording ? 0.38 : 1)

                    Button {
                        Haptics.open()
                        Task {
                            await store.recordVoicePrompt(currentVoicePrompt)
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(.white.opacity(0.26), lineWidth: 8)
                                .scaleEffect(store.isRecordingVoice ? 1.18 + store.voiceRecordingLevel * 0.12 : 1)
                                .opacity(store.isRecordingVoice ? 1 : 0)
                            Image(systemName: voiceRecordSymbol)
                                .font(.system(size: 22, weight: .bold))
                                .frame(width: 72, height: 72)
                        }
                    }
                    .buttonStyle(CircleButtonStyle(tint: NotebookTheme.ink, foreground: .white))
                    .disabled(store.isPreparingVoiceRecording)
                    .scaleEffect(store.isPreparingVoiceRecording ? 0.96 : 1)
                    .accessibilityLabel(store.isRecordingVoice ? "finish recording" : "start recording")
                }
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
            return "keep reading naturally. the meter saves your voice sample."
        }
        return "read each sentence once. words darken only when they are matched."
    }

    private var voiceRecordSymbol: String {
        if store.isPreparingVoiceRecording { return "ellipsis" }
        return store.isRecordingVoice ? "waveform" : "mic.fill"
    }

    private var subjectChoice: some View {
        GlassSurface(radius: 34, padding: 20, interactive: true) {
            VStack(spacing: 16) {
                Text("subjects")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)

                HStack(spacing: 10) {
                    GooeyInput(
                        label: "subject",
                        systemName: "magnifyingglass",
                        text: $subjectDraft,
                        onSubmit: addSubject
                    )

                    Button(action: addSubject) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                            .frame(width: 54, height: 54)
                    }
                    .buttonStyle(FloatingCircleButtonStyle())
                    .disabled(bestSubjectMatch == nil)
                    .opacity(bestSubjectMatch == nil ? 0.42 : 1)
                }

                if !subjectSuggestions.isEmpty {
                    VStack(spacing: 7) {
                        ForEach(subjectSuggestions, id: \.self) { subject in
                            Button {
                                addSubject(subject)
                            } label: {
                                HStack {
                                    Text(subject)
                                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    Spacer()
                                    Image(systemName: "plus")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 26, height: 26)
                                        .background(NotebookTheme.ink, in: Circle())
                            }
                                .foregroundStyle(NotebookTheme.ink)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(.ultraThinMaterial, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.72, dampingFraction: 0.86), value: subjectSuggestions)
                }

                if !subjects.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(subjects, id: \.self) { subject in
                                SubjectToken(subject: subject) {
                                    subjects.removeAll { $0 == subject }
                                }
                            }
                        }
                    }
                }

                Button {
                    Haptics.success()
                    store.setSubjects(subjects)
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 58, height: 58)
                }
                .buttonStyle(CircleButtonStyle())
                .disabled(subjects.isEmpty)
            }
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
        let draft = subjectDraft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let availableSubjects = allowedSubjects.filter { !subjects.contains($0) }
        guard !draft.isEmpty else {
            let featured = ["biology", "math", "computer science", "chemistry", "history", "english"]
            return Array((featured.filter { availableSubjects.contains($0) } + availableSubjects.filter { !featured.contains($0) }).prefix(6))
        }
        let matches = availableSubjects.filter { $0.hasPrefix(draft) || $0.localizedCaseInsensitiveContains(draft) }
        return Array(matches[0..<min(matches.count, 4)])
    }

    private var bestSubjectMatch: String? {
        let draft = subjectDraft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !draft.isEmpty else { return nil }
        if allowedSubjects.contains(draft) { return draft }
        return allowedSubjects.first { $0.hasPrefix(draft) }
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
        .frame(width: 118, height: 118)
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
            return "voice captured"
        }
        return recognitionAvailable ? "listening for words" : "listening for your voice"
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
    }
}
