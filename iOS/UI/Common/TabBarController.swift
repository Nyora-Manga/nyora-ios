//
//  TabBarController.swift
//  Aidoku
//
//  Created by Skitty on 7/26/25.
//

import Combine
import SwiftUI
import SwiftUIIntrospect

class TabBarController: UITabBarController {
    private var originalFrame: CGRect = .zero
    private var shrunkFrame: CGRect = .zero
    private var cancellables: [AnyCancellable] = []

    private var settingsPath: NavigationCoordinator?
    private var previousSelectedIndex: Int?
    private var enabledSections: [NavSection] = []

    private lazy var libraryProgressView = CircularProgressView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))

    /// Floating rounded "pill" backing for the tab bar on pre-iOS 26 (iOS 26 floats natively).
    private lazy var floatingTabPill: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
        view.isUserInteractionEnabled = false
        view.clipsToBounds = true
        view.layer.borderWidth = 1
        view.layer.borderColor = AccentColor.current.uiColor.withAlphaComponent(0.18).cgColor
        return view
    }()

    private lazy var libraryRefreshAccessory: UIView = {
        let view = UIView()

        let label = UILabel()
        label.text = NSLocalizedString("REFRESHING_LIBRARY")
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        libraryProgressView.radius = 12
        libraryProgressView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(libraryProgressView)

        if #unavailable(iOS 26) {
            // add styling for older versions without the bottom accessory view
            let backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
            backgroundView.layer.cornerRadius = 48 / 2
            backgroundView.layer.borderColor = UIColor.quaternarySystemFill.cgColor
            backgroundView.layer.borderWidth = 1
            backgroundView.clipsToBounds = true
            backgroundView.translatesAutoresizingMaskIntoConstraints = false
            view.insertSubview(backgroundView, at: 0)

            NSLayoutConstraint.activate([
                backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
                backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: libraryProgressView.leadingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.heightAnchor.constraint(equalToConstant: 48),

            libraryProgressView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            libraryProgressView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            libraryProgressView.widthAnchor.constraint(equalToConstant: 20),
            libraryProgressView.heightAnchor.constraint(equalToConstant: 20)
        ])

        return view
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        delegate = self

        // setUpTabs first: on iOS 26 the UITab items must exist before the tint /
        // appearance is applied, or the selected tab never picks up the accent.
        setUpTabs()
        configureFloatingTabBar()

        NotificationCenter.default.publisher(for: .incognitoMode)
            .sink { [weak self] _ in
                self?.updateFrame(animated: true)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .init(NavConfig.key))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setUpTabs()
            }
            .store(in: &cancellables)

        // Live-retint the tab bar when the accent preset changes.
        NotificationCenter.default.publisher(for: .accentColorChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.configureFloatingTabBar()
                self?.floatingTabPill.layer.borderColor =
                    AccentColor.current.uiColor.withAlphaComponent(0.18).cgColor
            }
            .store(in: &cancellables)
    }

    /// Nyora tab bar: indigo selected tint + Poppins labels, and (pre-iOS 26) a
    /// floating rounded pill backing so the bar reads as a detached capsule.
    private func configureFloatingTabBar() {
        let accent = AccentColor.current.uiColor
        tabBar.tintColor = accent
        tabBar.unselectedItemTintColor = .secondaryLabel
        // iOS 26 UITab / Liquid-Glass bars tint the selected item from the view's
        // tintColor, NOT the UITabBarItemAppearance below (ignored for UITab), so
        // set it explicitly or the accent never reaches the bottom bar.
        view.tintColor = accent

        let itemAppearance = UITabBarItemAppearance()
        for state in [itemAppearance.normal, itemAppearance.selected, itemAppearance.focused, itemAppearance.disabled] {
            state.titleTextAttributes = [.font: NyoraTheme.poppins(10, .medium)]
        }
        itemAppearance.selected.titleTextAttributes = [
            .font: NyoraTheme.poppins(10, .semibold),
            .foregroundColor: accent
        ]
        itemAppearance.selected.iconColor = accent
        itemAppearance.normal.iconColor = .secondaryLabel

        let appearance = UITabBarAppearance()
        if #available(iOS 26.0, *) {
            // Keep the native liquid-glass floating bar; only retint items.
            appearance.configureWithDefaultBackground()
        } else {
            // Transparent bar so our floating pill provides the surface.
            appearance.configureWithTransparentBackground()
            if floatingTabPill.superview == nil {
                tabBar.insertSubview(floatingTabPill, at: 0)
            }
        }
        appearance.stackedLayoutAppearance = itemAppearance
        appearance.inlineLayoutAppearance = itemAppearance
        appearance.compactInlineLayoutAppearance = itemAppearance

        tabBar.standardAppearance = appearance
        if #available(iOS 15.0, *) {
            tabBar.scrollEdgeAppearance = appearance
        }
    }

    private func layoutFloatingTabPill() {
        guard floatingTabPill.superview != nil else { return }
        let horizontalInset: CGFloat = 12
        let topInset: CGFloat = 6
        let bottomInset = max(view.safeAreaInsets.bottom - 8, 4)
        let frame = CGRect(
            x: horizontalInset,
            y: topInset,
            width: tabBar.bounds.width - horizontalInset * 2,
            height: tabBar.bounds.height - topInset - bottomInset
        )
        guard frame.width > 0, frame.height > 0 else { return }
        floatingTabPill.frame = frame
        floatingTabPill.layer.cornerRadius = min(frame.height / 2, NyoraTheme.cornerCard)
    }

    // swiftlint:disable:next function_body_length
    private func setUpTabs() {
        enabledSections = NavConfig.enabledSections

        // The tab bar shows at most 5 tabs; a 6th collapses the extras into a system "More"
        // overflow, whose navigation controller wraps the pushed Settings screen — which already
        // carries its own NavigationStack — producing two stacked nav bars (a double back button)
        // on Settings → Appearance. Keep Settings a direct top-level tab (never in "More") by
        // capping to 5, always preserving the required section(s).
        if enabledSections.count > 5 {
            let required = enabledSections.filter(\.isRequired)
            let others = enabledSections.filter { !$0.isRequired }
            let kept = Set(required + Array(others.prefix(max(0, 5 - required.count))))
            enabledSections = enabledSections.filter { kept.contains($0) }
        }

        let discoverPath = NavigationCoordinator(rootViewController: nil)
        let discoverHostingController = UIHostingController(rootView: NyoraAccentTint {
            DiscoverView()
                .environmentObject(discoverPath)
        })
        discoverPath.rootViewController = discoverHostingController
        let discoverViewController = NavigationController(rootViewController: discoverHostingController)

        let libraryViewController = NavigationController(rootViewController: LibraryViewController())
        let browseViewController = NavigationController(rootViewController: BrowseViewController())
        let searchViewController = NavigationController(rootViewController: SearchViewController())

        let historyPath = NavigationCoordinator(rootViewController: nil)
        let historyHostingController = UIHostingController(rootView: NyoraAccentTint {
            HistoryView()
                .environmentObject(historyPath)
        })
        historyPath.rootViewController = historyHostingController
        let historyViewController = NavigationController(rootViewController: historyHostingController)

        let settingsPath = NavigationCoordinator(rootViewController: nil)
        let settingsViewController: UIViewController
        if #available(iOS 26.0, *), UIDevice.current.userInterfaceIdiom != .pad {
            settingsViewController = UIHostingController(
                rootView: NyoraAccentTint {
                    NavigationStack {
                        SettingsView()
                            .environmentObject(settingsPath)
                    }.introspect(.navigationStack, on: .iOS(.v26, .v27)) { entity in
                        settingsPath.rootViewController = entity
                    }
                }
            )
        } else {
            // this breaks the zoom transitions from the toolbar buttons in the backups setting page on ios 18 / ipads
            let hosting = UIHostingController(rootView: NyoraAccentTint {
                SettingsView().environmentObject(settingsPath)
            })
            let entity = NavigationController(rootViewController: hosting)
            entity.navigationBar.prefersLargeTitles = true
            settingsPath.rootViewController = entity
            settingsViewController = entity
        }
        self.settingsPath = settingsPath

        discoverViewController.navigationBar.prefersLargeTitles = true
        libraryViewController.navigationBar.prefersLargeTitles = true
        browseViewController.navigationBar.prefersLargeTitles = true
        historyViewController.navigationBar.prefersLargeTitles = true
        searchViewController.navigationBar.prefersLargeTitles = true

        func viewController(for section: NavSection) -> UIViewController {
            switch section {
                case .discover: discoverViewController
                case .library: libraryViewController
                case .browse: browseViewController
                case .history: historyViewController
                case .search: searchViewController
                case .settings: settingsViewController
            }
        }

        if #available(iOS 26.0, *) {
            var newTabs: [UITab] = []
            for section in enabledSections {
                if section == .search {
                    let searchTab = UISearchTab { _ in searchViewController }
                    searchTab.automaticallyActivatesSearch = true
                    newTabs.append(searchTab)
                } else {
                    let tab = UITab(
                        title: section.title,
                        image: UIImage(systemName: section.systemImage),
                        identifier: section.rawValue
                    ) { _ in
                        viewController(for: section)
                    }
                    tab.allowsHiding = false
                    tab.preferredPlacement = .fixed
                    newTabs.append(tab)
                }
            }
            tabs = newTabs
        } else {
            viewControllers = enabledSections.enumerated().map { index, section in
                let vc = viewController(for: section)
                if section == .history {
                    vc.tabBarItem = UITabBarItem(tabBarSystemItem: .history, tag: index)
                } else if section == .search {
                    vc.tabBarItem = UITabBarItem(tabBarSystemItem: .search, tag: index)
                } else {
                    vc.tabBarItem = UITabBarItem(
                        title: section.title,
                        image: UIImage(systemName: section.systemImage),
                        tag: index
                    )
                }
                return vc
            }
        }

        let updateCount = UserDefaults.standard.integer(forKey: "Browse.updateCount")
        browseViewController.tabBarItem.badgeValue = updateCount > 0 ? String(updateCount) : nil
    }

    func updateFrame(animated: Bool = false) {
        if originalFrame == .zero {
            let bannerHeight = (UIApplication.shared.connectedScenes.first?.delegate as? SceneDelegate)?.totalBannerHeight ?? 0
            originalFrame = view.frame
            shrunkFrame = .init(
                x: originalFrame.origin.x,
                y: originalFrame.origin.y + bannerHeight,
                width: originalFrame.width,
                height: originalFrame.height - bannerHeight
            )
        }
        func commit() {
            if UserDefaults.standard.bool(forKey: "General.incognitoMode") {
                view.frame = shrunkFrame
            } else {
                view.frame = originalFrame
            }
        }
        if animated {
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                commit()
            }
        } else {
            commit()
        }
    }
}

extension TabBarController {
    func showLibraryRefreshView() {
        libraryProgressView.setProgress(value: 0, withAnimation: false)

        if #available(iOS 26.0, *) {
            setBottomAccessory(.init(contentView: libraryRefreshAccessory), animated: true)
        } else {
            libraryRefreshAccessory.layer.opacity = 0
            view.insertSubview(libraryRefreshAccessory, belowSubview: tabBar)
            UIView.animate(withDuration: 0.5) {
                self.libraryRefreshAccessory.layer.opacity = 1
            }
        }
    }

    func setLibraryRefreshProgress(_ progress: Float) {
        libraryProgressView.setProgress(value: progress, withAnimation: true)
    }

    func hideAccessoryView() {
        if #available(iOS 26.0, *) {
            setBottomAccessory(nil, animated: true)
        } else {
            UIView.animate(withDuration: 0.5) {
                self.libraryRefreshAccessory.layer.opacity = 0
            } completion: { _ in
                self.libraryRefreshAccessory.removeFromSuperview()
            }
        }
    }

    override func viewDidLayoutSubviews() {
        if #unavailable(iOS 26.0) {
            layoutFloatingTabPill()

            let height: CGFloat = 48
            let padding: CGFloat = 16

            libraryRefreshAccessory.frame = CGRect(
                x: tabBar.frame.origin.x + view.safeAreaInsets.left + padding,
                y: tabBar.frame.origin.y - height - padding / 2,
                width: tabBar.frame.width - padding * 2 - view.safeAreaInsets.left - view.safeAreaInsets.right,
                height: height
            )
        }
        updateFrame()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        originalFrame = .init(origin: self.originalFrame.origin, size: size)
        shrunkFrame = self.originalFrame
        coordinator.animate { _ in
            self.view.setNeedsLayout()
        } completion: { _ in
            let bannerHeight = (UIApplication.shared.connectedScenes.first?.delegate as? SceneDelegate)?.totalBannerHeight ?? 0
            self.shrunkFrame = .init(
                x: self.originalFrame.origin.x,
                y: self.originalFrame.origin.y + bannerHeight,
                width: self.originalFrame.width,
                height: self.originalFrame.height - bannerHeight
            )
            self.updateFrame(animated: true)
        }
    }
}

extension TabBarController: UITabBarControllerDelegate {
    @available(iOS 18.0, *)
    func tabBarController(_ tabBarController: UITabBarController, didSelectTab selectedTab: UITab, previousTab: UITab?) {
        checkForSettingsPop()
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        if #unavailable(iOS 18.0) {
            checkForSettingsPop()
        }
    }

    private func checkForSettingsPop() {
        guard let settingsIndex = enabledSections.firstIndex(of: .settings) else {
            previousSelectedIndex = selectedIndex
            return
        }
        if selectedIndex == previousSelectedIndex && previousSelectedIndex == settingsIndex {
            settingsPath?.navigationController?.popToRootViewController(animated: true)
        }
        previousSelectedIndex = selectedIndex
    }
}

// MARK: - Keyboard Shortcuts
extension TabBarController {
    override var keyCommands: [UIKeyCommand]? {
        tabBar.items?.enumerated().map { index, item in
            UIKeyCommand(
                title: item.title ?? "Tab \(index + 1)",
                action: #selector(selectTab),
                input: "\(index + 1)",
                modifierFlags: .shiftOrCommand,
                alternates: [],
                attributes: [],
                state: .off
            )
        }
    }

    @objc private func selectTab(sender: UIKeyCommand) {
        guard
            let input = sender.input,
            let newIndex = Int(input),
            newIndex >= 1 && newIndex <= (tabBar.items?.count ?? 0)
        else { return }
        selectedIndex = newIndex - 1
    }

    override var canBecomeFirstResponder: Bool { true }
}
