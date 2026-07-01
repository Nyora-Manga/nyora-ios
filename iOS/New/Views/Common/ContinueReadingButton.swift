//
//  ContinueReadingButton.swift
//  Aidoku (iOS) — Nyora fork
//
//  ND-019 — Detached circular "Continue reading" button.
//
//  A floating circular indigo→purple button (ported from nyora-android's
//  navigation_rail_fab.xml FAB) that resumes the most recently read chapter.
//  It hides itself when there is no in-progress reading history, and opens the
//  last-read chapter in the reader on tap. Self-contained: it loads its own
//  resume target from Core Data and presents the existing reader flow via
//  `SwiftUIReaderNavigationController`, so it can be overlaid on any surface
//  (currently the Discover home) without threading data through callers.
//

import AidokuRunner
import SwiftUI

struct ContinueReadingButton: View {
    /// A resolved "resume reading" destination: the source, its manga (with the
    /// full chapter list so the reader can page forward/back), and the exact
    /// chapter the user last had open.
    struct ResumeTarget: Identifiable {
        let id = UUID()
        let source: AidokuRunner.Source
        let manga: AidokuRunner.Manga
        let chapter: AidokuRunner.Chapter
    }

    /// Diameter of the floating circular button.
    var diameter: CGFloat = 58

    @State private var target: ResumeTarget?
    @State private var presentedTarget: ResumeTarget?

    var body: some View {
        Group {
            if let target {
                button(for: target)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: target?.id)
        .task { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .historyAdded)) { _ in
            Task { await refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .historySet)) { _ in
            Task { await refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .historyRemoved)) { _ in
            Task { await refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .updateHistory)) { _ in
            Task { await refresh() }
        }
        .fullScreenCover(item: $presentedTarget) { target in
            SwiftUIReaderNavigationController(
                source: target.source,
                manga: target.manga,
                chapter: target.chapter
            )
            .ignoresSafeArea()
        }
    }

    private func button(for target: ResumeTarget) -> some View {
        Button {
            presentedTarget = target
        } label: {
            Image(systemName: "book.fill")
                .font(.system(size: diameter * 0.38, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: diameter, height: diameter)
                .background {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.nyoraIndigo, Color.nyoraPurple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                }
                .shadow(color: Color.nyoraIndigo.opacity(0.4), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(ContinueReadingButtonStyle())
        .accessibilityLabel(Text(NSLocalizedString("CONTINUE_READING", comment: "")))
    }

    // MARK: - Loading

    /// Resolve the most recent in-progress reading history entry into a full
    /// resume target, or clear the button when nothing is resumable.
    private func refresh() async {
        let entry = await CoreDataManager.shared.container.performBackgroundTask { context -> (source: String, manga: String, chapter: String)? in
            guard let obj = CoreDataManager.shared.getRecentHistory(limit: 1, offset: 0, context: context).first else {
                return nil
            }
            return (obj.sourceId, obj.mangaId, obj.chapterId)
        }

        guard
            let entry,
            let source = SourceManager.shared.source(for: entry.source)
        else {
            target = nil
            return
        }

        let baseManga = await CoreDataManager.shared.container.performBackgroundTask { context -> AidokuRunner.Manga? in
            CoreDataManager.shared.getManga(
                sourceId: entry.source,
                mangaId: entry.manga,
                context: context
            )?.toNewManga()
        }

        let chapters = await CoreDataManager.shared
            .getChapters(sourceId: entry.source, mangaId: entry.manga)
            .map { $0.toNew() }

        guard
            var manga = baseManga,
            let chapter = chapters.first(where: { $0.key == entry.chapter })
        else {
            target = nil
            return
        }

        manga.chapters = chapters
        target = ResumeTarget(source: source, manga: manga, chapter: chapter)
    }
}

/// Press feedback for the floating button: a subtle scale + dim.
private struct ContinueReadingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
