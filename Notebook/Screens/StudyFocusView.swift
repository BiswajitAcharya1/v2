import SwiftUI

struct StudyFocusView: View {
    @Environment(NotebookStore.self) private var store
    @State private var selectedTerm: StudyTerm?
    @State private var playback: VoicePlayback?
    @State private var isReading = false
    @State private var isListening = false

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
                gemmaVoiceMode
                voiceControls
            }
            .padding(20)
        }
        .background(NotebookTheme.field.ignoresSafeArea())
        .navigationTitle("study")
        .toolbarTitleDisplayMode(.inline)
        .sheet(item: $selectedTerm) { term in
            ExplanationSheet(term: term.text)
                .presentationDetents([.medium])
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
            }
            .foregroundStyle(NotebookTheme.ink)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(cards) { card in
                        GlassSurface(radius: 18, padding: 16, interactive: true) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(card.front)
                                    .font(.system(.headline, design: .rounded, weight: .semibold))
                                Text(card.back)
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(NotebookTheme.muted)
                                PageChip(text: store.schedule(for: card, mode: store.selectedStudyMode).dueLabel, systemName: "arrow.triangle.2.circlepath")
                            }
                            .frame(width: 238, alignment: .leading)
                        }
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
                HStack {
                    ForEach(PlaybackStyle.allCases) { style in
                        Button(style.rawValue) {
                            isReading = true
                            Task { @MainActor in
                                playback = await store.readAloud(page, style: style)
                                isReading = false
                            }
                        }
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.6), in: Capsule())
                    }
                }
                Text(playback?.summary ?? (isReading ? "preparing voice" : "choose a playback style"))
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(NotebookTheme.muted)
            }
            .foregroundStyle(NotebookTheme.ink)
        }
    }

    private var gemmaVoiceMode: some View {
        GlassSurface(radius: 22, padding: 16, interactive: true) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("voice mode", systemImage: "waveform.circle.fill")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                    Spacer()
                    Toggle("", isOn: Bindable(store).gemmaVoiceModeEnabled)
                        .labelsHidden()
                }

                Text(store.latestVoiceQuestion ?? (isListening ? "listening through faster whisper" : "talk to gemma about this page."))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(NotebookTheme.muted)

                Button {
                    isListening = true
                    Task { @MainActor in
                        await store.askGemmaByVoice()
                        isListening = false
                    }
                } label: {
                    Image(systemName: isListening ? "waveform" : "mic.fill")
                        .font(.system(size: 20, weight: .bold))
                        .frame(width: 58, height: 58)
                }
                .buttonStyle(CircleButtonStyle(tint: NotebookTheme.accent(.plum), foreground: .white))
                .accessibilityLabel(isListening ? "transcribing" : "ask with voice")
            }
            .foregroundStyle(NotebookTheme.ink)
        }
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

private struct StudyTerm: Identifiable, Hashable {
    let id = UUID()
    var text: String
}
