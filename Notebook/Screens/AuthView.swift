import SwiftUI
import UIKit

struct AuthView: View {
    @Environment(NotebookStore.self) private var store
    @State private var appeared = false
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

    var body: some View {
        ZStack {
            AmbientNotebookBackground().ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer(minLength: 0)

                heroStack
                    .scaleEffect(appeared ? 1 : 0.92)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: notebookOpen ? -42 : 0)

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
                        insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.9)),
                        removal: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.96))
                    ))
            }

        }
        .onAppear {
            withAnimation(.spring(response: 0.85, dampingFraction: 0.82).delay(0.08)) {
                appeared = true
            }
            withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
                leatherDrift = true
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
                    ContainerTextFlip(words: ["scan", "organize", "study", "remember"])
                }
                .opacity(Double(min(1, openProgress * 1.35)))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            draggableAuthBook
                .frame(width: 350, height: 330)
            if notebookOpen, let message = store.authMessage, !showingEmail {
                Text(message)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(NotebookTheme.muted)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(height: notebookOpen ? 420 : 330)
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
                        VStack(spacing: 12) {
                            ForEach(Array(AuthProvider.allCases.enumerated()), id: \.element.id) { index, provider in
                                AuthProviderPageButton(provider: provider) {
                                    if provider == .email {
                                        Haptics.open()
                                        withAnimation(.spring(response: 0.92, dampingFraction: 0.82)) {
                                            isSignIn = false
                                            showingEmail = true
                                        }
                                    } else {
                                        Task { await store.signIn(provider: provider) }
                                    }
                                }
                                .offset(x: openProgress >= 1 ? 0 : 16, y: openProgress >= 1 ? 0 : 10)
                                .animation(.spring(response: 0.62, dampingFraction: 0.82).delay(Double(index) * 0.05), value: notebookOpen)
                            }
                        }
                        .padding(.leading, 62)
                        .padding(.trailing, 18)
                        .opacity(Double((openProgress - 0.54) / 0.46))
                        .scaleEffect(0.86 + openProgress * 0.14)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                .frame(width: 224 + openProgress * 136, height: 282 + openProgress * 92)
                .offset(x: openProgress * 68, y: openProgress * 10)
                .shadow(color: .black.opacity(0.12), radius: 14, y: 9)

            NotebookLogo(isOpen: false)
                .frame(width: 190, height: 248)
                .rotation3DEffect(.degrees(-118 * openProgress + (leatherDrift ? 3 : -3)), axis: (x: 0.02, y: 1, z: 0), anchor: .leading, perspective: 0.68)
                .offset(x: -82 * openProgress, y: 2 * openProgress)
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
                            withAnimation(.spring(response: 0.78, dampingFraction: 0.76)) {
                                notebookOpen = shouldOpen
                                coverDrag = 0
                            }
                        }
                )
                .accessibilityLabel("drag notebook cover")
                .accessibilityHint("drag left to open sign up")
        }
        .scaleEffect(notebookOpen ? 1.04 : 1)
        .animation(.spring(response: 0.56, dampingFraction: 0.82), value: notebookOpen)
        .animation(.spring(response: 0.28, dampingFraction: 0.74), value: coverDrag)
    }

    private var authPanel: some View {
        VStack(spacing: 12) {
            Button {
                Haptics.press()
                withAnimation(.spring(response: 0.92, dampingFraction: 0.82)) {
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
        private let designs: [Font.Design] = [.serif, .rounded, .monospaced, .default, .serif, .rounded, .default, .monospaced, .serif]
        private let weights: [Font.Weight] = [.semibold, .regular, .bold, .medium, .light, .semibold, .thin, .bold, .regular]

        init(_ text: String) {
            self.text = text
        }

        var body: some View {
            ZStack(alignment: .leading) {
                ForEach(designs.indices, id: \.self) { designIndex in
                    fontText(for: designIndex)
                        .opacity(index == designIndex ? 1 : 0)
                        .scaleEffect(index == designIndex ? 1 : 0.94)
                        .blur(radius: index == designIndex ? 0 : 3)
                }
            }
            .frame(width: 62, height: 52, alignment: .leading)
            .clipped()
            .animation(.spring(response: 0.42, dampingFraction: 0.76), value: index)
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(620))
                    index = (index + 1) % designs.count
                }
            }
        }

        @ViewBuilder
        private func fontText(for designIndex: Int) -> some View {
            let base = Text(text)
                .font(.system(size: 43, weight: weights[designIndex], design: designs[designIndex]))
                .baselineOffset(designIndex == 2 ? -1 : 0)

            if designIndex.isMultiple(of: 2) {
                base.italic()
            } else {
                base
            }
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
                withAnimation(.easeInOut(duration: 3.8).repeatForever(autoreverses: false)) {
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
                        Text(isSignIn ? "welcome back." : "continue with email.")
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(NotebookTheme.muted)
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
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(NotebookTheme.muted)
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(NotebookTheme.muted)
                SecureField("", text: text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.password)
                    .foregroundStyle(NotebookTheme.ink)
                    .tint(NotebookTheme.ink)
            }
            .font(.system(.body, design: typingDesign(for: text.wrappedValue), weight: .regular))
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: text.wrappedValue.count)
            .padding(14)
            .background(.white.opacity(0.68), in: Capsule())
        }
    }

    private func typingDesign(for text: String) -> Font.Design {
        let designs: [Font.Design] = [.rounded, .serif, .monospaced, .default]
        return designs[max(0, text.count) % designs.count]
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
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(NotebookTheme.muted)
            HStack(spacing: 10) {
                Image(systemName: systemName)
                    .foregroundStyle(NotebookTheme.muted)
                TextField("", text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(keyboardType)
                    .foregroundStyle(NotebookTheme.ink)
                    .tint(NotebookTheme.ink)
            }
            .font(.system(.body, design: typingDesign, weight: .regular))
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: text.count)
            .padding(14)
            .background(.white.opacity(0.68), in: Capsule())
        }
    }

    private var typingDesign: Font.Design {
        let designs: [Font.Design] = [.rounded, .serif, .monospaced, .default]
        return designs[max(0, text.count) % designs.count]
    }
}

private struct AuthPaperInterior: View {
    var openProgress: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(NotebookTheme.paper)
            .overlay {
                PaperGrain(density: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .opacity(0.42)
            }
            .overlay(alignment: .leading) {
                LinearGradient(
                    colors: [.black.opacity(0.16), .clear, .white.opacity(0.16)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 42)
                .opacity(Double(openProgress))
            }
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(.black.opacity(0.14))
                    .frame(width: 2)
                    .padding(.vertical, 24)
                    .offset(x: 44)
                    .blur(radius: 0.4)
                    .opacity(Double(openProgress))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.78), .black.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.9
                    )
            }
    }
}

private struct GoogleLogo: View {
    var body: some View {
        Canvas { context, size in
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
    var body: some View {
        LivingPaperBackground()
    }
}
