//
//  ColorizationSettingsView.swift
//  Nyora (iOS)
//

import SwiftUI

struct ColorizationSettingsView: View {
    @ObservedObject private var controller = ColorizationController.shared
    @State private var confirmDelete = false

    var body: some View {
        List {
            Section {
                Toggle(
                    "Colorize pages",
                    isOn: Binding(
                        get: { controller.enabled },
                        set: { controller.setEnabled($0) }
                    )
                )
                .disabled(!controller.isModelReady && !controller.enabled)
            } footer: {
                if controller.isModelReady {
                    Text("Colorize visible manga pages on this device. The original page is restored immediately when this is turned off.")
                } else {
                    Text("Download and verify the on-device model below before colorization can be enabled. Reader controls never download it automatically.")
                }
            }

            Section {
                modelStatusRow

                switch controller.modelStatus {
                case .ready:
                    Button("Delete downloaded model", role: .destructive) {
                        confirmDelete = true
                    }
                case .downloading:
                    EmptyView()
                case .checking:
                    EmptyView()
                case .notInstalled, .failed:
                    Button("Download model (62 MB)") {
                        Task { await controller.downloadModel() }
                    }
                    .disabled(controller.isDownloadingModel)
                }
            } header: {
                Text("On-device model")
            } footer: {
                Text("The model is manga-colorization-v2. It is downloaded from a commit-pinned HTTPS URL and SHA-256 verified before use. Page images stay on your device.")
            }

            if let error = controller.lastNonfatalError, !error.isEmpty {
                Section {
                    Text(error)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Last colorization issue")
                } footer: {
                    Text("Unsupported, unusually large, or animated pages remain unchanged. Other pages can still be colorized.")
                }
            }
        }
        .navigationTitle("Colorization")
        .task {
            await controller.refreshModelStatus()
        }
        .confirmationDialog(
            "Delete colorization model?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete model", role: .destructive) {
                Task { await controller.deleteModel() }
            }
        } message: {
            Text("This removes the verified 62 MB on-device model and turns off page colorization. You can download it again later.")
        }
    }

    @ViewBuilder
    private var modelStatusRow: some View {
        switch controller.modelStatus {
        case .checking:
            HStack {
                ProgressView()
                Text("Checking downloaded model…")
            }
        case .notInstalled:
            Label("Not downloaded", systemImage: "arrow.down.circle")
                .foregroundStyle(.secondary)
        case let .downloading(progress):
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Downloading and verifying…")
                    Spacer()
                    Text(progress.formatted(.percent.precision(.fractionLength(0))))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: progress)
            }
        case .ready:
            Label("Downloaded and verified", systemImage: "checkmark.shield.fill")
                .foregroundStyle(.green)
        case let .failed(message):
            VStack(alignment: .leading, spacing: 6) {
                Label("Download unavailable", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
