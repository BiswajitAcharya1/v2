import SwiftUI

struct VoiceOnboardingView: View {
    @Environment(NotebookStore.self) private var store
    @State private var currentIndex = 0
    @State private var pulse = false

    private let prompts = [
        "today i will study with calm focus.",
        "explain this page like a patient tutor.",
        "help me remember only what matters."
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer(minLength: 12)

                VoiceOrb(progress: Double(recordedCount) / Double(prompts.count), pulse: pulse)
                    .frame(width: 190, height: 190)

                VStack(spacing: 8) {
                    Text("voice setup")
                        .font(.system(.largeTitle, design: .serif, weight: .semibold))
                        .foregroundStyle(NotebookTheme.ink)
                    Text("record three short lines to personalize reading.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(NotebookTheme.muted)
                        .multilineTextAlignment(.center)
                }

                GlassSurface(radius: 24, padding: 18, interactive: true) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("sentence \(min(currentIndex + 1, prompts.count)) of \(prompts.count)")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(NotebookTheme.muted)
                        Text(prompts[min(currentIndex, prompts.count - 1)])
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                            .foregroundStyle(NotebookTheme.ink)
                            .lineSpacing(4)
                        Button {
                            recordCurrentPrompt()
                        } label: {
                            Label(currentIndex >= prompts.count ? "voice ready" : "hold to record", systemImage: currentIndex >= prompts.count ? "checkmark.circle.fill" : "mic.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PillButtonStyle(tint: currentIndex >= prompts.count ? NotebookTheme.accent(.green) : NotebookTheme.ink))
                    }
                }
                .padding(.horizontal, 22)

                HStack(spacing: 10) {
                    ForEach(prompts.indices, id: \.self) { index in
                        Capsule()
                            .fill(index < recordedCount ? NotebookTheme.ink : NotebookTheme.muted.opacity(0.24))
                            .frame(width: index == currentIndex ? 34 : 18, height: 8)
                    }
                }

                Spacer()
            }
            .padding(.bottom, 20)
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

    private var recordedCount: Int {
        store.voiceProfile.samples.count
    }

    private func recordCurrentPrompt() {
        guard currentIndex < prompts.count else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
            store.voiceProfile.samples.append(VoiceSample(prompt: prompts[currentIndex], isRecorded: true))
            currentIndex += 1
            store.voiceProfile.isPersonalized = currentIndex == prompts.count
        }
    }
}

private struct VoiceOrb: View {
    var progress: Double
    var pulse: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Circle()
                        .stroke(NotebookTheme.ink.opacity(0.1), lineWidth: 1)
                }
                .scaleEffect(pulse ? 1.04 : 0.98)

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
