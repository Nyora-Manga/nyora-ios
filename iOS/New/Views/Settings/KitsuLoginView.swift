//
//  KitsuLoginView.swift
//  Aidoku
//
//  Username/password login sheet for trackers that use the OAuth password grant (Kitsu).
//

import SwiftUI

struct KitsuLoginView: View {
    let tracker: any UsernamePasswordTracker
    let completion: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var password = ""
    @State private var loading = false
    @State private var showError = false

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField(NSLocalizedString("EMAIL_OR_USERNAME"), text: $username)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField(NSLocalizedString("PASSWORD"), text: $password)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .onSubmit {
                            Task { await submit() }
                        }
                } footer: {
                    if showError {
                        Text(NSLocalizedString("LOGIN_FAILED"))
                            .foregroundStyle(.red)
                    } else {
                        Text(NSLocalizedString("KITSU_LOGIN_INFO"))
                    }
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            Text(NSLocalizedString("LOGIN"))
                            if loading {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(username.isEmpty || password.isEmpty || loading)
                }
            }
            .navigationTitle(tracker.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("CANCEL")) {
                        completion(false)
                        dismiss()
                    }
                }
            }
        }
    }

    private func submit() async {
        guard !username.isEmpty, !password.isEmpty, !loading else { return }
        loading = true
        showError = false
        let success = await tracker.login(username: username, password: password)
        loading = false
        if success {
            completion(true)
            dismiss()
        } else {
            showError = true
        }
    }
}
