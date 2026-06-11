import SwiftUI
import UIKit

struct AuthView: View {
    @Environment(NotebookStore.self) private var store
    @State private var appeared = true
    @State private var showingEmail = false
    @State private var isSignIn = false
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var closeRotation = 0.0
    @State private var leatherDrift = false
    @State private var notebookOpen = false
    @State private var coverDrag: CGFloat = 0
    @State private var legalDocument: LegalDocument?
    @State private var ambientMotion = false
    @State private var authControlsReady = false

    var body: some View {
        ZStack {
            AmbientNotebookBackground(animated: ambientMotion).ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer(minLength: 0)

                heroStack
                    .scaleEffect(appeared ? 1 : 0.92)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: notebookOpen ? -22 : -176)

                if notebookOpen {
                    authPanel
                        .padding(.horizontal, 22)
                        .offset(y: appeared ? 48 : 74)
                        .opacity(appeared ? 1 : 0)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Spacer(minLength: 18)
            }
            .padding(.bottom, 18)

            if showingEmail {
                emailSheet
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.94)),
                        removal: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.96))
                    ))
            }

        }
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(650))
                withAnimation(.easeInOut(duration: 0.62)) {
                    ambientMotion = true
                }
                withAnimation(.easeInOut(duration: 4.8).repeatForever(autoreverses: true)) {
                    leatherDrift = true
                }
            }
        }
        .sheet(item: $legalDocument) { document in
            LegalDocumentView(document: document)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var heroStack: some View {
        VStack(spacing: 14) {
            if openProgress > 0.18 {
                VStack(spacing: 8) {
                    BrandSignUpTitle()
                    ContainerTextFlip(words: ["scan", "organize", "study", "remember", "focus", "listen", "review", "recall", "diagram", "practice", "learn", "master"])
                }
                .opacity(Double(min(1, openProgress * 1.35)))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            draggableAuthBook
                .frame(width: 430, height: 414)
            if notebookOpen, let message = store.authMessage, !showingEmail {
                AuthNotice(message: message)
                    .padding(.horizontal, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(height: notebookOpen ? 484 : 386)
    }

    private var openProgress: CGFloat {
        if notebookOpen {
            return max(0, min(1, 1 + coverDrag / 180))
        }
        return max(0, min(1, -coverDrag / 128))
    }

    private var draggableAuthBook: some View {
            ZStack {
                AuthPaperInterior(openProgress: openProgress)
                    .overlay {
                        if openProgress > 0.54 {
                            VStack(spacing: 14) {
                            ForEach(Array(AuthProvider.allCases.enumerated()), id: \.element.id) { index, provider in
                                AuthProviderPageButton(provider: provider) {
                                    guard authControlsReady else { return }
                                    if provider == .email {
                                        Haptics.open()
                                        withAnimation(.spring(response: 1.02, dampingFraction: 0.88)) {
                                            isSignIn = false
                                            showingEmail = true
                                        }
                                    } else {
                                        Task { await store.signIn(provider: provider) }
                                    }
                                }
                                .offset(x: (1 - openProgress) * 26, y: (1 - openProgress) * 34)
                                .animation(.spring(response: 0.96, dampingFraction: 0.9).delay(Double(index) * 0.09), value: notebookOpen)
                            }
                        }
                        .frame(maxWidth: 330)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .padding(.horizontal, 28)
                        .opacity(Double((openProgress - 0.54) / 0.46))
                        .scaleEffect(0.9 + openProgress * 0.1)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .allowsHitTesting(authControlsReady)
                    }
                }
                .frame(width: 266 + openProgress * 204, height: 342 + openProgress * 126)
                .rotation3DEffect(.degrees(-6 + openProgress * 13), axis: (x: 1, y: 0.18, z: 0), perspective: 0.72)
                .offset(x: openProgress * 74, y: openProgress * 16)
                .shadow(color: .black.opacity(0.12), radius: 16, y: 10)

            CompositionCoverFace(
                subject: nil,
                cornerRadius: 22,
                spineWidth: 7,
                labelWidth: 152,
                labelHeight: 104,
                labelOffsetY: 36,
                paperGrainDensity: notebookOpen || coverDrag < -2 ? 90 : 0
            )
                .frame(width: 236, height: 306)
                .rotation3DEffect(.degrees(-156 * openProgress + (leatherDrift ? 2.5 : -2.5)), axis: (x: 0.02, y: 1, z: 0), anchor: .leading, perspective: 0.68)
                .offset(x: -132 * openProgress, y: 4 + 13 * openProgress)
                .opacity(Double(1 - max(0, (openProgress - 0.58) / 0.26)))
                .scaleEffect(1 - openProgress * 0.08)
                .shadow(color: .black.opacity(0.22), radius: 18, y: 12)
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            if !notebookOpen && value.translation.width < -42 {
                                Haptics.selection()
                            }
                            coverDrag = min(18, max(-170, value.translation.width))
                        }
                        .onEnded { value in
                            let shouldOpen = notebookOpen ? value.translation.width > -70 : value.translation.width < -88
                            if shouldOpen != notebookOpen {
                                Haptics.open()
                            } else {
                                Haptics.softTap()
                            }
                            withAnimation(.spring(response: 0.98, dampingFraction: 0.86)) {
                                notebookOpen = shouldOpen
                                coverDrag = 0
                            }
                            settleAuthControls(open: shouldOpen)
                        }
                )
                .onTapGesture {
                    guard !notebookOpen else { return }
                    Haptics.open()
                    withAnimation(.spring(response: 0.98, dampingFraction: 0.86)) {
                        notebookOpen = true
                        coverDrag = 0
                    }
                    settleAuthControls(open: true)
                }
                .accessibilityLabel("drag notebook cover")
                .accessibilityHint("tap or drag left to open sign up")
        }
        .scaleEffect(notebookOpen ? 1.03 : 1)
        .animation(.spring(response: 0.78, dampingFraction: 0.88), value: notebookOpen)
        .animation(.spring(response: 0.46, dampingFraction: 0.86), value: coverDrag)
    }

    private func settleAuthControls(open: Bool) {
        authControlsReady = false
        guard open else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(620))
            if notebookOpen {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                    authControlsReady = true
                }
            }
        }
    }

    private var authPanel: some View {
        VStack(spacing: 12) {
            Button {
                Haptics.press()
                withAnimation(.spring(response: 1.02, dampingFraction: 0.88)) {
                    isSignIn = true
                    showingEmail = true
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle")
                    Text("have an account? sign in")
                }
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(NotebookTheme.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)

            HStack(spacing: 16) {
                legalLink(.terms)
                legalLink(.privacy)
            }
        }
    }

    private func legalLink(_ document: LegalDocument) -> some View {
        Button {
            Haptics.softTap()
            legalDocument = document
        } label: {
            Text(document.title)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(NotebookTheme.muted)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private struct BrandSignUpTitle: View {
        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("sign")
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                FontFlipText("up")
            }
            .foregroundStyle(NotebookTheme.ink)
        }
    }

    private struct FontFlipText: View {
        let text: String
        @State private var index = 0
        private struct FontMood {
            let name: String?
            let design: Font.Design
            let weight: Font.Weight
            let italic: Bool
            let size: CGFloat
        }

        private let moods: [FontMood] = [
            .init(name: "NewYork-Regular", design: .serif, weight: .semibold, italic: false, size: 45),
            .init(name: "AvenirNext-DemiBold", design: .rounded, weight: .semibold, italic: false, size: 42),
            .init(name: "Didot", design: .serif, weight: .regular, italic: true, size: 46),
            .init(name: "Futura-Medium", design: .default, weight: .medium, italic: false, size: 41),
            .init(name: "HoeflerText-Regular", design: .serif, weight: .regular, italic: true, size: 46),
            .init(name: nil, design: .monospaced, weight: .bold, italic: false, size: 40),
            .init(name: "Georgia-Bold", design: .serif, weight: .bold, italic: false, size: 42),
            .init(name: nil, design: .rounded, weight: .light, italic: false, size: 44),
            .init(name: "AvenirNext-UltraLight", design: .default, weight: .light, italic: false, size: 45),
            .init(name: nil, design: .serif, weight: .semibold, italic: true, size: 45),
            .init(name: "Menlo-Bold", design: .monospaced, weight: .bold, italic: false, size: 38),
            .init(name: nil, design: .default, weight: .medium, italic: false, size: 43)
        ]

        init(_ text: String) {
            self.text = text
        }

        var body: some View {
            ZStack(alignment: .leading) {
                ForEach(moods.indices, id: \.self) { designIndex in
                    fontText(for: designIndex)
                        .opacity(index == designIndex ? 1 : 0)
                        .scaleEffect(index == designIndex ? 1 : 0.94)
                        .blur(radius: index == designIndex ? 0 : 3)
                }
            }
            .frame(width: 62, height: 52, alignment: .leading)
            .clipped()
            .animation(.spring(response: 0.58, dampingFraction: 0.86), value: index)
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(920))
                    index = (index + 1) % moods.count
                }
            }
        }

        @ViewBuilder
        private func fontText(for designIndex: Int) -> some View {
            let mood = moods[designIndex]
            let base = Text(text)
                .font(mood.name.map { .custom($0, size: mood.size) } ?? .system(size: mood.size, weight: mood.weight, design: mood.design))
                .fontWeight(mood.weight)
                .baselineOffset(designIndex == 2 ? -1 : 0)

            if mood.italic {
                base.italic()
            } else {
                base
            }
        }
    }

    private struct EncryptedTextLine: View {
        let text: String
        var revealDelayMs: UInt64 = 50

        @State private var revealedCount = 0
        @State private var tick = 0

        private let glyphs = Array("abcdefghijklmnopqrstuvwxyz0123456789")

        var body: some View {
            Text(renderedText)
                .font(.system(.footnote, design: .monospaced, weight: .medium))
                .foregroundStyle(revealedCount >= text.count ? NotebookTheme.muted : NotebookTheme.muted.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .animation(.easeOut(duration: 0.18), value: renderedText)
                .task(id: text) {
                    revealedCount = 0
                    tick = 0
                    while revealedCount < text.count, !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(revealDelayMs))
                        tick += 1
                        revealedCount += 1
                    }
                }
        }

        private var renderedText: String {
            let characters = Array(text)
            return String(characters.enumerated().map { index, character in
                guard character != " " else { return character }
                if index < revealedCount {
                    return character
                }
                return glyphs[(index + tick * 3) % glyphs.count]
            })
        }
    }

    private struct AuthProviderPageButton: View {
        let provider: AuthProvider
        var action: () -> Void
        @State private var shimmer = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Circle().stroke(.white.opacity(0.74), lineWidth: 1)
                        }
                        .frame(width: 36, height: 36)
                        .overlay { providerMark }
                    Text(provider.title)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(NotebookTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(.white.opacity(0.68), in: Capsule())
                .overlay {
                    InteractiveSheen(progress: shimmer ? 1 : 0, cornerRadius: 28)
                        .opacity(0.48)
                }
                .overlay {
                    Capsule().stroke(.black.opacity(0.06), lineWidth: 1)
                }
                .contentShape(Capsule())
                .accessibilityLabel(provider.title)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { Haptics.press() })
            .onAppear {
                withAnimation(.easeInOut(duration: 1.45).delay(0.22)) {
                    shimmer = true
                }
            }
        }

        @ViewBuilder
        private var providerMark: some View {
            switch provider {
            case .apple:
                Image(systemName: "apple.logo")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)
            case .google:
                GoogleLogo()
                    .frame(width: 18, height: 18)
            case .email:
                Image(systemName: "envelope.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)
            }
        }
    }

    private struct AuthNotice: View {
        let message: String
        @State private var awake = false

        var body: some View {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(NotebookTheme.ink)
                    Circle()
                        .trim(from: 0.08, to: 0.34)
                        .stroke(.white.opacity(0.34), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                        .rotationEffect(.degrees(awake ? 126 : -20))
                        .padding(5)
                    Image(systemName: "key.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 34, height: 34)

                Text(message)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink.opacity(0.76))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 0)
            }
            .padding(.leading, 8)
            .padding(.trailing, 13)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule().stroke(.white.opacity(0.62), lineWidth: 0.8)
            }
            .scaleEffect(awake ? 1 : 0.97)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                    awake = true
                }
            }
        }
    }

    private var emailSheet: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.18))
                .ignoresSafeArea()
                .onTapGesture { closeEmail() }

            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isSignIn ? "sign in" : "sign up")
                            .font(.system(.title2, design: .serif, weight: .semibold))
                            .foregroundStyle(NotebookTheme.ink)
                        EncryptedTextLine(text: isSignIn ? "secure access" : "create secure access")
                            .id(isSignIn ? "sign-in-security" : "sign-up-security")
                    }
                    Spacer()
                    Button {
                        closeEmail()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 42, height: 42)
                            .foregroundStyle(NotebookTheme.ink)
                            .background(.white.opacity(0.7), in: Circle())
                            .rotationEffect(.degrees(closeRotation))
                    }
                    .buttonStyle(.plain)
                }

                VStack(spacing: 10) {
                    if !isSignIn {
                        AuthField(label: "username", systemName: "person.fill", text: $username)
                        AuthField(label: "gmail", systemName: "envelope.fill", text: $email, keyboardType: .emailAddress)
                    } else {
                        AuthField(label: "email", systemName: "envelope.fill", text: $email, keyboardType: .emailAddress)
                    }
                    secureField("password", text: $password)
                    if !isSignIn {
                        secureField("confirm password", text: $confirmPassword)
                        passwordMeter
                    }
                }

                AuthKeyboardPreview(
                    typedCount: username.count + email.count + password.count + confirmPassword.count,
                    compact: isSignIn
                )
                .frame(height: isSignIn ? 70 : 84)
                .padding(.top, 2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                if let message = store.authMessage {
                    Text(message)
                        .font(.system(.footnote, design: .rounded, weight: .medium))
                        .foregroundStyle(NotebookTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Haptics.open()
                    Task {
                        if isSignIn {
                            await store.signIn(email: email, password: password)
                        } else {
                            await store.signUp(username: username, email: email, password: password, confirmPassword: confirmPassword)
                        }
                    }
                } label: {
                    Image(systemName: isSignIn ? "arrow.right" : "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 58, height: 58)
                }
                .buttonStyle(CircleButtonStyle(tint: NotebookTheme.ink, foreground: .white))

                if isSignIn {
                    Button {
                        Haptics.rigid()
                        Task { await store.resetPassword(email: email) }
                    } label: {
                        Label("forgot password", systemImage: "faceid")
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .foregroundStyle(NotebookTheme.ink)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .background(NotebookTheme.field, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(0.7), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private var passwordMeter: some View {
        if !password.isEmpty {
            let strength = passwordStrength(password)
            VStack(alignment: .leading, spacing: 7) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(NotebookTheme.muted.opacity(0.16))
                        Capsule()
                            .fill(strength.color)
                            .frame(width: proxy.size.width * width(for: strength))
                            .animation(.spring(response: 0.35, dampingFraction: 0.78), value: strength.rawValue)
                    }
                }
                .frame(height: 8)
                Text(passwordGuidance(for: strength))
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(strength.color)
            }
        }
    }

    private func width(for strength: PasswordStrength) -> CGFloat {
        switch strength {
        case .weak: 0.32
        case .medium: 0.66
        case .good: 1
        }
    }

    private func passwordGuidance(for strength: PasswordStrength) -> String {
        switch strength {
        case .weak:
            "weak password. add 8 characters, a number, and a symbol."
        case .medium:
            "medium password. add uppercase or a symbol to make it stronger."
        case .good:
            "good password."
        }
    }

    private func secureField(_ title: String, text: Binding<String>) -> some View {
        GooeyInput(
            label: title,
            systemName: "lock.fill",
            text: text,
            isSecure: true,
            textContentType: .password
        )
    }

    private func closeEmail() {
        Haptics.softTap()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.7)) {
            closeRotation += 90
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                showingEmail = false
            }
        }
    }
}

private struct AuthField: View {
    var label: String
    var systemName: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        GooeyInput(
            label: label,
            systemName: systemName,
            text: $text,
            keyboardType: keyboardType
        )
    }
}

private struct AuthKeyboardPreview: View {
    var typedCount: Int
    var compact: Bool
    @State private var glow = false

    private let rows = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["z", "x", "c", "v", "b", "n", "m"]
    ]

    var body: some View {
        GeometryReader { proxy in
            let keyGap = max(3, proxy.size.width * 0.012)
            let keyHeight = max(16, proxy.size.height * (compact ? 0.22 : 0.24))

            VStack(spacing: keyGap) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    HStack(spacing: keyGap) {
                        ForEach(Array(row.enumerated()), id: \.offset) { keyIndex, key in
                            keyCap(
                                key,
                                active: activeKey(row: rowIndex, index: keyIndex),
                                height: keyHeight
                            )
                        }
                    }
                    .padding(.horizontal, rowInset(rowIndex, width: proxy.size.width))
                }
                HStack(spacing: keyGap) {
                    keyCap("123", active: typedCount.isMultiple(of: 11) && typedCount > 0, height: keyHeight, width: proxy.size.width * 0.16)
                    keyCap("space", active: typedCount.isMultiple(of: 7) && typedCount > 0, height: keyHeight, width: proxy.size.width * 0.44)
                    keyCap("go", active: typedCount.isMultiple(of: 5) && typedCount > 0, height: keyHeight, width: proxy.size.width * 0.16)
                }
                .padding(.horizontal, proxy.size.width * 0.12)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(NotebookTheme.paper.opacity(0.3))
                    }
                    .overlay(alignment: glow ? .bottomTrailing : .topLeading) {
                        Circle()
                            .fill(.white.opacity(0.28))
                            .frame(width: 86, height: 86)
                            .blur(radius: 20)
                            .offset(x: glow ? 24 : -18, y: glow ? 16 : -16)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.58), lineWidth: 0.8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .opacity(0.86)
        .scaleEffect(typedCount > 0 ? 1 : 0.985)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: typedCount)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                glow = true
            }
        }
    }

    private func keyCap(_ title: String, active: Bool, height: CGFloat, width: CGFloat? = nil) -> some View {
        Text(title)
            .font(.system(size: title.count > 1 ? 9.5 : 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(active ? .white : NotebookTheme.ink.opacity(0.72))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .frame(width: width, height: height)
            .background(active ? NotebookTheme.ink.opacity(0.82) : .white.opacity(0.54), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(active ? 0.3 : 0.54), lineWidth: 0.7)
            }
            .scaleEffect(active ? 1.08 : 1)
            .shadow(color: .black.opacity(active ? 0.09 : 0.035), radius: active ? 5 : 2, y: active ? 3 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: active)
    }

    private func rowInset(_ row: Int, width: CGFloat) -> CGFloat {
        switch row {
        case 1: width * 0.045
        case 2: width * 0.12
        default: 0
        }
    }

    private func activeKey(row: Int, index: Int) -> Bool {
        guard typedCount > 0 else { return false }
        let allKeysBeforeRow = rows.prefix(row).reduce(0) { $0 + $1.count }
        let keyIndex = allKeysBeforeRow + index
        return keyIndex == typedCount % rows.flatMap { $0 }.count
    }
}

private struct AuthPaperInterior: View {
    var openProgress: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if openProgress > 0.01 {
                    ForEach(0..<3, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color(red: 0.72, green: 0.74, blue: 0.78).opacity(0.2 - Double(index) * 0.04))
                            .offset(x: CGFloat(index) * 3, y: CGFloat(index + 1) * 4)
                    }

                    authPage()
                        .padding(.horizontal, 2)
                }
            }
        }
    }

    private func authPage() -> some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
        .fill(
            LinearGradient(
                colors: [
                    Color(red: 0.965, green: 0.968, blue: 0.982),
                    Color(red: 0.938, green: 0.948, blue: 0.968),
                    Color(red: 0.91, green: 0.92, blue: 0.945)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(AuthPageRules())
        .overlay(PaperGrain(density: 120).opacity(0.15))
        .overlay(alignment: .leading) {
            LinearGradient(
                colors: [.black.opacity(0.1), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 28)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
            .stroke(.white.opacity(0.68), lineWidth: 0.85)
        }
    }
}

private struct AuthPageRules: View {
    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let margin = size.width * 0.16
            var red = Path()
            red.move(to: CGPoint(x: margin, y: 0))
            red.addLine(to: CGPoint(x: margin, y: size.height))
            context.stroke(red, with: .color(NotebookTheme.redRule.opacity(0.26)), lineWidth: 0.7)

            var y: CGFloat = 48
            while y < size.height - 18 {
                var rule = Path()
                rule.move(to: CGPoint(x: 0, y: y))
                rule.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(rule, with: .color(NotebookTheme.blueLine.opacity(0.36)), lineWidth: 0.58)
                y += 17
            }
        }
    }
}

private struct GoogleLogo: View {
    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let lineWidth = min(size.width, size.height) * 0.18
            let inset = lineWidth / 2
            let rect = CGRect(x: inset, y: inset, width: size.width - lineWidth, height: size.height - lineWidth)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(rect.width, rect.height) / 2

            func arc(_ start: Angle, _ end: Angle, _ color: Color) {
                var path = Path()
                path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }

            arc(.degrees(-38), .degrees(36), Color(red: 0.26, green: 0.52, blue: 0.96))
            arc(.degrees(36), .degrees(142), Color(red: 0.20, green: 0.65, blue: 0.32))
            arc(.degrees(142), .degrees(214), Color(red: 0.98, green: 0.75, blue: 0.18))
            arc(.degrees(214), .degrees(322), Color(red: 0.92, green: 0.25, blue: 0.21))

            var crossbar = Path()
            crossbar.move(to: CGPoint(x: center.x + radius * 0.08, y: center.y))
            crossbar.addLine(to: CGPoint(x: center.x + radius * 0.86, y: center.y))
            context.stroke(crossbar, with: .color(Color(red: 0.26, green: 0.52, blue: 0.96)), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            var notch = Path()
            notch.move(to: CGPoint(x: center.x + radius * 0.48, y: center.y + lineWidth * 0.48))
            notch.addLine(to: CGPoint(x: center.x + radius * 0.82, y: center.y + lineWidth * 0.48))
            context.stroke(notch, with: .color(Color(red: 0.26, green: 0.52, blue: 0.96)), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}

private struct AmbientNotebookBackground: View {
    var animated: Bool

    var body: some View {
        LivingPaperBackground(animated: animated, grainDensity: 90)
    }
}
