//
//  AddSourceView.swift
//  Aidoku
//
//  Created by Skitty on 5/23/25.
//
//  Nyora fork: the Nyora helper is a SOURCE REPOSITORY. This screen lists every
//  parser source it offers (GET /sources/catalog) and installs each as its own
//  Aidoku source — like the Android per-source model. Verified-working sources
//  are surfaced under "Recommended" so users don't land on dead mirrors.
//

import AidokuRunner
import SwiftUI

struct AddSourceView: View {
    // Kept for call-site compatibility (Browse passes the old WASM external list); unused.
    let allExternalSources: [ExternalSourceInfo]

    @State private var catalog: [NyoraCatalogEntry] = []
    @State private var installedParserSources: Set<String> = []
    @State private var loading = true
    @State private var loadFailed = false
    @State private var searchText = ""

    @Environment(\.dismiss) private var dismiss

    init(externalSources: [ExternalSourceInfo] = []) {
        allExternalSources = externalSources
    }

    /// All not-installed catalog entries matching the current search, name-sorted.
    private var filtered: [NyoraCatalogEntry] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return catalog
            .filter { !installedParserSources.contains($0.id) }
            .filter { q.isEmpty || $0.name.lowercased().contains(q) || $0.lang.lowercased().contains(q) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Verified-working sources (in curated order) that aren't installed yet.
    private var recommendedEntries: [NyoraCatalogEntry] {
        let available = Dictionary(
            catalog.filter { !installedParserSources.contains($0.id) }.map { ($0.id, $0) },
            uniquingKeysWith: { a, _ in a }
        )
        return NyoraCatalog.recommended.compactMap { available[$0] }
    }

    var body: some View {
        PlatformNavigationStack {
            List {
                if loading {
                    HStack { Spacer(); ProgressView(); Spacer() }.padding()
                } else if loadFailed {
                    infoView(
                        title: NSLocalizedString("NO_AVAILABLE_SOURCES"),
                        subtitle: "Couldn't reach the Nyora source server. Pull to retry."
                    )
                } else if searchText.isEmpty {
                    let rec = recommendedEntries
                    if !rec.isEmpty {
                        Section {
                            ForEach(rec) { cell($0) }
                        } header: {
                            Text("Recommended")
                        } footer: {
                            Text("Sources verified to work. The full catalog is below.")
                        }
                    }
                    let others = filtered.filter { !NyoraCatalog.recommended.contains($0.id) }
                    if !others.isEmpty {
                        Section {
                            ForEach(others) { cell($0) }
                        } header: {
                            Text(String(format: NSLocalizedString("%i sources", comment: ""), others.count))
                        }
                    } else if rec.isEmpty {
                        infoView(title: NSLocalizedString("ALL_SOURCES_INSTALLED"), subtitle: "")
                    }
                } else {
                    let entries = filtered
                    if entries.isEmpty {
                        infoView(title: NSLocalizedString("NO_RESULTS"), subtitle: "")
                    } else {
                        Section {
                            ForEach(entries) { cell($0) }
                        } header: {
                            Text(String(format: NSLocalizedString("%i sources", comment: ""), entries.count))
                        }
                    }
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .refreshable { await load() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton { dismiss() }
                }
            }
            .navigationTitle(NSLocalizedString("ADD_SOURCE"))
            .navigationBarTitleDisplayMode(.inline)
            .task { if catalog.isEmpty { await load() } }
        }
    }

    @ViewBuilder
    private func cell(_ entry: NyoraCatalogEntry) -> some View {
        ExternalSourceTableCell(
            source: .init(
                sourceId: entry.id,
                name: entry.name,
                languages: [entry.lang.isEmpty ? "multi" : entry.lang],
                version: 1,
                contentRating: .safe
            ),
            subtitle: entry.lang.isEmpty ? nil : entry.lang.uppercased(),
            onGet: {
                install(entry)
                return true
            }
        )
    }

    private func load() async {
        loading = true
        loadFailed = false
        let entries = await NyoraCatalog.fetchAll(server: SourceManager.nyoraServer)
        installedParserSources = Set(
            SourceManager.shared.sources
                .filter { $0.key.hasPrefix("\(NyoraSourceRunner.sourceKeyPrefix).") }
                .compactMap { UserDefaults.standard.string(forKey: "\($0.key).parserSource") }
        )
        catalog = entries
        loadFailed = entries.isEmpty
        loading = false
    }

    private func install(_ entry: NyoraCatalogEntry) {
        Task {
            await SourceManager.shared.addNyoraSource(id: entry.id, name: entry.name, lang: entry.lang)
            await MainActor.run {
                _ = installedParserSources.insert(entry.id)
            }
        }
    }

    private func infoView(title: String, subtitle: String) -> some View {
        VStack(spacing: 4) {
            Text(title).fontWeight(.medium)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}
