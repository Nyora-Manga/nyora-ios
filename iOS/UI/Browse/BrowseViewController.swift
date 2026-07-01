//
//  BrowseViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/23/22.
//

import AidokuRunner
import SafariServices
import SwiftUI

class BrowseViewController: BaseTableViewController {
    let viewModel = BrowseViewModel()

    private lazy var dataSource = makeDataSource()

    private lazy var refreshControl = UIRefreshControl()
    private lazy var emptyStackView = EmptyPageStackView()
    private lazy var searchHeroView = NyoraSearchHeroView()

    // Nyora Explore header: search-hero pill stacked over a 2×2 quick-actions card.
    private let headerContainer = UIView()
    private static let quickActionsHeight: CGFloat = 178
    private lazy var quickActionsHost: UIHostingController<QuickActionsCard> = {
        let card = QuickActionsCard(
            onLocal: { [weak self] in self?.openLocalSource() },
            onBookmarks: { [weak self] in self?.openBookmarks() },
            onRandom: { [weak self] in self?.openRandomSource() },
            onDownloads: { [weak self] in self?.openDownloads() }
        )
        let host = UIHostingController(rootView: card)
        host.view.backgroundColor = .clear
        return host
    }()

    override var tableViewStyle: UITableView.Style {
        .grouped
    }

    override func configure() {
        super.configure()

        title = NSLocalizedString("BROWSE", comment: "")

        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.hidesSearchBarWhenScrolling = false

        // search controller
        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = searchController

        // Nyora search-hero pill: a large tinted pill card that opens the search field.
        searchHeroView.onTap = { [weak self] in
            self?.navigationItem.searchController?.searchBar.becomeFirstResponder()
        }

        // toolbar buttons
        let deleteButton = UIBarButtonItem(
            title: nil,
            style: .plain,
            target: self,
            action: #selector(deleteSelected)
        )
        deleteButton.image = UIImage(systemName: "trash")
        if #unavailable(iOS 26.0) {
            deleteButton.tintColor = .systemRed
        }
        toolbarItems = [
            deleteButton,
            UIBarButtonItem(systemItem: .flexibleSpace)
        ]

        updateNavbar()
        updateToolbar()

        // configure table view
        tableView.dataSource = dataSource
        tableView.register(
            SourceTableViewCell.self,
            forCellReuseIdentifier: String(describing: SourceTableViewCell.self)
        )
        tableView.register(
            UITableViewHeaderFooterView.self,
            forHeaderFooterViewReuseIdentifier: String(describing: UITableViewHeaderFooterView.self)
        )
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        tableView.sectionFooterHeight = 8
        tableView.separatorStyle = .none
        tableView.backgroundColor = .systemBackground
        tableView.keyboardDismissMode = .onDrag
        tableView.allowsMultipleSelectionDuringEditing = true

        refreshControl.addTarget(self, action: #selector(refreshSourceLists(_:)), for: .valueChanged)
        tableView.refreshControl = refreshControl

        // install the combined header (search-hero + quick-actions), sized in viewDidLayoutSubviews
        addChild(quickActionsHost)
        headerContainer.addSubview(searchHeroView)
        headerContainer.addSubview(quickActionsHost.view)
        quickActionsHost.didMove(toParent: self)
        tableView.tableHeaderView = headerContainer

        // empty text
        emptyStackView.imageSystemName = "globe"
        emptyStackView.title = NSLocalizedString("BROWSE_NO_SOURCES", comment: "")
        emptyStackView.text = NSLocalizedString("BROWSE_NO_SOURCES_TEXT_NEW", comment: "")
        emptyStackView.buttonText = NSLocalizedString("ADDING_SOURCES_GUIDE_BUTTON", comment: "")
        emptyStackView.addButtonTarget(self, action: #selector(openGuidePage))
        emptyStackView.showsButton = true
        emptyStackView.isHidden = true
        emptyStackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyStackView)

        // load data
        Task {
            await viewModel.loadInstalledSources()
            await viewModel.loadPinnedSources()
            updateDataSource()
            await viewModel.loadExternalSources()
            viewModel.loadUpdates()
            updateDataSource()

            if viewModel.hasLegacySourceList && !UserDefaults.standard.bool(forKey: "Flag.showedLegacySourceListNotice") {
                showLegacySourceListNotice()
                UserDefaults.standard.set(true, forKey: "Flag.showedLegacySourceListNotice")
            }
        }
    }

    override func constrain() {
        super.constrain()

        NSLayoutConstraint.activate([
            emptyStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStackView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    override func observe() {
        // source installed/imported/pinned
        addObserver(forName: .updateSourceList) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.viewModel.loadInstalledSources()
                await self.viewModel.loadPinnedSources()
                self.viewModel.loadUpdates()
                if let query = self.navigationItem.searchController?.searchBar.text, !query.isEmpty {
                    self.viewModel.search(query: query)
                }
                self.updateDataSource()
            }
        }
        // source lists added/removed
        addObserver(forName: .updateSourceLists) { [weak self] _ in
            guard let self = self else { return }
            Task {
                await self.viewModel.loadExternalSources()
                self.viewModel.loadUpdates()
                self.updateDataSource()
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        dataSource.onReorder = { [weak self] snapshot in
            guard let self = self else { return }
            let sourceList = snapshot.itemIdentifiers(inSection: .pinned).map { $0.sourceId }
            UserDefaults.standard.set(sourceList, forKey: "Browse.pinnedList")

            if sourceList.isEmpty { self.stopEditing() }
            Task { @MainActor in
                await self.viewModel.loadInstalledSources()
                await self.viewModel.loadPinnedSources()
                self.updateDataSource()
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Size the combined header (search-hero pill + 2×2 quick-actions card) to the table width.
        guard tableView.tableHeaderView === headerContainer else { return }
        let width = tableView.bounds.width
        let searchHeight = NyoraSearchHeroView.preferredHeight
        let totalHeight = searchHeight + Self.quickActionsHeight
        let targetSize = CGSize(width: width, height: totalHeight)
        if headerContainer.frame.size != targetSize {
            headerContainer.frame = CGRect(origin: .zero, size: targetSize)
            searchHeroView.frame = CGRect(x: 0, y: 0, width: width, height: searchHeight)
            quickActionsHost.view.frame = CGRect(x: 0, y: searchHeight, width: width, height: Self.quickActionsHeight)
            tableView.tableHeaderView = headerContainer
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isToolbarHidden = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // fix refresh control snapping height
        refreshControl.didMoveToSuperview()

        // hack to show search bar on initial presentation
        if !navigationItem.hidesSearchBarWhenScrolling {
            navigationItem.hidesSearchBarWhenScrolling = true
        }
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        tableView.setEditing(editing, animated: animated)
        updateNavbar()
        updateToolbar()
    }
}

extension BrowseViewController {
    func uninstall(sources: [AidokuRunner.Source]) {
        let containsLocalSource = sources.contains(where: { $0.id == LocalSourceRunner.sourceKey })

        func commit() {
            for source in sources {
                SourceManager.shared.remove(source: source)
            }
            Task {
                await self.viewModel.loadInstalledSources()
                self.updateDataSource()
                self.setEditing(false, animated: true)
            }
        }

        if containsLocalSource {
            self.presentAlert(
                title: NSLocalizedString("REMOVE_LOCAL_SOURCE"),
                message: NSLocalizedString("REMOVE_LOCAL_SOURCE_TEXT"),
                actions: [
                    UIAlertAction(title: NSLocalizedString("CANCEL"), style: .cancel),
                    UIAlertAction(title: NSLocalizedString("OK"), style: .default) { _ in
                        Task {
                            await LocalFileManager.shared.removeAllLocalFiles()
                        }
                        commit()
                    }
                ]
            )
        } else {
            commit()
        }
    }

    // store update count and display badge
    func checkUpdateCount() {
        let updateCount = viewModel.updatesSources.count
        UserDefaults.standard.set(updateCount, forKey: "Browse.updateCount")
        let tabBarItem = tabBarController?.tabBar.items?.first(
            where: { $0.title == NSLocalizedString("BROWSE", comment: "") }
        )
        tabBarItem?.badgeValue = updateCount > 0 ? String(updateCount) : nil
    }

    func showLegacySourceListNotice() {
        let alert = UIAlertController(
            title: NSLocalizedString("LEGACY_SOURCE_LIST_WARNING"),
            message: NSLocalizedString("LEGACY_SOURCE_LIST_WARNING_INFO"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK"), style: .cancel) { _ in })
        present(alert, animated: true)
    }

    @objc func refreshSourceLists(_ refreshControl: UIRefreshControl? = nil) {
        Task {
            await viewModel.loadExternalSources(reload: true)
            self.viewModel.loadUpdates()
            updateExternalSources()
            refreshControl?.endRefreshing()
        }
    }

    @objc func openGuidePage() {
        let safariViewController = SFSafariViewController(
            url: URL(string: "https://aidoku.app/help/guides/getting-started/#installing-a-source")!
        )
        present(safariViewController, animated: true)
    }

    @objc func openMigrateSourcePage() {
        let viewController = SwiftUINavigationViewController(rootView: MigrateSourcesView())
        if #available(iOS 26.0, *) {
            viewController.preferredTransition = .zoom { _ in
                self.navigationItem.rightBarButtonItems?.last
            }
        }
        viewController.modalPresentationStyle = .pageSheet
        present(viewController, animated: true)
    }

    @objc func openAddSourcePage() {
        let path = NavigationCoordinator(rootViewController: self)
        let hostingController = UIHostingController(
            rootView: AddSourceView(externalSources: viewModel.unfilteredExternalSources)
                .ignoresSafeArea() // fixes some weird keyboard clipping stuff
                .environmentObject(path)
        )
        path.rootViewController = hostingController
        if #available(iOS 26.0, *) {
            hostingController.preferredTransition = .zoom { _ in
                self.navigationItem.rightBarButtonItems?.first
            }
        }
        hostingController.modalPresentationStyle = .pageSheet
        present(hostingController, animated: true)
    }

    @objc func stopEditing() {
        setEditing(false, animated: true)
    }

    // MARK: - Quick actions (Nyora Explore 2×2 card)

    private func push(source: AidokuRunner.Source) {
        let vc: UIViewController = if let legacySource = source.legacySource {
            SourceViewController(source: legacySource)
        } else {
            NewSourceViewController(source: source)
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    /// Local: open the local source; fall back to the add-source page if it isn't installed.
    func openLocalSource() {
        if let source = SourceManager.shared.source(for: LocalSourceRunner.sourceKey) {
            push(source: source)
        } else {
            openAddSourcePage()
        }
    }

    /// Bookmarks: jump to the saved library (Favourites) tab.
    func openBookmarks() {
        guard let tabBarController else { return }
        let target = tabBarController.viewControllers?.first { vc in
            (vc as? UINavigationController)?.viewControllers.first is LibraryViewController
        }
        if let target {
            tabBarController.selectedViewController = target
        }
    }

    /// Random: open a random installed source (excluding the local source).
    func openRandomSource() {
        let candidates = SourceManager.shared.sources.filter { $0.id != LocalSourceRunner.sourceKey }
        guard let source = candidates.randomElement() else { return }
        push(source: source)
    }

    /// Downloads: present the download queue.
    func openDownloads() {
        let hosting = UIHostingController(rootView: DownloadQueueView())
        hosting.navigationItem.largeTitleDisplayMode = .never
        hosting.navigationItem.title = NSLocalizedString("DOWNLOAD_QUEUE")
        let nav = UINavigationController(rootViewController: hosting)
        present(nav, animated: true)
    }

    @objc func deleteSelected() {
        confirmAction(
            continueActionName: NSLocalizedString("UNINSTALL"),
            sourceItem: toolbarItems?.first
        ) {
            let sources = self.tableView.indexPathsForSelectedRows?.compactMap { (path: IndexPath) -> AidokuRunner.Source? in
                guard let info = self.dataSource.itemIdentifier(for: path) else { return nil }
                return SourceManager.shared.source(for: info.sourceId)
            } ?? []
            self.uninstall(sources: sources)
        }
    }
}

// MARK: - Table View Delegate
extension BrowseViewController {
    // support two finger drag to select
    func tableView(_ tableView: UITableView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
        true
    }

    func tableView(_ tableView: UITableView, didBeginMultipleSelectionInteractionAt indexPath: IndexPath) {
        setEditing(true, animated: true)
    }

    func tableView(_ tableView: UITableView, didHighlightRowAt indexPath: IndexPath) {
        guard let cell = tableView.cellForRow(at: indexPath) else { return }
        if isEditing {
            // fix double selection animation when editing
            cell.setHighlighted(false, animated: false)
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let sectionId = dataSource.sectionIdentifier(for: indexPath.section)
        guard !isEditing else {
            if sectionId != .pinned && sectionId != .installed {
                tableView.deselectRow(at: indexPath, animated: false)
            } else {
                updateToolbar()
            }
            return
        }
        if
            sectionId == .installed || sectionId == .pinned,
            let info = dataSource.itemIdentifier(for: indexPath),
            let source = SourceManager.shared.source(for: info.sourceId)
        {
            let vc: UIViewController = if let legacySource = source.legacySource {
                SourceViewController(source: legacySource)
            } else {
                NewSourceViewController(source: source)
            }
            navigationController?.pushViewController(vc, animated: true)
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        if isEditing {
            updateToolbar()
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard
            let cell = tableView.dequeueReusableHeaderFooterView(
                withIdentifier: String(describing: UITableViewHeaderFooterView.self)
            ),
            let currentSection = dataSource.sectionIdentifier(for: section)
        else {
            return nil
        }
        var config = SmallSectionHeaderConfiguration()
        switch currentSection {
            case .updates:
                config.title = NSLocalizedString("UPDATES")
            case .pinned:
                config.title = NSLocalizedString("PINNED")
            case .installed:
                config.title = NSLocalizedString("INSTALLED")
            case .external:
                config.title = NSLocalizedString("EXTERNAL")
        }
        cell.contentConfiguration = config
        return cell
    }

    func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard
            !tableView.isEditing, // do not allow context menu when the sources are being edited
            case let section = dataSource.sectionIdentifier(for: indexPath.section),
            section == .installed || section == .pinned,
            let info = dataSource.itemIdentifier(for: indexPath),
            let source = SourceManager.shared.source(for: info.sourceId)
        else {
            return nil
        }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ -> UIMenu? in
            let editAction = UIMenu(title: "", options: .displayInline, children: [
                UIAction(
                    title: section == .pinned ? NSLocalizedString("REORDER") : NSLocalizedString("EDIT_SOURCES"),
                    image: UIImage(systemName: section == .pinned ? "shuffle" : "minus.circle")
                ) { _ in
                    self.setEditing(true, animated: true)
                }
            ])

            let pinAction = UIAction(
                title: section == .pinned ? NSLocalizedString("UNPIN") : NSLocalizedString("PIN"),
                image: UIImage(systemName: section == .pinned ? "pin.slash" : "pin")
            ) { _ in
                if section == .pinned {
                    SourceManager.shared.unpin(source: source)
                } else {
                    SourceManager.shared.pin(source: source)
                }
                Task {
                    await self.viewModel.loadPinnedSources()
                    self.updateDataSource()
                }
            }

            let uninstallAction = UIAction(
                title: NSLocalizedString("UNINSTALL"),
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { _ in
                self.uninstall(sources: [source])
            }

            return UIMenu(title: "", children: [
                editAction,
                pinAction,
                uninstallAction
            ])
        }
    }
}

// MARK: - Data Source
extension BrowseViewController {
    enum Section: Int {
        case pinned
        case updates
        case installed
        case external
    }

    // Ability to edit tableview for a diffable data source.
    // Changing data in a diffable data source requires its seperate tableview override which can't be done with the view's tableview delegate.
    class SourceCellDataSource: UITableViewDiffableDataSource<Section, SourceInfo2> {
        // Used for callback when cells are reordered in the pinned section.
        var onReorder: ((NSDiffableDataSourceSnapshot<Section, SourceInfo2>) -> Void)?
        // Let the rows in the Pinned section be reordered (used for reordering sources)
        override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
            sectionIdentifier(for: indexPath.section) == .pinned
        }

        // Move a selected source row from pinned section to a destination index.
        override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
            guard
                let sourceItem = itemIdentifier(for: sourceIndexPath),
                sourceIndexPath != destinationIndexPath
            else { return }

            let destinationItem = itemIdentifier(for: destinationIndexPath)

            var snapshot = self.snapshot()

            if
                let destinationItem = destinationItem,
                let sourceIndex = snapshot.indexOfItem(sourceItem),
                let destinationIndex = snapshot.indexOfItem(destinationItem)
            {
                snapshot.deleteItems([sourceItem])

                if destinationIndex > sourceIndex {
                    snapshot.insertItems([sourceItem], afterItem: destinationItem)
                } else {
                    snapshot.insertItems([sourceItem], beforeItem: destinationItem)
                }
            }
            // Save the order and notify the observer to reload table.
            apply(snapshot, animatingDifferences: false)
            onReorder?(snapshot)
        }

        override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
            let identifier = sectionIdentifier(for: indexPath.section)
            return identifier == .pinned || identifier == .installed
        }
    }

    private func makeDataSource() -> SourceCellDataSource {
        // Use subclass of UITableViewDiffableDataSource to add tableview overrides.
        SourceCellDataSource(tableView: tableView) { [weak self] tableView, indexPath, info in
            guard
                let self = self,
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: String(describing: SourceTableViewCell.self)
                ) as? SourceTableViewCell,
                let section = self.dataSource.sectionIdentifier(for: indexPath.section)
            else {
                return UITableViewCell()
            }

            cell.delegate = self
            cell.setSourceInfo(info, showButton: section == .updates)

            if section == .updates {
                cell.buttonTitle = NSLocalizedString("BUTTON_UPDATE")
                cell.selectionStyle = .none
                cell.accessoryType = .none
            } else {
                cell.selectionStyle = .default
                cell.accessoryType = .disclosureIndicator
            }
            return cell
        }
    }

    func updateDataSource() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, SourceInfo2>()

        if !viewModel.updatesSources.isEmpty {
            snapshot.appendSections([.updates])
            snapshot.appendItems(viewModel.updatesSources, toSection: .updates)
        }
        if !viewModel.pinnedSources.isEmpty {
            snapshot.appendSections([.pinned])
            snapshot.appendItems(viewModel.pinnedSources, toSection: .pinned)
        }
        if !viewModel.installedSources.isEmpty {
            snapshot.appendSections([.installed])
            snapshot.appendItems(viewModel.installedSources, toSection: .installed)
        }
//        if !viewModel.externalSources.isEmpty {
//            snapshot.appendSections([.external])
//            snapshot.appendItems(viewModel.externalSources, toSection: .external)
//        }

        dataSource.apply(snapshot)

        Task { @MainActor in
            if navigationItem.searchController?.searchBar.text?.isEmpty ?? true {
                emptyStackView.isHidden = !snapshot.itemIdentifiers.isEmpty
            }
            checkUpdateCount()
        }
    }

    func updateExternalSources() {
        var snapshot = dataSource.snapshot()

        snapshot.deleteSections([.updates, .external])
        if !viewModel.updatesSources.isEmpty {
            if snapshot.indexOfSection(.installed) != nil {
                snapshot.insertSections([.updates], beforeSection: .installed)
            } else {
                snapshot.appendSections([.updates])
            }
            snapshot.appendItems(viewModel.updatesSources, toSection: .updates)
        }
//        if !viewModel.externalSources.isEmpty {
//            snapshot.appendSections([.external])
//            snapshot.appendItems(viewModel.externalSources, toSection: .external)
//        }

        if #available(iOS 15.0, *) {
            // prevents jumpiness from pull to refresh
            dataSource.applySnapshotUsingReloadData(snapshot)
        } else {
            dataSource.apply(snapshot)
        }

        Task { @MainActor in
            emptyStackView.isHidden = !snapshot.itemIdentifiers.isEmpty
            checkUpdateCount()
        }
    }
}

// MARK: - Search Results
extension BrowseViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        viewModel.search(query: searchController.searchBar.text)
        updateDataSource()
    }
}

extension BrowseViewController {
    func updateNavbar(isEditing: Bool? = nil) {
        let isEditing = isEditing ?? self.isEditing
        if isEditing {
            navigationItem.rightBarButtonItems = [UIBarButtonItem(
                barButtonSystemItem: .done,
                target: self,
                action: #selector(stopEditing)
            )]
        } else {
            let addSourceBarButton = UIBarButtonItem(
                image: UIImage(systemName: "plus"),
                style: .plain,
                target: self,
                action: #selector(openAddSourcePage)
            )
            addSourceBarButton.title = NSLocalizedString("ADD_SOURCE")
            if #available(iOS 26.0, *) {
                addSourceBarButton.sharesBackground = false
            }

            let migrateSourcesBarButton = UIBarButtonItem(
                image: UIImage(systemName: "arrow.left.arrow.right"),
                style: .plain,
                target: self,
                action: #selector(openMigrateSourcePage)
            )
            migrateSourcesBarButton.title = NSLocalizedString("MIGRATE_SOURCES")
            if #available(iOS 26.0, *) {
                migrateSourcesBarButton.sharesBackground = false
            }

            navigationItem.rightBarButtonItems = [
                addSourceBarButton,
                migrateSourcesBarButton
            ]
        }
    }

    func updateToolbar(isEditing: Bool? = nil) {
        let isEditing = isEditing ?? self.isEditing
        if isEditing {
            // show toolbar
            if navigationController?.isToolbarHidden ?? false {
                UIView.animate(withDuration: CATransaction.animationDuration()) {
                    self.navigationController?.isToolbarHidden = false
                    self.navigationController?.toolbar.alpha = 1
                    if #available(iOS 26.0, *) {
                        // hide tab bar on iOS 26 (it covers the toolbar)
                        self.tabBarController?.isTabBarHidden = true
                    }
                }
            }
            // enable items
            let hasSelectedItems = !(tableView.indexPathsForSelectedRows?.isEmpty ?? true)
            toolbarItems?.first?.isEnabled = hasSelectedItems
        } else if !(self.navigationController?.isToolbarHidden ?? true) {
            // fade out toolbar
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                self.navigationController?.toolbar.alpha = 0
                if #available(iOS 26.0, *) {
                    // reshow tab bar on iOS 26
                    self.tabBarController?.isTabBarHidden = false
                }
            } completion: { _ in
                self.navigationController?.isToolbarHidden = true
            }
        }
    }
}

extension BrowseViewController: SourceCellDelegate {
    func getButtonPressed(cell: SourceTableViewCell) {
        guard
            let externalInfo = cell.info?.externalInfo,
            let url = externalInfo.fileURL
        else {
            cell.getButton.buttonState = .fail
            return
        }
        cell.getButton.buttonState = .downloading
        Task {
            let installedSource = await SourceManager.shared.importSource(from: url)
            cell.getButton.buttonState = installedSource == nil ? .fail : .get
        }
    }

    func warningButtonPressed(cell: SourceTableViewCell) {
        let alert = UIAlertController(
            title: NSLocalizedString("MISSING_SOURCE_LIST"),
            message: NSLocalizedString("MISSING_SOURCE_LIST_INFO"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK"), style: .cancel) { _ in })
        present(alert, animated: true)
    }
}
