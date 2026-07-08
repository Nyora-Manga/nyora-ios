//
//  NyoraStartView.swift
//  Aidoku (iOS) — Nyora fork
//
//  First-launch onboarding (NX-008): a branded start page offering Sign in,
//  Create account (both against the Nyora sync server via NyoraSyncClient), and
//  Continue as guest (proceeds locally). Shown once — the caller persists the
//  "Nyora.completedStart" flag and dismisses when `onFinish` fires.
//
//  Visual design (NX-redesign): monochrome, editorial "Awwwards" aesthetic —
//  black/white/gray only, high contrast, generous negative space, a bold Poppins
//  wordmark against lighter body copy, crisp hairline dividers, and a restrained
//  entrance animation. Adapts to light/dark via semantic colors (label / paper).
//

import SwiftUI

// MARK: - Monochrome palette

/// The onboarding is deliberately colorless: `ink` is the foreground (black in
/// light, white in dark) and `paper` is the background (the inverse). All accents
/// are grays derived from `ink`.
private enum Mono {
    static let ink = Color(uiColor: .label)
    static let paper = Color(uiColor: .systemBackground)
    static let inkInverse = Color(uiColor: .systemBackground)
    static let subtle = Color(uiColor: .secondaryLabel)
    static let faint = Color(uiColor: .tertiaryLabel)
    static let hairline = Color(uiColor: .separator)
    static let field = Color(uiColor: .secondarySystemBackground)
}

struct NyoraStartView: View {
    /// UserDefaults flag the caller sets once the start flow completes.
    static let completedKey = "Nyora.completedStart"

    /// Called when the user has finished onboarding (signed in, registered, or
    /// chose to continue as a guest). The presenter persists the flag + dismisses.
    let onFinish: () -> Void

    private enum Mode: Equatable {
        case landing
        case signIn
        case signUp

        var isAuth: Bool { self != .landing }
    }

    @ObservedObject private var client = NyoraSyncClient.shared

    @State private var mode: Mode = .landing
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var appeared = false

    /// Layer 2 of onboarding: once the user is "in" (signed in / registered /
    /// guest) we swap the auth card for the Preferences step, which seeds sources
    /// and only then calls `onFinish`.
    @State private var showingPreferences = false

    @FocusState private var focusedField: Field?
    private enum Field { case email, password }

    var body: some View {
        Group {
            if showingPreferences {
                PreferencesOnboardingView(onFinish: onFinish)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                authBody
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: showingPreferences)
    }

    private var authBody: some View {
        ZStack {
            Mono.paper.ignoresSafeArea()
            backgroundWordmark

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 32)
                brand
                Spacer(minLength: 36)
                card
                Spacer(minLength: 32)
                legalFootnote
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 14)
        }
        .animation(.easeInOut(duration: 0.28), value: mode)
        .onAppear {
            guard !appeared else { return }
            withAnimation(.easeOut(duration: 0.55)) { appeared = true }
        }
    }

    // MARK: - Background

    /// A single oversized ghost "N" bleeding off the trailing edge — editorial
    /// negative-space flourish, barely-there so it never competes with the copy.
    private var backgroundWordmark: some View {
        Text("N")
            .font(.poppins(440, weight: .black))
            .foregroundStyle(Mono.ink.opacity(0.035))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .offset(x: 120, y: -60)
            .allowsHitTesting(false)
            .ignoresSafeArea()
    }

    // MARK: - Brand

    private var brand: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("MANGA · EVERYWHERE")
                .font(.poppins(12, weight: .semibold))
                .tracking(2.5)
                .foregroundStyle(Mono.subtle)

            Text("Nyora")
                .font(.poppins(64, weight: .black))
                .foregroundStyle(Mono.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Rectangle()
                .fill(Mono.ink)
                .frame(width: 48, height: 3)

            Text("Your library, in sync — read anywhere, pick up where you left off.")
                .font(.poppins(16, weight: .regular))
                .foregroundStyle(Mono.subtle)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Card

    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            if mode.isAuth {
                authForm
            } else {
                landingButtons
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.poppins(13, weight: .medium))
                    .foregroundStyle(Mono.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Mono.field)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Mono.hairline, lineWidth: 1)
                    )
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Landing

    private var landingButtons: some View {
        VStack(spacing: 12) {
            primaryButton(title: "Sign in") { switchTo(.signIn) }
            secondaryButton(title: "Create account") { switchTo(.signUp) }

            Button {
                continueAsGuest()
            } label: {
                Text("Continue as guest")
                    .font(.poppins(15, weight: .medium))
                    .foregroundStyle(Mono.subtle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .padding(.top, 2)
        }
    }

    // MARK: - Auth form

    private var authForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(mode == .signUp ? "Create account" : "Welcome back")
                .font(.poppins(26, weight: .bold))
                .foregroundStyle(Mono.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 4) {
                field(placeholder: "Email", text: $email, isSecure: false)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .focused($focusedField, equals: .email)

                field(placeholder: "Password", text: $password, isSecure: true)
                    .textContentType(mode == .signUp ? .newPassword : .password)
                    .focused($focusedField, equals: .password)
            }

            primaryButton(
                title: mode == .signUp ? "Create account" : "Sign in",
                busy: busy,
                disabled: email.isEmpty || password.isEmpty
            ) {
                Task { await authenticate(register: mode == .signUp) }
            }

            Button {
                switchTo(.landing)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Back")
                        .font(.poppins(15, weight: .medium))
                }
                .foregroundStyle(Mono.subtle)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .disabled(busy)
        }
    }

    // MARK: - Reusable controls

    /// Editorial underlined field — no filled box, just a baseline hairline that
    /// darkens on focus.
    private func field(
        placeholder: String,
        text: Binding<String>,
        isSecure: Bool
    ) -> some View {
        VStack(spacing: 8) {
            Group {
                if isSecure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .font(.poppins(17, weight: .regular))
            .foregroundStyle(Mono.ink)
            .tint(Mono.ink)
            .padding(.vertical, 10)

            Rectangle()
                .fill(Mono.hairline)
                .frame(height: 1)
        }
    }

    private func primaryButton(
        title: String,
        busy: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .font(.poppins(16, weight: .semibold))
                    .opacity(busy ? 0 : 1)
                if busy {
                    ProgressView()
                        .tint(Mono.inkInverse)
                }
            }
            .foregroundStyle(Mono.inkInverse)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Mono.ink)
            )
            .opacity(disabled || busy ? 0.35 : 1)
        }
        .disabled(disabled || busy)
    }

    private func secondaryButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.poppins(16, weight: .semibold))
                .foregroundStyle(Mono.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Mono.ink.opacity(0.35), lineWidth: 1.5)
                )
        }
    }

    private var legalFootnote: some View {
        Text("By continuing you agree to sync your library with Nyora.")
            .font(.poppins(11, weight: .regular))
            .foregroundStyle(Mono.faint)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private func switchTo(_ newMode: Mode) {
        errorMessage = nil
        focusedField = nil
        mode = newMode
    }

    private func continueAsGuest() {
        enterPreferences()
    }

    /// Advance from auth (Layer 1) to the Preferences step (Layer 2).
    private func enterPreferences() {
        focusedField = nil
        showingPreferences = true
    }

    @MainActor
    private func authenticate(register: Bool) async {
        busy = true
        errorMessage = nil
        focusedField = nil
        defer { busy = false }
        do {
            if register {
                try await client.register(email: email, password: password)
            } else {
                try await client.signIn(email: email, password: password)
            }
            password = ""
            // Kick off an initial library sync in the background; failures here
            // shouldn't block finishing onboarding.
            Task { try? await client.syncNow() }
            enterPreferences()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Preferences onboarding (Layer 2)

/// Second onboarding layer, shown after the user is "in" (signed in / registered
/// / guest). Mirrors the web app's `populatePreferencesCard`: a "Show 18+ sources"
/// toggle (default off) + multi-select language chips with counts, a live "N
/// sources will be added" line, and a CTA that seeds exactly the matching
/// installed sources and persists the NSFW preference before finishing.
///
/// Visuals match NyoraStartView's monochrome editorial system.
struct PreferencesOnboardingView: View {
    /// Called once preferences are applied (sources seeded + NSFW pref set).
    let onFinish: () -> Void

    @State private var catalog: [NyoraCatalogEntry] = []
    @State private var loading = true
    @State private var loadFailed = false
    @State private var applying = false
    @State private var appeared = false

    /// "Show 18+ sources" — default OFF.
    @State private var show18 = false
    /// Selected language codes (lowercased). Empty ⇒ all languages.
    @State private var selectedLangs: Set<String> = []

    // MARK: Body

    var body: some View {
        ZStack {
            Mono.paper.ignoresSafeArea()
            content
                .padding(.horizontal, 32)
        }
        .task { if catalog.isEmpty { await load() } }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            VStack(spacing: 16) {
                ProgressView()
                    .tint(Mono.ink)
                Text("Lining up your sources…")
                    .font(.poppins(15, weight: .medium))
                    .foregroundStyle(Mono.subtle)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, 20)
                    .padding(.bottom, 24)

                ScrollView {
                    VStack(spacing: 14) {
                        if loadFailed {
                            fallbackCard
                        } else {
                            nsfwCard
                            languagesCard
                        }
                    }
                    .padding(.bottom, 12)
                }

                foot
                    .padding(.top, 12)
                    .padding(.bottom, 12)
            }
            .padding(.top, 8)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            .onAppear {
                guard !appeared else { return }
                withAnimation(.easeOut(duration: 0.5)) { appeared = true }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("STEP 02 · YOU'RE IN")
                .font(.poppins(12, weight: .semibold))
                .tracking(2.5)
                .foregroundStyle(Mono.subtle)

            Text("Preferences")
                .font(.poppins(44, weight: .black))
                .foregroundStyle(Mono.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Rectangle()
                .fill(Mono.ink)
                .frame(width: 48, height: 3)

            Text("Choose your languages and content preference — we'll line up the matching sources. Change any of this later in Settings.")
                .font(.poppins(15, weight: .regular))
                .foregroundStyle(Mono.subtle)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Cards

    private var nsfwCard: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Show 18+ sources")
                    .font(.poppins(16, weight: .semibold))
                    .foregroundStyle(Mono.ink)
                Text("Include adult-only sources in Explore & search.")
                    .font(.poppins(13, weight: .regular))
                    .foregroundStyle(Mono.subtle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $show18)
                .labelsHidden()
                .tint(Mono.ink)
        }
        .padding(18)
        .background(cardBackground)
    }

    private var languagesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Languages")
                .font(.poppins(16, weight: .semibold))
                .foregroundStyle(Mono.ink)
            Text("Pick the languages you read, or keep \u{201C}All languages\u{201D}.")
                .font(.poppins(13, weight: .regular))
                .foregroundStyle(Mono.subtle)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 104), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                chip(
                    title: NSLocalizedString("All languages", comment: ""),
                    count: nil,
                    active: selectedLangs.isEmpty
                ) {
                    selectedLangs.removeAll()
                }
                ForEach(languageOptions, id: \.code) { option in
                    chip(
                        title: option.label,
                        count: option.count,
                        active: selectedLangs.contains(option.code)
                    ) {
                        if selectedLangs.contains(option.code) {
                            selectedLangs.remove(option.code)
                        } else {
                            selectedLangs.insert(option.code)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(cardBackground)
    }

    private var fallbackCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Couldn't load the source catalog")
                .font(.poppins(16, weight: .semibold))
                .foregroundStyle(Mono.ink)
            Text("You can continue with the default sources and set your languages later in Settings. The 18+ preference below still applies.")
                .font(.poppins(13, weight: .regular))
                .foregroundStyle(Mono.subtle)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
                .overlay(Mono.hairline)
                .padding(.vertical, 4)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Show 18+ sources")
                        .font(.poppins(15, weight: .semibold))
                        .foregroundStyle(Mono.ink)
                    Text("Include adult-only sources in Explore & search.")
                        .font(.poppins(12, weight: .regular))
                        .foregroundStyle(Mono.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: $show18)
                    .labelsHidden()
                    .tint(Mono.ink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(cardBackground)
    }

    // MARK: Foot (count + CTA)

    private var foot: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !loadFailed {
                Text(countText)
                    .font(.poppins(14, weight: .semibold))
                    .foregroundStyle(Mono.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                Task { await applyAndFinish() }
            } label: {
                ZStack {
                    Text("Start reading")
                        .font(.poppins(16, weight: .semibold))
                        .opacity(applying ? 0 : 1)
                    if applying {
                        ProgressView().tint(Mono.inkInverse)
                    }
                }
                .foregroundStyle(Mono.inkInverse)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Mono.ink)
                )
                .opacity(applying ? 0.35 : 1)
            }
            .disabled(applying)
        }
    }

    // MARK: Reusable

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Mono.field)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Mono.hairline, lineWidth: 1)
            )
    }

    private func chip(
        title: String,
        count: Int?,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.poppins(14, weight: .medium))
                    .lineLimit(1)
                if let count {
                    Text(String(count))
                        .font(.poppins(12, weight: .semibold))
                        .foregroundStyle(active ? Mono.inkInverse.opacity(0.7) : Mono.faint)
                }
            }
            .foregroundStyle(active ? Mono.inkInverse : Mono.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(active ? Mono.ink : Color(uiColor: .systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(active ? Color.clear : Mono.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Derived data

    private struct LanguageOption {
        let code: String
        let label: String
        let count: Int
    }

    /// Distinct languages present in the catalog, respecting the current 18+
    /// toggle so counts reflect what would actually be added. Sorted by count
    /// desc, then label.
    private var languageOptions: [LanguageOption] {
        var counts: [String: Int] = [:]
        for entry in catalog where show18 || !entry.isNsfw {
            counts[langCode(entry), default: 0] += 1
        }
        return counts
            .map { LanguageOption(code: $0.key, label: languageLabel($0.key), count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.label < $1.label }
    }

    /// Entries matching the current selection — the set that will be seeded.
    private var matchedEntries: [NyoraCatalogEntry] {
        catalog.filter {
            (selectedLangs.isEmpty || selectedLangs.contains(langCode($0))) && (show18 || !$0.isNsfw)
        }
    }

    /// The set actually seeded — falls back to "all matching the 18+ rule" so we
    /// never leave an empty shelf.
    private var seedEntries: [NyoraCatalogEntry] {
        let matched = matchedEntries
        if !matched.isEmpty { return matched }
        return catalog.filter { show18 || !$0.isNsfw }
    }

    private var countText: String {
        let n = seedEntries.count
        return "\(n) source\(n == 1 ? "" : "s") will be added"
    }

    private func langCode(_ entry: NyoraCatalogEntry) -> String {
        entry.lang.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private func languageLabel(_ code: String) -> String {
        switch code {
            case "", "multi", "all": return NSLocalizedString("Multi-language", comment: "")
            default:
                return Locale.current.localizedString(forIdentifier: code)
                    ?? Locale.current.localizedString(forLanguageCode: String(code.prefix(2)))
                    ?? code.uppercased()
        }
    }

    // MARK: Actions

    private func load() async {
        loading = true
        loadFailed = false
        let entries = await NyoraCatalog.fetchAll(server: SourceManager.nyoraServer)
        catalog = entries
        loadFailed = entries.isEmpty
        loading = false
    }

    @MainActor
    private func applyAndFinish() async {
        applying = true
        defer { applying = false }

        // Persist the NSFW preference (toggle is "Show 18+", key is inverse).
        UserDefaults.standard.set(!show18, forKey: "Sources.disableNsfw")
        NotificationCenter.default.post(name: Notification.Name("Sources.disableNsfw"), object: nil)

        // Seed the matching installed sources (no-op when the catalog failed to
        // load — the pre-installed defaults are left in place).
        if !loadFailed {
            await SourceManager.shared.replaceNyoraSources(with: seedEntries)
        }

        onFinish()
    }
}
