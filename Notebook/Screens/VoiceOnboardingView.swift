import SwiftUI

struct VoiceOnboardingView: View {
    @Environment(NotebookStore.self) private var store
    @State private var pulse = false

    private let prompts = [
        "today i will study with calm focus.",
        "explain this page like a patient tutor.",
        "help me remember only what matters."
    ]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 24) {
                    Spacer(minLength: 12)

                    VoiceOrb(progress: Double(recordedCount) / Double(prompts.count), pulse: pulse, level: store.voiceRecordingLevel)
                        .frame(width: 190, height: 190)

                    VStack(spacing: 8) {
                        Text("voice setup")
                            .font(.system(.largeTitle, design: .serif, weight: .semibold))
                            .foregroundStyle(NotebookTheme.ink)
                        Text(voiceSubtitle)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(NotebookTheme.muted)
                            .multilineTextAlignment(.center)
                    }

                    GlassSurface(radius: 24, padding: 18, interactive: true) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("sentence \(min(recordedCount + 1, prompts.count)) of \(prompts.count)")
                                .font(.system(.caption, design: .rounded, weight: .semibold))
                                .foregroundStyle(NotebookTheme.muted)
                            VoicePromptWordsView(
                                prompt: currentPrompt,
                                progress: store.voicePromptWordProgress,
                                recording: store.isRecordingVoice,
                                voiceActive: store.voiceSignalActive
                            )
                            Text(statusText)
                                .font(.system(.caption, design: .rounded, weight: .semibold))
                                .foregroundStyle(store.isRecordingVoice && store.voiceSignalActive ? NotebookTheme.accent(.green) : NotebookTheme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .animation(.spring(response: 0.25, dampingFraction: 0.76), value: store.voiceSignalActive)
                            VoiceLevelStrip(level: store.voiceRecordingLevel, recording: store.isRecordingVoice)
                            Button {
                                recordCurrentPrompt()
                            } label: {
                                Image(systemName: recordedCount >= prompts.count ? "checkmark" : store.isRecordingVoice ? "waveform" : "mic.fill")
                                    .font(.system(size: 20, weight: .bold))
                                    .frame(width: 64, height: 64)
                            }
                            .buttonStyle(CircleButtonStyle(tint: recordedCount >= prompts.count ? NotebookTheme.accent(.green) : NotebookTheme.ink, foreground: .white))
                            .accessibilityLabel(recordedCount >= prompts.count ? "voice ready" : store.isRecordingVoice ? "finish recording" : "record")
                        }
                    }
                    .padding(.horizontal, 22)

                    HStack(spacing: 10) {
                        ForEach(prompts.indices, id: \.self) { index in
                            Capsule()
                                .fill(index < recordedCount ? NotebookTheme.ink : NotebookTheme.muted.opacity(0.24))
                                .frame(width: index == min(recordedCount, prompts.count - 1) ? 34 : 18, height: 8)
                        }
                    }

                    Spacer()
                }
                .padding(.bottom, 20)

                Button {
                    Haptics.softTap()
                    store.skipVoiceSetup()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(NotebookTheme.ink)
                        .frame(width: 50, height: 50)
                }
                .buttonStyle(.plain)
                .background(.ultraThinMaterial, in: Circle())
                .padding(.top, 18)
                .padding(.trailing, 20)
                .accessibilityLabel("skip voice")
            }
            .background(NotebookTheme.field.ignoresSafeArea())
            .navigationTitle("voice")
            .toolbarTitleDisplayMode(.inline)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
    }

    private var currentPrompt: String {
        prompts[min(recordedCount, prompts.count - 1)]
    }

    private var recordedCount: Int {
        store.voiceProfile.samples.count
    }

    private var statusText: String {
        guard store.isRecordingVoice else {
            return "tap once and read naturally."
        }
        if store.voiceSignalActive {
            if store.voiceRecognitionAvailable {
                return "\(min(store.voicePromptWordProgress, currentPrompt.split(separator: " ").count)) words heard"
            }
            return "voice captured"
        }
        return store.voiceRecognitionAvailable ? "listening for words" : "listening for your voice"
    }

    private var voiceSubtitle: String {
        if store.isRecordingVoice && !store.voiceRecognitionAvailable {
            return "keep reading naturally. the meter saves your voice sample."
        }
        return store.isRecordingVoice ? durationText(store.voiceRecordingElapsed) : "record three short lines to personalize reading."
    }

    private func recordCurrentPrompt() {
        guard recordedCount < prompts.count else {
            store.continueToSubjects()
            return
        }
        Haptics.open()
        Task {
            await store.recordVoicePrompt(currentPrompt)
        }
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

private struct VoiceLevelStrip: View {
    var level: Double
    var recording: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<18, id: \.self) { index in
                Capsule()
                    .fill(NotebookTheme.ink.opacity(recording ? 0.22 + level * 0.62 : 0.16))
                    .frame(width: 4, height: barHeight(index))
                    .animation(.spring(response: 0.22, dampingFraction: 0.72), value: level)
            }
        }
        .frame(height: 44)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let wave = 0.5 + 0.5 * sin(Double(index) * 0.74 + level * 8)
        return 8 + CGFloat(recording ? max(0.08, level) * wave * 34 : 0)
    }
}

private struct VoiceOrb: View {
    var progress: Double
    var pulse: Bool
    var level: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Circle()
                        .stroke(NotebookTheme.ink.opacity(0.1), lineWidth: 1)
                }
                .scaleEffect(pulse ? 1.04 + level * 0.04 : 0.98)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(NotebookTheme.ink, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(12)

            VStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.system(size: 42, weight: .semibold))
                Text("\(Int(progress * 100))%")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
            }
            .foregroundStyle(NotebookTheme.ink)
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.82), value: progress)
    }
}
