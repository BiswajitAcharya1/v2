import SwiftUI

struct AccountCenterView: View {
    @Environment(NotebookStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var legalDocument: LegalDocument?
    @State private var editingAvatar = false
    @State private var expanded = false
    @State private var heroPulse = false
    @State private var closeRotation = 0.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    accountHero
                    .scaleEffect(expanded ? 1 : 0.96)
                    .opacity(expanded ? 1 : 0)

                    accountSection("notebooks") {
                        accountRow(systemName: "books.vertical.fill", title: "\(store.notebooks.count) journals", detail: "\(store.notebooks.reduce(0) { $0 + $1.pages.count }) pages")
                        accountRow(systemName: "mic.fill", title: "personal voice", detail: voiceStatus)
                    }

                    accountSection("study") {
                        accountRow(systemName: "rectangle.stack.fill", title: "\(flashcardCount) flashcards", detail: "ready from scanned pages")
                        accountRow(systemName: "cube.transparent", title: "\(modelCount) models", detail: "interactive diagrams found")
                        accountRow(systemName: "text.magnifyingglass", title: "\(keywordCount) keywords", detail: "searchable across journals")
                    }

                    accountSection("insights") {
                        accountRow(systemName: "flame.fill", title: "\(studyStreak) day streak", detail: "from saved pages")
                        accountRow(systemName: "checkmark.seal.fill", title: "\(reviewCount) reviews", detail: "graded flashcards")
                        accountRow(systemName: "sparkles", title: strongestSubject, detail: "strongest journal")
                    }

                    accountSection("security") {
                        accountRow(systemName: "key.fill", title: authProviderTitle, detail: authSecurityDetail)
                        accountRow(systemName: "faceid", title: "face id reset", detail: faceIDDetail)
                        accountRow(systemName: "icloud.fill", title: "synced keychain", detail: "credentials use secure keychain sync")
                    }

                    accountSection("preferences") {
                        Toggle(
                            "personal voice",
                            isOn: Binding(
                                get: { store.voiceProfile.wantsPersonalVoice },
                                set: { value in
                                    Haptics.selection()
                                    store.setPersonalVoiceEnabled(value)
                                }
                            )
                        )
                            .tint(NotebookTheme.ink)
                        Button {
                            Haptics.open()
                            editingAvatar = true
                        } label: {
                            accountRow(systemName: "person.crop.circle.fill", title: "profile picture", detail: "build your own avatar")
                        }
                        .buttonStyle(.plain)
                    }

                    accountSection("legal") {
                        legalButton(.terms)
                        legalButton(.privacy)
                    }

                    Button {
                        Haptics.warning()
                        dismiss()
                        store.signOut()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 16, weight: .bold))
                            Text("sign out")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(NotebookTheme.ink, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .background(LivingPaperBackground().ignoresSafeArea())
            .navigationTitle("account")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        closeAccount()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(NotebookTheme.ink)
                            .frame(width: 38, height: 38)
                            .background(.ultraThinMaterial, in: Circle())
                            .rotationEffect(.degrees(closeRotation))
                    }
                    .buttonStyle(.plain)
                }
            }
            .sheet(item: $legalDocument) { document in
                LegalDocumentView(document: document)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $editingAvatar) {
                AvatarBuilderView()
                    .presentationDetents([.height(560), .large])
                    .presentationDragIndicator(.visible)
            }
            .onAppear {
                withAnimation(.spring(response: 0.58, dampingFraction: 0.84)) {
                    expanded = true
                }
                withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                    heroPulse = true
                }
            }
        }
    }

    private var accountHero: some View {
        GlassSurface(radius: 34, padding: 18, interactive: true) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(NotebookTheme.accent(store.user.avatar.base).opacity(0.14))
                        .frame(width: 148, height: 148)
                        .blur(radius: 18)
                        .scaleEffect(heroPulse ? 1.08 : 0.94)

                    ForEach(0..<2, id: \.self) { index in
                        Circle()
                            .trim(from: 0.08, to: 0.34)
                            .stroke(
                                NotebookTheme.accent(index == 0 ? store.user.avatar.base : store.user.avatar.accent).opacity(0.34),
                                style: StrokeStyle(lineWidth: 2, lineCap: .round)
                            )
                            .frame(width: 112 + CGFloat(index * 24), height: 112 + CGFloat(index * 24))
                            .rotationEffect(.degrees(heroPulse ? Double(84 + index * 72) : Double(-24 - index * 54)))
                    }

                    Button {
                        Haptics.open()
                        editingAvatar = true
                    } label: {
                        ProfileAvatarView(avatar: store.user.avatar, size: 92, animated: true)
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(NotebookTheme.ink, in: Circle())
                                    .overlay {
                                        Circle().stroke(.white.opacity(0.64), lineWidth: 0.8)
                                    }
                            }
                    }
                    .buttonStyle(.plain)
                    .rotation3DEffect(.degrees(heroPulse ? 5 : -5), axis: (x: 0.2, y: 1, z: 0), perspective: 0.78)
                }

                VStack(spacing: 4) {
                    Text(store.user.name.lowercased())
                        .font(.system(.title2, design: .serif, weight: .semibold))
                        .foregroundStyle(NotebookTheme.ink)
                    Text(accountSubtitle)
                        .font(.system(.footnote, design: .rounded, weight: .medium))
                        .foregroundStyle(NotebookTheme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                HStack(spacing: 10) {
                    AccountQuickAction(symbol: "person.crop.circle.fill", title: "avatar", active: true) {
                        Haptics.open()
                        editingAvatar = true
                    }
                    AccountQuickAction(symbol: "waveform", title: "voice", active: store.voiceProfile.wantsPersonalVoice) {
                        Haptics.selection()
                        store.setPersonalVoiceEnabled(!store.voiceProfile.wantsPersonalVoice)
                    }
                    AccountQuickAction(symbol: "hand.raised.fill", title: "privacy", active: false) {
                        Haptics.open()
                        legalDocument = .privacy
                    }
                }

                AccountTrustRibbon(
                    provider: authProviderTitle,
                    faceID: faceIDDetail,
                    voice: voiceStatus,
                    awake: heroPulse
                )
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func closeAccount() {
        Haptics.softTap()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
            closeRotation += 90
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            dismiss()
        }
    }

    private var accountSubtitle: String {
        if let email = store.authSession?.email, !email.isEmpty {
            return email.lowercased()
        }
        return "\(store.notebooks.count) journals  \(store.notebooks.reduce(0) { $0 + $1.pages.count }) pages"
    }

    private func accountSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        GlassSurface(radius: 24, padding: 16, interactive: true) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)
                content()
                    .font(.system(.body, design: .rounded))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(expanded ? 1 : 0)
        .offset(y: expanded ? 0 : 12)
    }

    private func accountRow(systemName: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(NotebookTheme.ink, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)
                Text(detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(NotebookTheme.muted)
            }
            Spacer()
        }
    }

    private func legalButton(_ document: LegalDocument) -> some View {
        Button {
            Haptics.open()
            legalDocument = document
        } label: {
            accountRow(
                systemName: document == .terms ? "doc.text.fill" : "hand.raised.fill",
                title: document.title,
                detail: document.summary
            )
        }
        .buttonStyle(.plain)
    }

    private var flashcardCount: Int {
        store.notebooks.flatMap(\.pages).reduce(0) { count, page in
            count + max(1, page.content.sections.count)
        }
    }

    private var modelCount: Int {
        store.notebooks.flatMap(\.pages).reduce(0) { $0 + $1.content.models.count }
    }

    private var keywordCount: Int {
        Set(store.notebooks.flatMap(\.pages).flatMap(\.content.keywords)).count
    }

    private var reviewCount: Int {
        store.notebooks.flatMap(\.pages).reduce(0) { $0 + $1.studyState.reviewCount }
    }

    private var strongestSubject: String {
        guard !store.notebooks.isEmpty else { return "add course" }
        guard store.notebooks.contains(where: { !$0.pages.isEmpty }) else { return "scan first" }
        return store.notebooks.max { first, second in
            first.progress < second.progress
        }?.subject ?? "scan first"
    }

    private var voiceStatus: String {
        if store.voiceProfile.isPersonalized { return "ready" }
        return store.voiceProfile.wantsPersonalVoice ? "enabled" : "optional"
    }

    private var authProviderTitle: String {
        guard let provider = store.authSession?.provider else { return "email access" }
        return "\(provider.rawValue) access"
    }

    private var authSecurityDetail: String {
        guard let email = store.authSession?.email, !email.isEmpty else {
            return "local session protected"
        }
        return email.lowercased()
    }

    private var faceIDDetail: String {
        guard let email = store.authSession?.email, !email.isEmpty else {
            return "available after email sign up"
        }
        return CredentialVault.accountExists(email: email) ? "linked to this account" : "available after email sign up"
    }

    private var studyStreak: Int {
        let calendar = Calendar.current
        let days = Set(store.notebooks.flatMap(\.pages).map { calendar.startOfDay(for: $0.createdAt) })
        guard !days.isEmpty else { return 0 }
        var streak = 0
        var day = calendar.startOfDay(for: .now)
        while days.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }
}

private extension String {
    var readableSymbolName: String {
        replacingOccurrences(of: ".fill", with: "")
            .replacingOccurrences(of: ".", with: " ")
            .lowercased()
    }
}

private struct AccountQuickAction: View {
    let symbol: String
    let title: String
    var active: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 42, height: 42)
                    .foregroundStyle(active ? .white : NotebookTheme.ink)
                    .background(active ? NotebookTheme.ink : .white.opacity(0.58), in: Circle())
                    .overlay {
                        Circle().stroke(.white.opacity(active ? 0.22 : 0.66), lineWidth: 0.8)
                    }
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(NotebookTheme.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(.white.opacity(0.34), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct AccountTrustRibbon: View {
    var provider: String
    var faceID: String
    var voice: String
    var awake: Bool

    var body: some View {
        HStack(spacing: 8) {
            trustChip(symbol: "key.fill", title: provider)
            trustChip(symbol: "faceid", title: faceID)
            trustChip(symbol: "waveform", title: "voice \(voice)")
        }
        .padding(7)
        .background(.white.opacity(0.34), in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(awake ? 0.72 : 0.46), lineWidth: 0.8)
        }
        .scaleEffect(awake ? 1 : 0.985)
        .animation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true), value: awake)
    }

    private func trustChip(symbol: String, title: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
            Text(shortTitle(title))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .foregroundStyle(NotebookTheme.ink.opacity(0.72))
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .background(.white.opacity(0.48), in: Capsule())
    }

    private func shortTitle(_ title: String) -> String {
        if title.contains("@") { return "email" }
        if title.contains("linked") { return "face id" }
        if title.contains("available") { return "face id" }
        if title.contains("local") { return "local" }
        return title
    }
}

private struct AvatarBuilderView: View {
    @Environment(NotebookStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft = AvatarProfile.default
    @State private var previewPulse = false
    @State private var previewTilt = false

    private let symbols = [
        "book.closed.fill", "pencil.and.scribble", "sparkles", "brain.head.profile", "cube.transparent", "graduationcap.fill",
        "atom", "function", "paintpalette.fill", "lightbulb.fill", "waveform.path.ecg", "scope", "scribble.variable", "camera.macro", "sum"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                LivingPaperBackground().ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        avatarStudio
                            .padding(.top, 8)

                        avatarSection("color") {
                            HStack(spacing: 12) {
                                ForEach(ColorToken.allCases, id: \.self) { token in
                                    avatarColorButton(token, selected: draft.base == token) {
                                        draft.base = token
                                    }
                                }
                            }
                        }

                        avatarSection("highlight") {
                            HStack(spacing: 12) {
                                ForEach(ColorToken.allCases, id: \.self) { token in
                                    avatarColorButton(token, selected: draft.accent == token) {
                                        draft.accent = token
                                    }
                                }
                            }
                        }

                        avatarSection("mark") {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                                ForEach(symbols, id: \.self) { symbol in
                                    avatarChoiceButton(active: draft.symbol == symbol) {
                                        draft.symbol = symbol
                                    } label: {
                                        Image(systemName: symbol)
                                            .font(.system(size: 19, weight: .semibold))
                                    }
                                }
                            }
                        }

                        avatarSection("texture") {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                                ForEach(AvatarDetail.allCases) { detail in
                                    avatarChoiceButton(active: draft.detail == detail) {
                                        draft.detail = detail
                                    } label: {
                                        Text(detail.rawValue)
                                            .font(.system(.caption, design: .rounded, weight: .semibold))
                                    }
                                }
                            }
                        }

                        HStack(spacing: 12) {
                            Button {
                                Haptics.selection()
                                store.randomizeAvatar()
                                draft = store.user.avatar
                            } label: {
                                Image(systemName: "shuffle")
                                    .font(.system(size: 16, weight: .bold))
                                    .frame(width: 52, height: 52)
                            }
                            .buttonStyle(FloatingCircleButtonStyle(tint: .white.opacity(0.72), foreground: NotebookTheme.ink))

                            Button {
                                Haptics.success()
                                store.updateAvatar(draft)
                                dismiss()
                            } label: {
                                Text("save avatar")
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(NotebookTheme.ink, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("avatar")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.softTap()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(NotebookTheme.ink)
                            .frame(width: 38, height: 38)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .onAppear {
                draft = store.user.avatar
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                    previewPulse = true
                }
                withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                    previewTilt = true
                }
            }
        }
    }

    private var avatarStudio: some View {
        GlassSurface(radius: 34, padding: 18, interactive: true) {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(NotebookTheme.accent(draft.base).opacity(0.16))
                        .frame(width: 196, height: 196)
                        .blur(radius: 24)
                        .scaleEffect(previewPulse ? 1.08 : 0.94)

                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .trim(from: 0.08, to: 0.26)
                            .stroke(NotebookTheme.accent(index.isMultiple(of: 2) ? draft.accent : draft.base).opacity(0.34), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .frame(width: 164 + CGFloat(index * 18), height: 164 + CGFloat(index * 18))
                            .rotationEffect(.degrees(previewTilt ? Double(80 + index * 40) : Double(-18 - index * 28)))
                    }

                    ProfileAvatarView(avatar: draft, size: 132, animated: true)
                        .scaleEffect(previewPulse ? 1.02 : 0.98)
                        .rotation3DEffect(.degrees(previewTilt ? 7 : -7), axis: (x: 0.2, y: 1, z: 0), perspective: 0.72)
                }

                HStack(spacing: 10) {
                    ProfileAvatarView(avatar: draft, size: 34, animated: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.user.name.lowercased())
                            .font(.system(.callout, design: .serif, weight: .semibold))
                            .foregroundStyle(NotebookTheme.ink)
                        Text("\(draft.detail.rawValue) \(draft.symbol.readableSymbolName)")
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(NotebookTheme.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.white.opacity(0.52), in: Capsule())
            }
        }
    }

    private func avatarSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        GlassSurface(radius: 24, padding: 16, interactive: true) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(NotebookTheme.ink)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func avatarColorButton(_ token: ColorToken, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                action()
            }
        } label: {
            Circle()
                .fill(NotebookTheme.accent(token))
                .frame(width: selected ? 42 : 34, height: selected ? 42 : 34)
                .overlay {
                    Circle()
                        .stroke(selected ? NotebookTheme.ink.opacity(0.8) : .white.opacity(0.74), lineWidth: selected ? 2 : 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func avatarChoiceButton<Content: View>(active: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> Content) -> some View {
        Button {
            Haptics.selection()
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                action()
            }
        } label: {
            label()
                .foregroundStyle(active ? .white : NotebookTheme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(active ? NotebookTheme.ink : .white.opacity(0.58), in: Capsule())
                .overlay {
                    Capsule().stroke(.white.opacity(active ? 0.18 : 0.62), lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
    }
}
