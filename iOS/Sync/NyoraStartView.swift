//
//  NyoraStartView.swift
//  Aidoku (iOS) — Nyora fork
//
//  First-launch onboarding (NX-008): a branded start page offering Sign in,
//  Create account (both against the Nyora sync server via NyoraSyncClient), and
//  Continue as guest (proceeds locally). Shown once — the caller persists the
//  "Nyora.completedStart" flag and dismisses when `onFinish` fires.
//

import SwiftUI

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
    @ObservedObject private var accent = AccentManager.shared

    @State private var mode: Mode = .landing
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var errorMessage: String?

    @FocusState private var focusedField: Field?
    private enum Field { case email, password }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                Spacer(minLength: 24)
                brand
                Spacer(minLength: 24)
                card
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 28)
        }
        .animation(.easeInOut(duration: 0.25), value: mode)
    }

    // MARK: - Background

    private var background: some View {
        LinearGradient(
            colors: [
                accent.color.opacity(0.85),
                accent.color.opacity(0.35),
                Color(uiColor: .systemBackground)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Brand

    private var brand: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(width: 96, height: 96)
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: .black.opacity(0.15), radius: 12, y: 6)

            Text("Nyora")
                .font(.poppins(38, weight: .bold))
                .foregroundStyle(.white)

            Text("Your manga library, everywhere.")
                .font(.poppins(15, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Card

    private var card: some View {
        VStack(spacing: 16) {
            if mode.isAuth {
                authForm
            } else {
                landingButtons
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.poppins(13, weight: .regular))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: NyoraTheme.cornerCard + 4, style: .continuous)
                .fill(.ultraThinMaterial)
        )
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
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Auth form

    private var authForm: some View {
        VStack(spacing: 14) {
            Text(mode == .signUp ? "Create your account" : "Welcome back")
                .font(.poppins(20, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            field(
                systemImage: "envelope",
                placeholder: "Email",
                text: $email,
                isSecure: false
            )
            .textContentType(.emailAddress)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .focused($focusedField, equals: .email)

            field(
                systemImage: "lock",
                placeholder: "Password",
                text: $password,
                isSecure: true
            )
            .textContentType(mode == .signUp ? .newPassword : .password)
            .focused($focusedField, equals: .password)

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
                Text("Back")
                    .font(.poppins(15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .disabled(busy)
        }
    }

    // MARK: - Reusable controls

    private func field(
        systemImage: String,
        placeholder: String,
        text: Binding<String>,
        isSecure: Bool
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Group {
                if isSecure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .font(.poppins(16, weight: .regular))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
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
                        .tint(.white)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(accent.color)
            )
            .opacity(disabled || busy ? 0.6 : 1)
        }
        .disabled(disabled || busy)
    }

    private func secondaryButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.poppins(16, weight: .semibold))
                .foregroundStyle(accent.color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(accent.color.opacity(0.5), lineWidth: 1.5)
                )
        }
    }

    // MARK: - Actions

    private func switchTo(_ newMode: Mode) {
        errorMessage = nil
        focusedField = nil
        mode = newMode
    }

    private func continueAsGuest() {
        onFinish()
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
            onFinish()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
