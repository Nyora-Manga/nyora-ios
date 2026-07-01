//
//  AddSourceView.swift
//  Aidoku
//
//  Created by Skitty on 5/23/25.
//

import AidokuRunner
import SwiftUI
import UniformTypeIdentifiers

struct AddSourceView: View {
    let allExternalSources: [ExternalSourceInfo]

    @State private var externalSources: [SourceInfo2] = []
    @State private var allSourcesInstalled: Bool = false

    @State private var importing = false
    @State private var searching = false
    @State private var searchText = ""
    @State private var showLocalSetup = false
    @State private var showKomgaSetup = false
    @State private var showKavitaSetup = false
    @State private var showNyoraSetup = false
    @State private var showImportFailAlert = false

    @State private var searchFocused: Bool? = false

    @Environment(\.dismiss) private var dismiss

    init(externalSources: [ExternalSourceInfo]) {
        allExternalSources = externalSources

        let result = filterExternalSources()
        _externalSources = State(initialValue: result.0)
        _allSourcesInstalled = State(initialValue: result.allSourcesInstalled)
    }

    var body: some View {
        PlatformNavigationStack {
            List {
                // Nyora fork: only the hosted Nyora helper source is offered.
                // The import button and external (WASM repo) sources are hidden.
                builtInSources
            }
            .contentMarginsPlease(.top, 4)
            .customSearchable(
                text: $searchText,
                enabled: $searching,
                focused: $searchFocused,
                hidesNavigationBarDuringPresentation: false,
                hidesSearchBarWhenScrolling: false,
                onCancel: {
                    // task delays slightly to prevent sheet from closing
                    Task {
                        searching = false
                    }
                }
            )
            .animation(.default, value: searchText)
            .animation(.default, value: searching)
            .sheet(isPresented: $importing) {
                DocumentPickerView(
                    allowedContentTypes: [
                        UTType(exportedAs: "app.aidoku.Aidoku.aix", conformingTo: .zip),
                        .init(filenameExtension: "aix")!
                    ],
                    onDocumentsPicked: { urls in
                        guard let url = urls.first else {
                            return
                        }
                        Task {
                            let result = await SourceManager.shared.importSource(from: url)
                            if result == nil {
                                showImportFailAlert = true
                            } else {
                                dismiss()
                            }
                        }
                    }
                )
                .ignoresSafeArea()
            }
            .alert(NSLocalizedString("IMPORT_FAIL"), isPresented: $showImportFailAlert) {
                Button(NSLocalizedString("OK"), role: .cancel) {}
            } message: {
                Text(NSLocalizedString("SOURCE_IMPORT_FAIL_TEXT"))
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !allExternalSources.isEmpty {
                        AddSourceFilterMenu()
                    }
                }
            }
            .navigationTitle(NSLocalizedString("ADD_SOURCE"))
            .navigationBarTitleDisplayMode(.inline)
            .onReceive(NotificationCenter.default.publisher(for: .filterExternalSources)) { _ in
                let result = filterExternalSources()
                withAnimation {
                    externalSources = result.0
                    allSourcesInstalled = result.allSourcesInstalled
                }
            }
        }
        .interactiveDismissDisabled(searching)
    }

    var builtInSources: some View {
        // Nyora fork: only the hosted Nyora helper source. Local/Komga/Kavita/demo
        // and external WASM sources are intentionally removed.
        Section {
            ExternalSourceTableCell(
                source: .init(
                    sourceId: "nyora",
                    name: "Nyora",
                    languages: ["multi"],
                    version: 1,
                    contentRating: .safe
                ),
                subtitle: NSLocalizedString("Hosted Nyora content server"),
                onGet: {
                    showNyoraSetup = true
                    return true
                }
            )
            .background(NavigationLink("", destination: NyoraSetupView(), isActive: $showNyoraSetup).hidden())
        }
    }

    func infoView(title: String, subtitle: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .fontWeight(.medium)
            Text(subtitle)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    func checkAllSourcesInstalled() -> Bool {
        let installedSources = SourceManager.shared.sources.map { $0.toInfo() }
        return !allExternalSources.contains { source in
            !installedSources.contains(where: { $0.sourceId == source.id })
        }
    }

    func filterExternalSources() -> ([SourceInfo2], allSourcesInstalled: Bool) {
        guard let appVersionString = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        else { return ([], true) }
        let appVersion = SemanticVersion(appVersionString)
        let selectedLanguages = UserDefaults.standard.stringArray(forKey: "Browse.languages") ?? []
        let contentRatings = (UserDefaults.standard.stringArray(forKey: "Browse.contentRatings") ?? [])
            .compactMap { SourceContentRating(stringValue: $0) }

        var allSourcesInstalled = true

        let installedSources = SourceManager.shared.sources.map { $0.toInfo() }
        let result = allExternalSources
            .compactMap { info -> SourceInfo2? in
                // strip installed sources from external list
                if installedSources.contains(where: { $0.sourceId == info.id }) {
                    return nil
                }
                // this source isn't installed
                allSourcesInstalled = false
                // check version availability
                if let minAppVersion = info.minAppVersion {
                    let minAppVersion = SemanticVersion(minAppVersion)
                    if minAppVersion > appVersion {
                        return nil
                    }
                }
                if let maxAppVersion = info.maxAppVersion {
                    let maxAppVersion = SemanticVersion(maxAppVersion)
                    if maxAppVersion < appVersion {
                        return nil
                    }
                }
                // hide unselected content ratings
                let contentRating = info.resolvedContentRating
                if !contentRatings.contains(where: { $0 == contentRating }) {
                    return nil
                }
                // hide unselected languages
                if !selectedLanguages.contains(where: { info.languages?.contains($0) ?? (info.lang == $0) }) {
                    return nil
                }
                return info.toInfo()
            }
            // sort first by name, then by language
            .sorted { $0.name < $1.name }
            .sorted {
                let lhsLang = $0.languages.count == 1 ? $0.languages[0] : "multi"
                let rhsLang = $1.languages.count == 1 ? $1.languages[0] : "multi"
                let lhs = SourceManager.languageCodes.firstIndex(of: lhsLang) ?? Int.max
                let rhs = SourceManager.languageCodes.firstIndex(of: rhsLang) ?? Int.max
                return lhs < rhs
            }
        return (result, allSourcesInstalled)
    }
}
