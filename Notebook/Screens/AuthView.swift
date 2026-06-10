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

    var body: some View {
        ZStack {
            AmbientNotebookBackground().ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer(minLength: 0)

                heroStack
                    .scaleEffect(appeared ? 1 : 0.92)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: notebookOpen ? -20 : 0)

                if notebookOpen {
                    authPanel
                        .padding(.horizontal, 22)
                        .offset(y: appeared ? -16 : 18)
                        .opacity(appeared ? 1 : 0)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Spacer(minLength: 18)
            }
            .padding(.bottom, 18)

            if showingEmail {
                emailSheet
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.92).combined(with: .opacity),
                        removal: .scale(scale: 0.96).combined(with: .opacity)
                    ))
            }

            if notebookOpen {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        StudyAgentBubble(mode: .auth)
                            .padding(.trailing, 18)
                            .padding(.bottom, 22)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
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
    }

    private var heroStack: some View {
        VStack(spacing: 14) {
            if notebookOpen {
                VStack(spacing: 8) {
                    BrandSignUpTitle()
                    ContainerTextFlip(words: ["scan", "organize", "study", "remember"])
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            ZStack {
                Button {
                    withAnimation(.spring(response: 0.78, dampingFraction: 0.76)) {
                        notebookOpen = true
                    }
                } label: {
                    NotebookLogo(isOpen: notebookOpen)
                        .frame(width: 174, height: 226)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("open sign up notebook")
                .accessibilityHint("reveals sign up options")
                .scaleEffect(notebookOpen ? 0.96 : 1)
                .offset(y: notebookOpen ? 6 : 0)
                .animation(.spring(response: 0.58, dampingFraction: 0.8), value: notebookOpen)
                    .rotation3DEffect(.degrees(leatherDrift ? 4 : -4), axis: (x: 0.2, y: 1, z: 0), perspective: 0.65)
                    .shadow(color: .black.opacity(0.2), radius: 18, y: 14)

                if notebookOpen {
                    orbitingAuthButtons
                        .transition(.scale(scale: 0.74).combined(with: .opacity))
                }
            }
            .frame(width: 330, height: 248)
        }
        .frame(height: 320)
    }

    private var authPanel: some View {
        Button {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
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
    }

    private var orbitingAuthButtons: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate * 0.42
            ForEach(Array(AuthProvider.allCases.enumerated()), id: \.element.id) { index, provider in
                AuthProviderCircle(provider: provider) {
                    if provider == .email {
                        isSignIn = false
                        showingEmail = true
                    } else {
                        Task { await store.signIn(provider: provider) }
                    }
                }
                .offset(orbitOffset(index: index, phase: phase))
                .zIndex(sin(phase + Double(index) * 2.094) > 0 ? 2 : 0)
                .scaleEffect(sin(phase + Double(index) * 2.094) > 0 ? 1.04 : 0.92)
            }
        }
    }

    private func orbitOffset(index: Int, phase: Double) -> CGSize {
        let angle = phase + Double(index) * 2.094
        return CGSize(width: cos(angle) * 142, height: sin(angle) * 78)
    }

    private struct BrandSignUpTitle: View {
        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("sign")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                FontFlipText("up")
            }
            .foregroundStyle(NotebookTheme.ink)
        }
    }

    private struct FontFlipText: View {
        let text: String
        @State private var index = 0
        private let designs: [Font.Design] = [.serif, .rounded, .monospaced, .default]

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
            .frame(width: 48, height: 46, alignment: .leading)
            .clipped()
            .animation(.spring(response: 0.42, dampingFraction: 0.76), value: index)
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(820))
                    index = (index + 1) % designs.count
                }
            }
        }

        @ViewBuilder
        private func fontText(for designIndex: Int) -> some View {
            let base = Text(text)
                .font(.system(size: 38, weight: .semibold, design: designs[designIndex]))
                .baselineOffset(designIndex == 2 ? -1 : 0)

            if designIndex.isMultiple(of: 2) {
                base.italic()
            } else {
                base
            }
        }
    }

    private struct AuthProviderCircle: View {
        let provider: AuthProvider
        var action: () -> Void

        var body: some View {
            Button(action: action) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Circle().stroke(.white.opacity(0.74), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.12), radius: 12, y: 8)
                    providerMark
                }
                .frame(width: 64, height: 64)
                .contentShape(Circle())
                .accessibilityLabel(provider.title)
            }
            .buttonStyle(.plain)
        }

        @ViewBuilder
        private var providerMark: some View {
            switch provider {
            case .apple:
                Image(systemName: "apple.logo")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)
            case .google:
                GoogleLogo()
                    .frame(width: 28, height: 28)
            case .email:
                Image(systemName: "envelope.fill")
                    .font(.system(size: 23, weight: .semibold))
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
            .font(.system(.body, design: .rounded))
            .padding(14)
            .background(.white.opacity(0.68), in: Capsule())
        }
    }

    private func closeEmail() {
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
            .font(.system(.body, design: .rounded))
            .padding(14)
            .background(.white.opacity(0.68), in: Capsule())
        }
    }
}

private struct GoogleLogo: View {
    var body: some View {
        Canvas { context, size in
            let lineWidth = min(size.width, size.height) * 0.16
            let inset = lineWidth / 2
            let rect = CGRect(x: inset, y: inset, width: size.width - lineWidth, height: size.height - lineWidth)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = rect.width / 2

            func arc(_ start: Angle, _ end: Angle, _ color: Color) {
                var path = Path()
                path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }

            arc(.degrees(-38), .degrees(42), Color(red: 0.26, green: 0.52, blue: 0.96))
            arc(.degrees(42), .degrees(142), Color(red: 0.20, green: 0.65, blue: 0.32))
            arc(.degrees(142), .degrees(214), Color(red: 0.98, green: 0.75, blue: 0.18))
            arc(.degrees(214), .degrees(322), Color(red: 0.92, green: 0.25, blue: 0.21))

            var crossbar = Path()
            crossbar.move(to: CGPoint(x: center.x, y: center.y))
            crossbar.addLine(to: CGPoint(x: size.width * 0.88, y: center.y))
            context.stroke(crossbar, with: .color(Color(red: 0.26, green: 0.52, blue: 0.96)), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}

private struct AmbientNotebookBackground: View {
    var body: some View {
        LinearGradient(
            colors: [NotebookTheme.field, Color(red: 0.91, green: 0.89, blue: 0.83)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
