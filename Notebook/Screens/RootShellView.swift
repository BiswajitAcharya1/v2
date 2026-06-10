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
        "math", "algebra", "geometry", "calculus", "statistics",
        "science", "biology", "chemistry", "physics", "earth science",
        "history", "world history", "us history", "government",
        "english", "literature", "writing", "spanish", "french",
        "computer science", "economics", "psychology", "art", "music"
    ]

    var body: some View {
        ZStack {
            NotebookTheme.field.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                NotebookLogo()
                    .frame(width: 132, height: 172)
                    .rotationEffect(.degrees(store.setupStep == .theme ? -4 : 3))
                    .animation(.spring(response: 0.55, dampingFraction: 0.75), value: store.setupStep)

                switch store.setupStep {
                case .voiceRecording:
                    voiceRecording
                case .theme:
                    subjectChoice
                case .subjects:
                    subjectChoice
                }

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
                Text(prompts[min(store.voiceProfile.samples.count, prompts.count - 1)])
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)

                Text(store.isRecordingVoice ? "tap again to save this sentence." : "tap once, read the sentence, then tap again.")
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(NotebookTheme.muted)
                    .multilineTextAlignment(.center)

                VoiceProgress(count: store.voiceProfile.samples.count, total: prompts.count, recording: store.isRecordingVoice)
                VoiceRecordingReadout(
                    elapsed: store.voiceRecordingElapsed,
                    level: store.voiceRecordingLevel,
                    paused: store.isVoicePaused,
                    samples: store.voiceProfile.samples
                )

                HStack(spacing: 14) {
                    Button {
                        store.retakeVoicePrompt()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 18, weight: .bold))
                            .frame(width: 56, height: 56)
                    }
                    .buttonStyle(CircleButtonStyle(tint: NotebookTheme.muted.opacity(0.6), foreground: NotebookTheme.ink))

                    if store.isRecordingVoice {
                        Button {
                            if store.isVoicePaused {
                                store.resumeVoiceRecording()
                            } else {
                                store.pauseVoiceRecording()
                            }
                        } label: {
                            Image(systemName: store.isVoicePaused ? "play.fill" : "pause.fill")
                                .font(.system(size: 18, weight: .bold))
                                .frame(width: 56, height: 56)
                        }
                        .buttonStyle(CircleButtonStyle(tint: .white.opacity(0.76), foreground: NotebookTheme.ink))
                        .transition(.scale.combined(with: .opacity))
                    }

                    Button {
                        Task {
                            await store.recordVoicePrompt(prompts[min(store.voiceProfile.samples.count, prompts.count - 1)])
                        }
                    } label: {
                        Image(systemName: store.isRecordingVoice ? "stop.fill" : "mic.fill")
                            .font(.system(size: 22, weight: .bold))
                            .frame(width: 72, height: 72)
                    }
                    .buttonStyle(CircleButtonStyle(tint: NotebookTheme.ink, foreground: .white))

                    Button {
                        store.skipVoiceSetup()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 17, weight: .bold))
                            .frame(width: 56, height: 56)
                    }
                    .buttonStyle(CircleButtonStyle(tint: .white.opacity(0.72), foreground: NotebookTheme.ink))
                }
            }
        }
    }

    private var subjectChoice: some View {
        GlassSurface(radius: 34, padding: 20, interactive: true) {
            VStack(spacing: 16) {
                Text("subjects")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)

                HStack(spacing: 10) {
                    TextField("", text: $subjectDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(NotebookTheme.ink)
                        .tint(NotebookTheme.ink)
                        .padding(14)
                        .background(.white.opacity(0.66), in: Capsule())
                        .onSubmit(addSubject)

                    Button(action: addSubject) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                            .frame(width: 50, height: 50)
                    }
                    .buttonStyle(CircleButtonStyle())
                    .disabled(bestSubjectMatch == nil)
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
                                    Image(systemName: "return")
                                        .font(.system(size: 12, weight: .bold))
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
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
            subjects.append(subject)
            subjectDraft = ""
        }
    }

    private var subjectSuggestions: [String] {
        let draft = subjectDraft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !draft.isEmpty else { return [] }
        let matches = allowedSubjects.filter { $0.hasPrefix(draft) || $0.localizedCaseInsensitiveContains(draft) }
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

    var body: some View {
        ZStack {
            Circle()
                .stroke(NotebookTheme.muted.opacity(0.16), lineWidth: 10)
            Circle()
                .trim(from: 0, to: CGFloat(count) / CGFloat(total))
                .stroke(NotebookTheme.ink, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: recording ? "waveform" : "mic")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(NotebookTheme.ink)
        }
        .frame(width: 118, height: 118)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: count)
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
                        Text(durationText(sample.duration))
                            .font(.system(.caption2, design: .monospaced, weight: .semibold))
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

private struct SettingsView: View {
    @Environment(NotebookStore.self) private var store
    @State private var spinning = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    GlassSurface(radius: 24, padding: 18, interactive: true) {
                        HStack(spacing: 14) {
                            NotebookLogo()
                                .frame(width: 58, height: 76)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(store.user.name)
                                    .font(.system(.title3, design: .rounded, weight: .semibold))
                                Text(store.authSession?.email ?? "student")
                                    .font(.system(.footnote, design: .rounded))
                                    .foregroundStyle(NotebookTheme.muted)
                            }
                            Spacer()
                            Image(systemName: "gearshape.fill")
                                .rotationEffect(.degrees(spinning ? 360 : 0))
                                .animation(.linear(duration: 5).repeatForever(autoreverses: false), value: spinning)
                        }
                        .foregroundStyle(NotebookTheme.ink)
                    }

                    settingSection("voice") {
                        Toggle("gemma voice mode", isOn: Bindable(store).gemmaVoiceModeEnabled)
                        Toggle("personal voice", isOn: Bindable(store).voiceProfile.wantsPersonalVoice)
                    }

                    settingSection("notebooks") {
                        Text("\(store.notebooks.count) subject notebooks")
                            .foregroundStyle(NotebookTheme.muted)
                        Text("\(store.notebooks.reduce(0) { $0 + $1.pages.count }) scanned pages")
                            .foregroundStyle(NotebookTheme.muted)
                    }
                }
                .padding(20)
            }
            .background(NotebookTheme.field.ignoresSafeArea())
            .navigationTitle("settings")
            .toolbarTitleDisplayMode(.inline)
            .onAppear { spinning = true }
        }
    }

    private func settingSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        GlassSurface(radius: 20, padding: 16, interactive: true) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)
                content()
                    .font(.system(.body, design: .rounded))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
