//
//  LocalLibraryView.swift
//  Aidoku (iOS) — Nyora fork
//
//  The Local files library — a grid of imported local titles with an Import (+) button.
//  Opened from the Browse "Local" quick action. Tapping a title opens its details/reader.
//

import AidokuRunner
import CoreData
import SwiftUI

struct LocalLibraryView: View {
    @EnvironmentObject private var path: NavigationCoordinator
    @State private var manga: [AidokuRunner.Manga] = []
    @State private var loaded = false
    @State private var showImporter = false

    private let columns = [GridItem(.adaptive(minimum: 108, maximum: 150), spacing: 12)]

    var body: some View {
        Group {
            if manga.isEmpty && loaded {
                emptyView
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(manga, id: \.key) { item in
                            Button {
                                open(item)
                            } label: {
                                card(item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle(NSLocalizedString("LOCAL_FILES", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showImporter = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task { if !loaded { await load() } }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("refresh-content"))) { _ in
            Task { await load() }
        }
        .sheet(isPresented: $showImporter) {
            LocalFileImportView()
        }
    }

    private func card(_ item: AidokuRunner.Manga) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(NyoraTheme.coverAspectRatio, contentMode: .fit)
                .overlay {
                    SourceImageView(
                        sourceId: LocalSourceRunner.sourceKey,
                        imageUrl: item.cover ?? "",
                        downsampleWidth: 300,
                        contentMode: .fill
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: NyoraTheme.cornerCover, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: NyoraTheme.cornerCover, style: .continuous)
                        .strokeBorder(Color.nyoraCardOutline, lineWidth: 1)
                )

            Text(item.title)
                .font(.poppins(12, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 14) {
            Image(systemName: "folder")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.secondary)
            Text(NSLocalizedString("LOCAL_FILES_EMPTY", comment: ""))
                .font(.poppins(15, weight: .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showImporter = true
            } label: {
                Label(NSLocalizedString("IMPORT", comment: ""), systemImage: "plus")
                    .font(.poppins(15, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func open(_ item: AidokuRunner.Manga) {
        guard let source = SourceManager.shared.source(for: LocalSourceRunner.sourceKey) else { return }
        path.push(MangaViewController(source: source, manga: item, parent: path.rootViewController))
    }

    private func load() async {
        let items = await CoreDataManager.shared.container.performBackgroundTask { context -> [AidokuRunner.Manga] in
            let request = MangaObject.fetchRequest()
            request.predicate = NSPredicate(format: "sourceId == %@", LocalSourceRunner.sourceKey)
            let objects = (try? context.fetch(request)) ?? []
            return objects.map { $0.toNewManga() }
        }
        manga = items
        loaded = true
    }
}
