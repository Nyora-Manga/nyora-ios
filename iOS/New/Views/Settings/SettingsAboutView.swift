//
//  SettingsAboutView.swift
//  Nyora
//

import SwiftUI

struct SettingsAboutView: View {
    var body: some View {
        List {
            Section {
                HStack {
                    Text(NSLocalizedString("VERSION"))
                    Spacer()
                    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                    ?? NSLocalizedString("UNKNOWN")
                    Text(version)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text(NSLocalizedString("BUILD"))
                    Spacer()
                    let version = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
                    ?? NSLocalizedString("UNKNOWN")
                    Text(version)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                SettingView(setting: .init(
                    title: "Website",
                    value: .link(.init(url: "https://nyora.pages.dev", external: true))
                ))
                SettingView(setting: .init(
                    title: NSLocalizedString("GITHUB_REPO"),
                    value: .link(.init(url: "https://github.com/Hasan72341/nyora-ios"))
                ))
            }

            Section {
                SettingView(setting: .init(
                    title: "Reader UI based on Aidoku",
                    value: .link(.init(url: "https://github.com/Aidoku/Aidoku", external: true))
                ))
            } footer: {
                Text("Nyora's reader interface is a fork of the open-source Aidoku app (GPLv3). Nyora provides the source catalog, parser backend, and cross-device cloud sync.")
            }
        }
        .navigationTitle(NSLocalizedString("ABOUT"))
    }
}
