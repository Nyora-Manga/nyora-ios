//
//  ReaderPageViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/15/22.
//

import UIKit

class ReaderPageViewController: BaseObservingViewController {
    enum InfoPageType {
        case previous
        case next
    }

    enum PageType {
        case info(InfoPageType)
        case page
    }

    let type: PageType

    weak var delegate: ReaderHoldingDelegate?

    private var infoView: ReaderInfoPageView?
    private(set) var zoomView: ZoomableScrollView?
    private(set) var pageView: ReaderPageView?

    private lazy var reloadButton = {
        let reloadButton = UIButton(type: .roundedRect)
        reloadButton.isHidden = true
        reloadButton.setTitle(NSLocalizedString("RELOAD", comment: ""), for: .normal)
        reloadButton.addTarget(self, action: #selector(reload), for: .touchUpInside)
        reloadButton.configuration = .borderless()
        reloadButton.configuration?.contentInsets = .init(top: 15, leading: 15, bottom: 15, trailing: 15)
        reloadButton.translatesAutoresizingMaskIntoConstraints = false
        return reloadButton
    }()

    var currentChapter: Chapter? {
        get { infoView?.currentChapter }
        set { infoView?.currentChapter = newValue }
    }
    var previousChapter: Chapter? {
        get { infoView?.previousChapter }
        set { infoView?.previousChapter = newValue }
    }
    var nextChapter: Chapter? {
        get { infoView?.nextChapter }
        set { infoView?.nextChapter = newValue }
    }

    private var pageSet = false
    private var page: Page?
    private var sourceId: String?
    private var imageAspectRatio: CGFloat? // Aspect ratio of the image, > 1 means wide image
    private var pageBackground: PageBackground?

    // disable auto page background in double page controller
    var isInDoublePageController = false {
        didSet {
            loadPageBackground()
            zoomView?.zoomEnabled = !(isInDoublePageController)
        }
    }
    var doublePageRestorationConstraints: [NSLayoutConstraint] = []

    /// Callback when image aspect ratio is updated
    var onAspectRatioUpdated: (() -> Void)?

    /// Callback when image loading is complete and wide image status is determined
    var onImageisWideImage: ((Bool) -> Void)?

    init(type: PageType, delegate: ReaderHoldingDelegate?) {
        self.type = type
        self.delegate = delegate
        super.init()

        // need this so the page / chapters can be set before the rest of the views are loaded
        switch type {
            case .info(let infoPageType):
                infoView = ReaderInfoPageView(type: infoPageType == .previous ? .previous : .next)
            case .page:
                pageView = ReaderPageView(parent: self)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func configure() {
        switch type {
            case .info:
                // info view
                guard let infoView else { return }
                infoView.translatesAutoresizingMaskIntoConstraints = false
                view.addSubview(infoView)

            case .page:
                // zoom view
                let zoomView = ZoomableScrollView(frame: view.bounds)
                zoomView.translatesAutoresizingMaskIntoConstraints = false
                view.addSubview(zoomView)

                // page view
                guard let pageView else { return }
                pageView.translatesAutoresizingMaskIntoConstraints = false
                zoomView.addSubview(pageView)
                zoomView.zoomView = pageView
                // hide live text button when zoomed in
                zoomView.onZoomScaleChanged = { [weak self] scale in
                    self?.pageView?.setLiveTextHidden(scale != 1 || (self?.delegate?.barsHidden ?? false))
                }
                zoomView.doubleTapEnabled = !UserDefaults.standard.bool(forKey: "Reader.disableDoubleTap")
                view.addSubview(reloadButton)

                self.zoomView = zoomView
        }
    }

    override func constrain() {
        if let infoView {
            NSLayoutConstraint.activate([
                infoView.topAnchor.constraint(equalTo: view.topAnchor),
                infoView.leftAnchor.constraint(equalTo: view.leftAnchor),
                infoView.rightAnchor.constraint(equalTo: view.rightAnchor),
                infoView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        } else if let zoomView, let pageView {
            NSLayoutConstraint.activate([
                zoomView.topAnchor.constraint(equalTo: view.topAnchor),
                zoomView.leftAnchor.constraint(equalTo: view.leftAnchor),
                zoomView.rightAnchor.constraint(equalTo: view.rightAnchor),
                zoomView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

                pageView.widthAnchor.constraint(equalTo: zoomView.widthAnchor),
                pageView.heightAnchor.constraint(equalTo: zoomView.heightAnchor),

                reloadButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                reloadButton.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
        }
    }

    override func observe() {
        addObserver(forName: "Reader.backgroundColor") { [weak self] _ in
            self?.loadPageBackground()
        }
        addObserver(forName: "Reader.disableDoubleTap") { [weak self] notification in
            self?.zoomView?.doubleTapEnabled = !(notification.object as? Bool ?? UserDefaults.standard.bool(forKey: "Reader.disableDoubleTap"))
        }

        addObserver(forName: .orientationDidChange) { [weak self] _ in
            self?.loadPageBackground(forceReload: true)
            self?.applyZoomMode()
        }
        addObserver(forName: "Reader.zoomMode") { [weak self] _ in
            self?.applyZoomMode()
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        loadPageBackground() // fix page background resetting on system appearance change
    }

    func setPage(_ page: Page, sourceId: String? = nil, skipProcessing: Bool = false) {
        guard !pageSet, let pageView else { return }
        pageSet = true
        self.page = page
        self.sourceId = sourceId
        reloadButton.isHidden = true
        zoomView?.zoomEnabled = false
        Task {
            let result = await pageView.setPage(page, sourceId: sourceId, skipProcessing: skipProcessing)
            zoomView?.zoomEnabled = result && !isInDoublePageController
            reloadButton.isHidden = result

            // Update aspect ratio
            let oldAspectRatio = imageAspectRatio
            if result, let image = pageView.imageView.image {
                imageAspectRatio = image.size.width / image.size.height
            } else {
                imageAspectRatio = nil
            }

            // Notify if aspect ratio changed and became wide image
            if oldAspectRatio != imageAspectRatio && isWideImage {
                onAspectRatioUpdated?()
            }

            // Notify when image loading is complete with wide image status
            onImageisWideImage?(isWideImage)

            // determine page background color
            loadPageBackground()

            // apply the configured scale / zoom mode (fit-center/height/width/keep-start)
            applyZoomMode()
        }
    }

    /// Apply the reader's configured zoom/scale mode to the current page.
    /// Fit-center is the default (whole page visible). Fit-width/height scale the
    /// page so that dimension fills the screen and enable panning; keep-start acts
    /// like fit-width but anchored to the top of the page.
    func applyZoomMode() {
        guard
            let zoomView,
            let pageView,
            pageView.imageView.image != nil,
            !isInDoublePageController
        else { return }

        let mode = ReaderZoomMode.current

        // reset any previous baseline before recomputing
        zoomView.minimumZoomScale = 1

        guard mode != .fitCenter else {
            zoomView.setZoomScale(1, animated: false)
            return
        }

        zoomView.layoutIfNeeded()
        let bounds = zoomView.bounds.size
        let displayed = pageView.imageView.bounds.size
        guard
            bounds.width > 0, bounds.height > 0,
            displayed.width > 0, displayed.height > 0
        else { return }

        let fitWidthScale = bounds.width / displayed.width
        let fitHeightScale = bounds.height / displayed.height

        let target: CGFloat
        switch mode {
            case .fitWidth, .keepStart: target = fitWidthScale
            case .fitHeight: target = fitHeightScale
            case .fitCenter: target = 1
        }

        let clamped = min(max(target, 1), zoomView.maximumZoomScale)
        guard clamped > 1.001 else {
            zoomView.setZoomScale(1, animated: false)
            return
        }

        zoomView.minimumZoomScale = clamped
        zoomView.setZoomScale(clamped, animated: false)
        zoomView.layoutIfNeeded()

        // position the viewport for the mode
        let content = zoomView.contentSize
        switch mode {
            case .fitWidth, .keepStart:
                // top of the page, horizontally centered
                zoomView.contentOffset = CGPoint(
                    x: max(0, (content.width - bounds.width) / 2),
                    y: 0
                )
            case .fitHeight:
                // leading edge, vertically centered
                zoomView.contentOffset = CGPoint(
                    x: 0,
                    y: max(0, (content.height - bounds.height) / 2)
                )
            case .fitCenter:
                break
        }
    }

    func loadPageBackground(forceReload: Bool = false) {
        // ensure no old gradients are left
        view.layer.sublayers?.removeAll(where: { $0 is CAGradientLayer })

        if
            UserDefaults.standard.string(forKey: "Reader.backgroundColor") == "auto",
            !isInDoublePageController,
            pageBackground != nil || pageView?.imageView.image != nil
        {
            let background = if !forceReload, let pageBackground {
                pageBackground
            } else if let image = pageView?.imageView.image {
                PageBackground.choose(for: image, isLandscape: {
                    let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
                    let orientation = if #available(iOS 16.0, *) {
                        scene?.effectiveGeometry.interfaceOrientation
                    } else {
                        scene?.interfaceOrientation
                    }
                    return orientation?.isLandscape ?? false
                }())
            } else {
                PageBackground.color(.clear)
            }
            pageBackground = background
            switch background {
                case .color(let color):
                    view.backgroundColor = color
                case .gradient(let gradient):
                    gradient.frame = view.bounds
                    view.layer.insertSublayer(gradient, at: 0)
            }
        } else {
            view.backgroundColor = nil
        }
    }

    @objc func reload() {
        guard let page else { return }
        pageSet = false
        reloadButton.isHidden = true
        pageView?.progressView.setProgress(value: 0, withAnimation: false)
        pageView?.progressView.isHidden = false
        setPage(page, sourceId: sourceId)
    }

    func clearPage() {
        pageSet = false
        pageView?.imageView.image = nil
        zoomView?.zoomEnabled = false
        imageAspectRatio = nil
    }

    /// Check if this is a wide image (aspect ratio > 1)
    var isWideImage: Bool {
        guard let imageAspectRatio else { return false }
        return imageAspectRatio > 1
    }
}
