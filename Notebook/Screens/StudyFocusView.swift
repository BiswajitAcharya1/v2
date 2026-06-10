import SwiftUI
import AVFoundation

struct StudyFocusView: View {
    @Environment(NotebookStore.self) private var store
    @State private var selectedTerm: StudyTerm?
    @State private var playback: VoicePlayback?
    @State private var isReading = false
    @State private var speechSynthesizer = AVSpeechSynthesizer()
    @State private var speechDelegate = SpeechCompletionDelegate()

    let page: NotebookPage

    private var cards: [Flashcard] {
        store.flashcards(for: page)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                insightCard
                tapToStudy
                flashcards
                voiceControls
            }
            .padding(20)
        }
        .background(LivingPaperBackground().ignoresSafeArea())
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .sheet(item: $selectedTerm) { term in
            ExplanationSheet(term: term.text)
                .presentationDetents([.medium])
        }
        .onAppear {
            speechSynthesizer.delegate = speechDelegate
            speechDelegate.onFinish = {
                isReading = false
            }
        }
        .onDisappear {
            speechSynthesizer.stopSpeaking(at: .immediate)
            isReading = false
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(page.title)
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                .foregroundStyle(NotebookTheme.ink)
            Text("focus on the smallest ideas that move your score.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(NotebookTheme.muted)
        }
    }

    private var insightCard: some View {
        NotebookPaperView {
            VStack(alignment: .leading, spacing: 14) {
                Label("only what matters", systemImage: "sparkles")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Text(page.content.sections.first?.body ?? page.content.cleanedText)
                    .font(.system(.body, design: .rounded))
                    .lineSpacing(5)
                HStack {
                    PageChip(text: "recall", systemName: "brain.head.profile")
                    PageChip(text: page.studyState.dueLabel, systemName: "calendar")
                }
            }
            .foregroundStyle(NotebookTheme.ink)
        }
    }

    private var tapToStudy: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("tap to study")
                .font(.notebookSection)
                .foregroundStyle(NotebookTheme.ink)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 10)], spacing: 10) {
                ForEach(page.content.keywords + page.content.formulas, id: \.self) { token in
                    Button {
                        Haptics.selection()
                        selectedTerm = StudyTerm(text: token)
                    } label: {
                        Text(token)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(NotebookTheme.ink)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var flashcards: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("flashcards")
                    .font(.notebookSection)
                Spacer()
                Picker("mode", selection: Bindable(store).selectedStudyMode) {
                    ForEach(MemorizationMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
                .onChange(of: store.selectedStudyMode) {
                    Haptics.selection()
                }
            }
            .foregroundStyle(NotebookTheme.ink)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        FlashcardPaper(
                            card: card,
                            dueLabel: store.schedule(for: card, mode: store.selectedStudyMode).dueLabel,
                            tilt: index.isMultiple(of: 2) ? -1.2 : 1.2
                        )
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var voiceControls: some View {
        GlassSurface(radius: 22, padding: 16, interactive: true) {
            VStack(alignment: .leading, spacing: 14) {
                Text("read aloud")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                HStack(spacing: 14) {
                    ForEach(PlaybackStyle.allCases) { style in
                        Button {
                            Haptics.open()
                            if isReading {
                                speechSynthesizer.stopSpeaking(at: .immediate)
                                isReading = false
                            } else {
                                isReading = true
                                Task { @MainActor in
                                    playback = await store.readAloud(page, style: style)
                                    speak(page.content.cleanedText, style: style)
                                }
                            }
                        } label: {
                            VoiceStyleButton(style: style, active: isReading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(playback?.summary ?? (isReading ? "reading now" : "choose a playback style"))
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(NotebookTheme.muted)
            }
            .foregroundStyle(NotebookTheme.ink)
        }
    }

    private func speak(_ text: String, style: PlaybackStyle) {
        speechSynthesizer.stopSpeaking(at: AVSpeechBoundary.immediate)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        switch style {
        case .calmTutor:
            utterance.rate = 0.43
            utterance.pitchMultiplier = store.voiceProfile.isPersonalized ? 0.96 : 1.0
        case .focusedReview:
            utterance.rate = 0.52
            utterance.pitchMultiplier = store.voiceProfile.isPersonalized ? 0.98 : 1.02
        case .examPrep:
            utterance.rate = 0.58
            utterance.pitchMultiplier = store.voiceProfile.isPersonalized ? 1.0 : 1.05
        }
        speechSynthesizer.speak(utterance)
    }

}

private final class SpeechCompletionDelegate: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    var onFinish: (() -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.onFinish?() }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.onFinish?() }
    }
}

private struct ExplanationSheet: View {
    @Environment(NotebookStore.self) private var store
    let term: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Capsule()
                .fill(NotebookTheme.muted.opacity(0.28))
                .frame(width: 44, height: 5)
                .frame(maxWidth: .infinity)
            Text(term.lowercased())
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                .foregroundStyle(NotebookTheme.ink)
            Text(store.flashcards(for: NotebookFixtures.notebooks[0].pages[0]).first?.back ?? "study this idea in one small step.")
                .font(.notebookBody)
                .foregroundStyle(NotebookTheme.muted)
            Text(store.explain(term.lowercased()))
                .font(.notebookBody)
                .foregroundStyle(NotebookTheme.ink)
                .lineSpacing(5)
            Spacer()
        }
        .padding(24)
        .background(NotebookTheme.field)
    }
}

private struct FlashcardPaper: View {
    let card: Flashcard
    let dueLabel: String
    let tilt: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(card.front)
                .font(.system(.headline, design: .serif, weight: .semibold))
                .foregroundStyle(NotebookTheme.ink)
                .lineLimit(3)
            Text(card.back)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(NotebookTheme.muted)
                .lineSpacing(4)
            Spacer(minLength: 2)
            PageChip(text: dueLabel, systemName: "arrow.triangle.2.circlepath")
        }
        .padding(16)
        .frame(width: 244, height: 174, alignment: .leading)
        .background(NotebookTheme.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            PaperRules()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .opacity(0.42)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.68), lineWidth: 0.8)
        }
        .rotationEffect(.degrees(tilt))
        .shadow(color: .black.opacity(0.1), radius: 12, y: 8)
    }
}

private struct VoiceStyleButton: View {
    let style: PlaybackStyle
    var active: Bool

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(active ? .white : NotebookTheme.ink)
                .frame(width: 52, height: 52)
                .background(active ? NotebookTheme.ink : .white.opacity(0.66), in: Circle())
                .overlay {
                    Circle().stroke(.white.opacity(0.72), lineWidth: 0.8)
                }
                .scaleEffect(active ? 1.08 : 1)
            Text(shortLabel)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(NotebookTheme.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var symbol: String {
        switch style {
        case .calmTutor: "sparkle"
        case .focusedReview: "waveform"
        case .examPrep: "bolt.fill"
        }
    }

    private var shortLabel: String {
        switch style {
        case .calmTutor: "calm"
        case .focusedReview: "focus"
        case .examPrep: "exam"
        }
    }
}

private struct StudyTerm: Identifiable, Hashable {
    let id = UUID()
    var text: String
}
