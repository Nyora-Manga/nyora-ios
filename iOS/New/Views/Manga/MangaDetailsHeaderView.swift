//
//  MangaDetailsHeaderView.swift
//  Aidoku
//
//  Created by Skitty on 8/18/23.
//

import SwiftUI
import AidokuRunner
import MarkdownUI
import NukeUI
import SafariServices

struct MangaDetailsHeaderView: View {
    @Binding var source: AidokuRunner.Source?

    @Binding var manga: AidokuRunner.Manga
    @Binding var chapters: [AidokuRunner.Chapter]
    @Binding var nextChapter: AidokuRunner.Chapter?
    @Binding var readingInProgress: Bool
    @Binding var readChapterCount: Int
    @Binding var allChaptersLocked: Bool
    @Binding var allChaptersRead: Bool
    @Binding var initialDataLoaded: Bool

    @Binding var bookmarked: Bool
    @Binding var coverPressed: Bool
    @Binding var chapterSortOption: ChapterSortOption
    @Binding var chapterSortAscending: Bool

    @Binding var filters: [ChapterFilterOption]
    @Binding var langFilter: String?
    @Binding var scanlatorFilter: [String]

    @Binding var descriptionExpanded: Bool

    @Binding var chapterTitleDisplayMode: ChapterTitleDisplayMode

    var hasOtherDownloads: Bool
    var onTrackerButtonPressed: (() -> Void)?
    var onReadButtonPressed: (() -> Void)?

    @EnvironmentObject private var path: NavigationCoordinator

    @State private var readButtonText = NSLocalizedString("LOADING_ELLIPSIS")
    @State private var readButtonDisabled = true
    @State private var animationTrigger = false
    @State private var longHeldBookmark = false
    @State private var longHeldSafari = false
    @State private var isTracking = false
    @State private var hasAvailableTrackers = false
    @State private var showLibraryRemoveConfirm = false
    @State private var altTitles: [String] = []
    @State private var rating: Float?
    @State private var language: String?
    @State private var categoryNames: [String] = []
    @State private var bookmarkScale: CGFloat = 1

    static let coverWidth: CGFloat = 114

    init(
        source: Binding<AidokuRunner.Source?>,
        manga: Binding<AidokuRunner.Manga>,
        chapters: Binding<[AidokuRunner.Chapter]>,
        nextChapter: Binding<AidokuRunner.Chapter?>,
        readingInProgress: Binding<Bool>,
        readChapterCount: Binding<Int>,
        allChaptersLocked: Binding<Bool>,
        allChaptersRead: Binding<Bool>,
        initialDataLoaded: Binding<Bool>,
        bookmarked: Binding<Bool>,
        coverPressed: Binding<Bool>,
        chapterSortOption: Binding<ChapterSortOption>,
        chapterSortAscending: Binding<Bool>,
        filters: Binding<[ChapterFilterOption]>,
        langFilter: Binding<String?>,
        scanlatorFilter: Binding<[String]>,
        descriptionExpanded: Binding<Bool>,
        chapterTitleDisplayMode: Binding<ChapterTitleDisplayMode>,
        hasOtherDownloads: Bool,
        onTrackerButtonPressed: (() -> Void)? = nil,
        onReadButtonPressed: (() -> Void)? = nil
    ) {
        self._source = source
        self._manga = manga
        self._chapters = chapters
        self._nextChapter = nextChapter
        self._readingInProgress = readingInProgress
        self._readChapterCount = readChapterCount
        self._allChaptersLocked = allChaptersLocked
        self._allChaptersRead = allChaptersRead
        self._initialDataLoaded = initialDataLoaded
        self._bookmarked = bookmarked
        self._coverPressed = coverPressed
        self._chapterSortOption = chapterSortOption
        self._chapterSortAscending = chapterSortAscending
        self._filters = filters
        self._langFilter = langFilter
        self._scanlatorFilter = scanlatorFilter
        self._descriptionExpanded = descriptionExpanded
        self._chapterTitleDisplayMode = chapterTitleDisplayMode
        self.hasOtherDownloads = hasOtherDownloads
        self.onTrackerButtonPressed = onTrackerButtonPressed
        self.onReadButtonPressed = onReadButtonPressed

        self._isTracking = State(initialValue: TrackerManager.shared.isTracking(
            sourceId: manga.wrappedValue.sourceKey,
            mangaId: manga.wrappedValue.key
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    Button {
                        coverPressed = true
                    } label: {
                        // 13:18 Nyora cover ratio
                        MangaCoverView(
                            source: source,
                            coverImage: manga.cover ?? "",
                            width: Self.coverWidth,
                            height: Self.coverWidth / NyoraTheme.coverAspectRatio
                        )
                        .id(manga.cover ?? "")
                    }
                    .buttonStyle(DarkOverlayButtonStyle())
                    .clipShape(RoundedRectangle(cornerRadius: NyoraTheme.cornerCover, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: NyoraTheme.cornerCover, style: .continuous)
                            .strokeBorder(Color.nyoraCardOutline, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 0)

                    Text(manga.title)
                        .lineLimit(4)
                        .font(.poppins(22, weight: .bold))
                        .textSelection(.enabled)
                        .foregroundStyle(.primary)
                        .minimumScaleFactor(0.75)
                        .contentTransitionDisabledPlease()
                        .padding(.bottom, 4)

                    if !altTitles.isEmpty {
                        Text(altTitles.prefix(3).joined(separator: " • "))
                            .lineLimit(2)
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                            .textSelection(.enabled)
                            .padding(.bottom, 6)
                            .transition(.opacity)
                    }

                    if let authors = manga.authors, !authors.isEmpty {
                        let label = Text(authors.joined(separator: ", "))
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                            .font(.callout)
                            .padding(.bottom, 6)
                            .textSelection(.enabled)
                            .transition(.opacity)

                        if let source, source.supportsAuthorSearch {
                            Button {
                                // we'll need a better ui in the future for different author selection
                                guard let author = authors.first else { return }

                                let viewController = MangaListViewController(source: source, title: author)
                                viewController.getEntries = { page in
                                    try await source.getSearchMangaList(query: nil, page: page, filters: [
                                        .text(id: "author", value: author)
                                    ])
                                }
                                path.push(viewController)
                            } label: {
                                label
                            }
                            .buttonStyle(.borderless)
                        } else {
                            label
                        }
                    }

                    labelsView

                    buttonsView
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 174)
            .padding(.bottom, 14)
            .padding(.horizontal, 20)

            progressView

            if let description = manga.description, !description.isEmpty {
                ExpandableTextView(text: description, expanded: $descriptionExpanded)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)
                    .padding(.horizontal, 20)
                    .foregroundStyle(.secondary)
            }

            tagsView

            // read button
            Button {
                onReadButtonPressed?()
            } label: {
                Text(readButtonText)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: .medium))
            .padding(11)
            .foregroundStyle(.white)
            .background(Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.bottom, 20)
            .padding(.horizontal, 20)
            .allowsHitTesting(!readButtonDisabled)

            // hide the chapter list header if there are no chapters and the other downloads header is shown
            if !(manga.chapters ?? chapters).isEmpty || !hasOtherDownloads {
                ChapterListHeaderView(
                    allChapters: manga.chapters,
                    filteredChapters: manga.chapters != nil ? chapters : (initialDataLoaded ? [] : nil),
                    sortOption: $chapterSortOption,
                    sortAscending: $chapterSortAscending,
                    filters: $filters,
                    langFilter: $langFilter,
                    scanlatorFilter: $scanlatorFilter,
                    displayMode: $chapterTitleDisplayMode,
                    mangaUniqueKey: manga.uniqueKey
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }

            // separator
            if !chapters.isEmpty {
                ListDivider()
            }
        }
        .background(alignment: .top) {
            backdropView
                .ignoresSafeArea(edges: .top)
        }
        .animation(.default, value: animationTrigger)
        .animation(.default, value: readChapterCount)
        .animation(.default, value: descriptionExpanded)
        .foregroundStyle(.primary)
        .textCase(.none)
        .padding(.top, 10)
        .onChange(of: manga) { _ in
            animationTrigger.toggle()
            altTitles = NyoraAltTitleStore.shared.get(for: manga.key)
            rating = NyoraRatingStore.shared.get(for: manga.key)
            language = NyoraLanguageStore.shared.get(for: manga.key)
            loadCategories()
        }
        .onChange(of: bookmarked) { newValue in
            if newValue {
                loadCategories()
            } else {
                categoryNames = []
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("updateMangaCategories"))) { notification in
            if let info = notification.object as? MangaInfo {
                guard info.mangaId == manga.key, info.sourceId == manga.sourceKey else { return }
            }
            loadCategories()
        }
        .onChange(of: nextChapter) { _ in
            updateReadButtonText()
        }
        .onChange(of: readingInProgress) { _ in
            updateReadButtonText()
        }
        .onChange(of: allChaptersLocked) { _ in
            updateReadButtonText()
        }
        .onChange(of: allChaptersRead) { _ in
            updateReadButtonText()
        }
        .onChange(of: source != nil) { _ in
            updateReadButtonText()
        }
        .onReceive(NotificationCenter.default.publisher(for: .updateTrackers)) { _ in
            isTracking = TrackerManager.shared.isTracking(
                sourceId: manga.sourceKey,
                mangaId: manga.key
            )
        }
        .task {
            updateReadButtonText()
            altTitles = NyoraAltTitleStore.shared.get(for: manga.key)
            rating = NyoraRatingStore.shared.get(for: manga.key)
            language = NyoraLanguageStore.shared.get(for: manga.key)
            loadCategories()
            hasAvailableTrackers = await TrackerManager.shared.hasAvailableTrackers(sourceKey: manga.sourceKey, mangaKey: manga.key)
        }
    }

    // Blurred cover backdrop with a bottom gradient fade + stretch parallax on pull-down.
    // Mirrors nyora-android's imageView_blur_background + gradient_fade_bottom + ParallaxScrollListener.
    @ViewBuilder
    var backdropView: some View {
        if let cover = manga.cover, !cover.isEmpty {
            GeometryReader { geo in
                // minY relative to the enclosing list; >0 while the list is pulled down (overscroll)
                let minY = geo.frame(in: .named("mangaScroll")).minY
                let stretch = max(0, minY)
                let baseHeight: CGFloat = 300

                SourceImageView(
                    source: source,
                    imageUrl: cover,
                    contentMode: .fill
                )
                .frame(width: geo.size.width, height: baseHeight + stretch)
                .blur(radius: 12)
                .opacity(0.4)
                .clipped()
                .offset(y: -stretch)
                .overlay {
                    LinearGradient(
                        colors: [
                            Color(uiColor: .systemBackground).opacity(0),
                            Color(uiColor: .systemBackground).opacity(0.55),
                            Color(uiColor: .systemBackground)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .offset(y: -stretch)
                }
            }
            .frame(height: 300)
            .allowsHitTesting(false)
        }
    }

    // Reading progress bar + "Chapter X of Y" + read percentage, derived from history.
    // Mirrors nyora-android DetailsActivity.onHistoryChanged (chapter_d_of_d + percent_string_pattern + progress bar).
    @ViewBuilder
    var progressView: some View {
        let total = chapters.count
        let read = min(max(readChapterCount, 0), total)
        // only show when there is reading history and at least one chapter
        if total > 0 && (read > 0 || readingInProgress) {
            let fraction = total > 0 ? min(1, max(0, Double(read) / Double(total))) : 0
            let isCompleted = fraction >= 0.99999
            let percent = isCompleted ? 100 : Int(fraction * 100)
            let current = min(read + 1, total)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(String(format: NSLocalizedString("CHAPTER_X_OF_Y"), current, total))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(String(format: NSLocalizedString("PERCENT_READ_PATTERN"), percent))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .contentTransitionDisabledPlease()
                }
                ProgressView(value: fraction)
                    .tint(.accentColor)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
            .transition(.opacity)
        }
    }

    // Valid normalized rating (0...1) mapped to a 0...5 scale with one decimal, matching
    // nyora-android DetailsActivity textViewRatingValue (rating * 5).
    private var ratingText: String? {
        guard let rating, rating > 0, rating <= 1 else { return nil }
        return String(format: "%.1f", rating * 5)
    }

    // Translation language shown as an emoji flag + display name, mirroring
    // nyora-android DetailsActivity textViewTranslation (details.getLocale() + emoji flag).
    private var languageText: String? {
        guard let language, let name = NyoraLanguageStore.displayName(forLanguageCode: language) else {
            return nil
        }
        if let flag = NyoraLanguageStore.emojiFlag(forLanguageCode: language) {
            return "\(flag) \(name)"
        }
        return name
    }

    // Joined favourite-category names shown while the manga is in the library, mirroring
    // nyora-android DetailsActivity onFavoritesChanged (favourite category names on the library button).
    private var categoryLabelText: String? {
        guard bookmarked, !categoryNames.isEmpty else { return nil }
        return categoryNames.joined(separator: ", ")
    }

    @ViewBuilder
    var labelsView: some View {
        if ratingText != nil || languageText != nil || manga.status != .unknown || (manga.contentRating != .unknown && manga.contentRating != .safe) || (bookmarked && source != nil) || categoryLabelText != nil {
            HStack(spacing: 6) {
                if let ratingText {
                    LabelView(
                        text: ratingText,
                        systemImage: "star.fill",
                        background: .yellow.opacity(0.25)
                    )
                }
                if let languageText {
                    LabelView(text: languageText)
                }
                if manga.status != .unknown {
                    LabelView(text: manga.status.title)
                }
                if manga.contentRating != .unknown && manga.contentRating != .safe {
                    LabelView(
                        text: manga.contentRating.title,
                        background: manga.contentRating == .suggestive
                            ? .orange.opacity(0.3)
                            : .red.opacity(0.3)
                    )
                }
                if let categoryLabelText {
                    LabelView(
                        text: categoryLabelText,
                        systemImage: "folder.fill",
                        background: .accentColor.opacity(0.25)
                    )
                } else if let source, bookmarked {
                    LabelView(
                        text: source.name,
                        background: Color(red: 0.25, green: 0.55, blue: 1).opacity(0.3)
                    )
                }
            }
            .padding(.bottom, 8)
            .animation(.default, value: manga.status)
            .animation(.default, value: bookmarked)
            .animation(.default, value: rating)
            .animation(.default, value: language)
            .animation(.default, value: categoryNames)
        }
    }

    var buttonsView: some View {
        HStack(spacing: 8) {
            Button {
                // long holding also triggers a press on release, so cancel that
                if longHeldBookmark {
                    longHeldBookmark = false
                    return
                }
                if bookmarked && isTracking {
                    // show confirm prompt
                    showLibraryRemoveConfirm = true
                } else {
                    Task {
                        await toggleBookmarked()
                    }
                }
            } label: {
                Image(systemName: "bookmark.fill")
                    .scaleEffect(bookmarkScale)
            }
            .buttonStyle(MangaActionButtonStyle(selected: bookmarked))
            .simultaneousGesture(
                // on long hold, show category select
                LongPressGesture()
                    .onEnded { _ in
                        if
                            bookmarked,
                            !CoreDataManager.shared.getCategoryTitles(sorted: false).isEmpty
                        {
                            longHeldBookmark = true
                            path.present(
                                UINavigationController(
                                    rootViewController: CategorySelectViewController(
                                        manga: manga
                                    )
                                )
                            )
                        }
                    }
            )
            .alert(NSLocalizedString("REMOVE_FROM_LIBRARY_CONFIRM"), isPresented: $showLibraryRemoveConfirm) {
                Button(NSLocalizedString("CANCEL"), role: .cancel) {}
                Button(NSLocalizedString("REMOVE"), role: .destructive) {
                    guard bookmarked else { return }
                    Task {
                        await toggleBookmarked()
                    }
                }
            } message: {
                Text(NSLocalizedString("REMOVE_FROM_LIBRARY_CONFIRM_TEXT"))
            }

            if hasAvailableTrackers {
                Button {
                    onTrackerButtonPressed?()
                } label: {
                    Image(systemName: "clock.arrow.2.circlepath")
                }
                .buttonStyle(MangaActionButtonStyle(selected: isTracking))
            }

            if let url = manga.url {
                Button {
                    guard url.scheme == "http" || url.scheme == "https" else { return }
                    path.present(SFSafariViewController(url: url))
                } label: {
                    Image(systemName: "safari")
                }
                .buttonStyle(MangaActionButtonStyle())
                .transition(.opacity)
                .simultaneousGesture(
                    LongPressGesture()
                        .onEnded { finished in
                            if finished {
                                UIPasteboard.general.string = url.absoluteString
                                longHeldSafari = true
                            }
                        }
                )
                .alert(
                    NSLocalizedString("LINK_COPIED"),
                    isPresented: $longHeldSafari
                ) {
                    Button(NSLocalizedString("OK"), role: .cancel) {}
                } message: {
                    Text(NSLocalizedString("LINK_COPIED_TEXT"))
                }
            }
        }
    }

    @ViewBuilder
    var tagsView: some View {
        if let tags = manga.tags, !tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(manga.tags ?? [], id: \.self) { tag in
                        let label = TagView(text: tag)
                        if let source, let filter = source.matchingGenreFilter(for: tag) {
                            Button {
                                let viewController = MangaListViewController(source: source, title: tag)
                                viewController.getEntries = { page in
                                    try await source.getSearchMangaList(query: nil, page: page, filters: [
                                        filter
                                    ])
                                }
                                path.push(viewController)
                            } label: {
                                label
                            }
                        } else {
                            label
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 16)
        }
    }

    // Spring-scale pop + selection haptic when the library state changes, mirroring
    // nyora-android's animated favourite button feedback.
    private func playBookmarkFeedback() {
        UISelectionFeedbackGenerator().selectionChanged()
        bookmarkScale = 0.7
        withAnimation(.spring(response: 0.35, dampingFraction: 0.45)) {
            bookmarkScale = 1
        }
    }

    // Load the favourite-category titles for the current manga off the main actor.
    private func loadCategories() {
        let sourceId = manga.sourceKey
        let mangaId = manga.key
        Task {
            let names = await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.getCategories(
                    sourceId: sourceId,
                    mangaId: mangaId,
                    context: context
                )
                .sorted { $0.sort < $1.sort }
                .compactMap { $0.title }
            }
            await MainActor.run {
                guard manga.key == mangaId, manga.sourceKey == sourceId else { return }
                categoryNames = names
            }
        }
    }

    func toggleBookmarked() async {
        playBookmarkFeedback()
        let sourceId = manga.sourceKey
        let mangaId = manga.key
        let inLibrary = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.hasLibraryManga(
                sourceId: sourceId,
                mangaId: mangaId,
                context: context
            )
        }
        if inLibrary {
            // remove from library
            await MangaManager.shared.removeFromLibrary(
                sourceId: sourceId,
                mangaId: mangaId
            )
            bookmarked = false
        } else {
            if MangaManager.shouldAskForCategories() { // open category select view
                let viewController = UINavigationController(rootViewController: CategorySelectViewController(manga: manga))
                path.present(viewController)
            } else { // add to library
                bookmarked = true
                await MangaManager.shared.addToLibrary(
                    manga: manga,
                    chapters: manga.chapters ?? []
                )
            }
        }
    }

    func updateReadButtonText() {
        var title = ""
        if allChaptersLocked {
            title = NSLocalizedString("ALL_CHAPTERS_LOCKED", comment: "")
            readButtonDisabled = true
        } else if allChaptersRead {
            title = NSLocalizedString("ALL_CHAPTERS_READ", comment: "")
            readButtonDisabled = true
        } else if source == nil {
            title = NSLocalizedString("UNAVAILABLE", comment: "")
            readButtonDisabled = true
        } else {
            if let chapter = nextChapter {
                if !readingInProgress {
                    title = NSLocalizedString("START_READING", comment: "")
                } else {
                    title = NSLocalizedString("CONTINUE_READING", comment: "")
                }
                switch chapterTitleDisplayMode {
                    case .volume:
                        if let volumeNum = chapter.volumeNumber {
                            title += " " + String(format: NSLocalizedString("VOL_X"), volumeNum)
                        } else if let chapterNum = chapter.chapterNumber {
                            // Force display as volume if no volume number
                            title += " " + String(format: NSLocalizedString("VOL_X"), chapterNum)
                        }
                    case .chapter:
                        if let chapterNum = chapter.chapterNumber {
                            title += " " + String(format: NSLocalizedString("CH_X"), chapterNum)
                        } else if let volumeNum = chapter.volumeNumber {
                            // Force display as chapter if no chapter number
                            title += " " + String(format: NSLocalizedString("CH_X"), volumeNum)
                        }
                    case .default:
                        if let volumeNum = chapter.volumeNumber {
                            title += " " + String(format: NSLocalizedString("VOL_X"), volumeNum)
                        }
                        if let chapterNum = chapter.chapterNumber {
                            title += " " + String(format: NSLocalizedString("CH_X"), chapterNum)
                        }
                }
            } else {
                title = NSLocalizedString("NO_CHAPTERS_AVAILABLE", comment: "")
            }
            readButtonDisabled = false
        }
        readButtonText = title
    }
}

struct LabelView: View {
    let text: String
    var systemImage: String?
    var background = Color(UIColor.tertiarySystemFill)

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2)
            }
            Text(text)
        }
        .lineLimit(1)
        .foregroundStyle(.secondary)
        .font(.caption2)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct TagView: View {
    let text: String

    var body: some View {
        Text(text)
            .lineLimit(1)
            .foregroundStyle(.secondary)
            .font(.footnote)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .textSelection(.enabled)
            .background(Color(UIColor.tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 100))
    }
}

private struct MangaActionButtonStyle: ButtonStyle {
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
//        Group {
//            if selected {
//                configuration.label
//                    .foregroundStyle(.white)
//            } else {
//                configuration.label
//                    .foregroundStyle(.tint)
//            }
//        }
        configuration.label
            .foregroundStyle(selected ? Color.white : Color.accentColor)
            .opacity(configuration.isPressed ? 0.4 : 1)
            .font(.system(size: 16, weight: .semibold))
            .frame(width: 40, height: 32)
            .background(selected ? Color.accentColor : Color(UIColor.secondarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

@available(iOS 17.0, macOS 14.0, *)
#Preview {
    @Previewable @State var bookmarked = false
    @Previewable @State var chapterSortOption = ChapterSortOption.sourceOrder
    @Previewable @State var chapterSortAscending = false

    @Previewable @State var filters: [ChapterFilterOption] = []
    @Previewable @State var langFilter: String?
    @Previewable @State var scanlatorFilter: [String] = []
    @Previewable @State var chapterTitleDisplayMode = ChapterTitleDisplayMode.default

    MangaDetailsHeaderView(
        source: Binding.constant(AidokuRunner.Source.demo()),
        manga: Binding.constant(AidokuRunner.Manga(
            sourceKey: "",
            key: "",
            title: "Manga",
            authors: ["Author"],
            description: "Description"
        )),
        chapters: Binding.constant([]),
        nextChapter: Binding.constant(nil),
        readingInProgress: Binding.constant(false),
        readChapterCount: Binding.constant(0),
        allChaptersLocked: Binding.constant(false),
        allChaptersRead: Binding.constant(false),
        initialDataLoaded: Binding.constant(true),
        bookmarked: $bookmarked,
        coverPressed: Binding.constant(false),
        chapterSortOption: $chapterSortOption,
        chapterSortAscending: $chapterSortAscending,
        filters: $filters,
        langFilter: $langFilter,
        scanlatorFilter: $scanlatorFilter,
        descriptionExpanded: Binding.constant(false),
        chapterTitleDisplayMode: $chapterTitleDisplayMode,
        hasOtherDownloads: false,
    )
}
