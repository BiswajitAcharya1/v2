import SwiftUI

struct AuthView: View {
    @Environment(NotebookStore.self) private var store
    @State private var appeared = false
    @State private var showingEmail = false
    @State private var isSignIn = false
    @State private var username = "maya"
    @State private var email = "student@email.com"
    @State private var password = "notebook"
    @State private var confirmPassword = "notebook"
    @State private var closeRotation = 0.0
    @State private var leatherDrift = false

    var body: some View {
        ZStack {
            AmbientNotebookBackground().ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer(minLength: 18)

                heroStack
                    .scaleEffect(appeared ? 1 : 0.92)
                    .opacity(appeared ? 1 : 0)

                authPanel
                    .padding(.horizontal, 22)
                    .offset(y: appeared ? 0 : 28)
                    .opacity(appeared ? 1 : 0)

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
        ZStack {
            NotebookLogo()
                .frame(width: 172, height: 226)
                .rotation3DEffect(.degrees(leatherDrift ? 4 : -4), axis: (x: 0.2, y: 1, z: 0), perspective: 0.65)
                .shadow(color: .black.opacity(0.2), radius: 18, y: 14)
        }
        .frame(height: 252)
    }

    private var authPanel: some View {
        GlassSurface(radius: 34, padding: 16, interactive: true) {
            VStack(spacing: 18) {
                HStack(spacing: 18) {
                    ForEach(AuthProvider.allCases) { provider in
                        AuthProviderCircle(provider: provider) {
                            if provider == .email {
                                isSignIn = false
                                showingEmail = true
                            } else {
                                Task { await store.signIn(provider: provider) }
                            }
                        }
                    }
                }

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
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.62), in: Capsule())
                }
                .buttonStyle(.plain)
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
                        Text(isSignIn ? "welcome back." : "create your study identity.")
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
                        AuthField(systemName: "person.fill", text: $username, prompt: "username")
                        AuthField(systemName: "envelope.fill", text: $email, prompt: "gmail")
                    } else {
                        AuthField(systemName: "envelope.fill", text: $email, prompt: "email")
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

    private var passwordMeter: some View {
        let strength = passwordStrength(password)
        return VStack(alignment: .leading, spacing: 7) {
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
            Text("\(strength.rawValue) password")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(strength.color)
        }
    }

    private func width(for strength: PasswordStrength) -> CGFloat {
        switch strength {
        case .weak: 0.32
        case .medium: 0.66
        case .good: 1
        }
    }

    private func secureField(_ title: String, text: Binding<String>) -> some View {
        SecureField(title, text: text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.system(.body, design: .rounded))
            .padding(14)
            .background(.white.opacity(0.68), in: Capsule())
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

private struct AuthProviderCircle: View {
    let provider: AuthProvider
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: provider.symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 64, height: 64)
                    .background(.white.opacity(0.72), in: Circle())
                    .overlay {
                        Circle().stroke(.white.opacity(0.7), lineWidth: 1)
                    }
                Text(provider.rawValue)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(NotebookTheme.muted)
            }
            .foregroundStyle(NotebookTheme.ink)
        }
        .buttonStyle(.plain)
    }
}

private struct AuthField: View {
    var systemName: String
    @Binding var text: String
    var prompt: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemName)
                .foregroundStyle(NotebookTheme.muted)
            TextField(prompt, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .font(.system(.body, design: .rounded))
        .padding(14)
        .background(.white.opacity(0.68), in: Capsule())
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
