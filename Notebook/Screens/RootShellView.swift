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
        .preferredColorScheme(store.preferredColorScheme)
    }

    private var appTabs: some View {
        TabView {
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label("shelf", systemImage: "books.vertical.fill")
            }

            ScanView()
                .tabItem {
                    Label("scan", systemImage: "viewfinder")
                }

            VoiceOnboardingView()
                .tabItem {
                    Label("voice", systemImage: "waveform")
                }

            SettingsView()
                .tabItem {
                    Label("settings", systemImage: "gearshape.fill")
                }
        }
        .tint(NotebookTheme.ink)
    }
}

private struct SetupFlowView: View {
    @Environment(NotebookStore.self) private var store
    @State private var subjectText = "math, science, history, english"
    private let prompts = [
        "today i will study with calm focus.",
        "explain this page like a patient tutor.",
        "help me remember only what matters."
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
                    themeChoice
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
                Text("voice print")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)
                Text(prompts[min(store.voiceProfile.samples.count, prompts.count - 1)])
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)

                VoiceProgress(count: store.voiceProfile.samples.count, total: prompts.count, recording: store.isRecordingVoice)

                HStack(spacing: 22) {
                    Button {
                        store.retakeVoicePrompt()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 18, weight: .bold))
                            .frame(width: 56, height: 56)
                    }
                    .buttonStyle(CircleButtonStyle(tint: NotebookTheme.muted.opacity(0.6), foreground: NotebookTheme.ink))

                    Button {
                        Task {
                            await store.recordVoicePrompt(prompts[min(store.voiceProfile.samples.count, prompts.count - 1)])
                        }
                    } label: {
                        Image(systemName: store.isRecordingVoice ? "waveform" : "mic.fill")
                            .font(.system(size: 22, weight: .bold))
                            .frame(width: 72, height: 72)
                    }
                    .buttonStyle(CircleButtonStyle(tint: NotebookTheme.ink, foreground: .white))
                }
            }
        }
    }

    private var themeChoice: some View {
        GlassSurface(radius: 26, padding: 18, interactive: true) {
            VStack(spacing: 16) {
                Text("choose theme")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)
                HStack(spacing: 10) {
                    ForEach(AppTheme.allCases) { theme in
                        Button {
                            store.chooseTheme(theme)
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: symbol(for: theme))
                                Text(theme.rawValue)
                            }
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(store.appTheme == theme ? .white : NotebookTheme.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(store.appTheme == theme ? NotebookTheme.ink : .white.opacity(0.62), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button {
                    store.continueToSubjects()
                } label: {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 58, height: 58)
                }
                .buttonStyle(CircleButtonStyle())
            }
        }
    }

    private var subjectChoice: some View {
        GlassSurface(radius: 34, padding: 20, interactive: true) {
            VStack(spacing: 16) {
                Text("subjects")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)
                Text("type your classes separated by commas.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(NotebookTheme.muted)
                TextField("math, science, history", text: $subjectText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .rounded))
                    .padding(14)
                    .background(.white.opacity(0.66), in: Capsule())

                HStack(spacing: 8) {
                    ForEach(parsedSubjects.prefix(4), id: \.self) { subject in
                        Text(subject)
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(NotebookTheme.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.white.opacity(0.58), in: Capsule())
                    }
                }

                Button {
                    store.setSubjects(parsedSubjects)
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 58, height: 58)
                }
                .buttonStyle(CircleButtonStyle())
            }
        }
    }

    private var parsedSubjects: [String] {
        subjectText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    private func symbol(for theme: AppTheme) -> String {
        switch theme {
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        case .device: "iphone"
        }
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

                    settingSection("theme") {
                        Picker("theme", selection: Bindable(store).appTheme) {
                            ForEach(AppTheme.allCases) { theme in
                                Text(theme.rawValue).tag(theme)
                            }
                        }
                        .pickerStyle(.segmented)
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
