//
//  NyoraAccountView.swift
//  Aidoku (iOS) — Nyora fork
//
//  Account + manual library sync UI for the Nyora sync server.
//

import SwiftUI

struct NyoraAccountView: View {
    @ObservedObject private var client = NyoraSyncClient.shared

    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        Form {
            if client.isSignedIn {
                Section("Account") {
                    HStack {
                        Text("Signed in")
                        Spacer()
                        Text(client.email ?? "")
                            .foregroundColor(.secondary)
                    }
                    Button("Sign out", role: .destructive) {
                        client.signOut()
                        message = nil
                    }
                }
                Section {
                    Button {
                        Task { await syncNow() }
                    } label: {
                        HStack {
                            Text("Sync now")
                            if busy { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(busy)
                } footer: {
                    Text("Pushes your library to the server and pulls entries from your other devices (last-write-wins).")
                }
            } else {
                Section {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    SecureField("Password", text: $password)
                    Button {
                        Task { await authenticate(register: false) }
                    } label: {
                        HStack {
                            Text("Sign in")
                            if busy { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(busy || email.isEmpty || password.isEmpty)
                    Button("Create account") {
                        Task { await authenticate(register: true) }
                    }
                    .disabled(busy || email.isEmpty || password.isEmpty)
                } header: {
                    Text("Sign in")
                } footer: {
                    Text("Syncs your library across your Nyora apps via your self-hosted server.")
                }
            }

            if let message {
                Section {
                    Text(message)
                        .foregroundColor(isError ? .red : .secondary)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("Nyora Sync")
    }

    private func authenticate(register: Bool) async {
        busy = true; message = nil; isError = false
        defer { busy = false }
        do {
            if register {
                try await client.register(email: email, password: password)
            } else {
                try await client.signIn(email: email, password: password)
            }
            password = ""
            message = "Signed in. Tap Sync now to sync your library."
        } catch {
            isError = true
            message = error.localizedDescription
        }
    }

    private func syncNow() async {
        busy = true; message = nil; isError = false
        defer { busy = false }
        do {
            let result = try await client.syncNow()
            message = "Synced — pushed \(result.pushed), pulled \(result.pulled)."
        } catch {
            isError = true
            message = error.localizedDescription
        }
    }
}
