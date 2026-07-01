//
//  MangaGridCell.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 7/24/22.
//

import AidokuRunner
import Gifu
import Nuke
import UIKit

class MangaGridCell: UICollectionViewCell {
    var identifier: MangaIdentifier?

    var title: String? {
        get {
            titleLabel.text
        }
        set {
            titleLabel.text = newValue ?? NSLocalizedString("UNTITLED")
        }
    }

    var showsBookmark: Bool {
        get {
            !bookmarkView.isHidden
        }
        set {
            bookmarkView.isHidden = !newValue
        }
    }

    var badgeNumber: Int {
        get { badgeView.badgeNumber }
        set { badgeView.badgeNumber = newValue }
    }
    var badgeNumber2: Int {
        get { badgeView.badgeNumber2 }
        set { badgeView.badgeNumber2 = newValue }
    }

    let imageView = GIFImageView()
    private let titleLabel = UILabel()
    private let overlayView = UIView()
    private let gradient = CAGradientLayer()

    private lazy var badgeView = DoubleBadgeView()

    private let bookmarkView = UIImageView()
    private let highlightView = UIView()

    private lazy var progressBadge: UILabel = {
        let label = PaddedLabel()
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .white
        label.backgroundColor = UIColor(white: 0, alpha: 0.55)
        label.layer.cornerRadius = 8
        label.layer.masksToBounds = true
        label.textAlignment = .center
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // Bottom reading-progress bar overlay (nyora-android library cover style).
    private lazy var progressBarTrack: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(white: 0, alpha: 0.35)
        view.clipsToBounds = true
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var progressBarFill: UIView = {
        let view = UIView()
        view.backgroundColor = NyoraTheme.indigo
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var progressBarFillWidth: NSLayoutConstraint?

    private var progressTaskId: MangaIdentifier?

    private var url: String?
    private var imageTask: ImageTask?
    var isEditing = false

    // shadow shown when in selection mode
    private lazy var shadowOverlayView: UIView = {
        let shadowOverlayView = UIView()
        shadowOverlayView.alpha = 0
        shadowOverlayView.backgroundColor = UIColor(white: 0, alpha: 0.5)
        shadowOverlayView.layer.cornerRadius = layer.cornerRadius
        shadowOverlayView.translatesAutoresizingMaskIntoConstraints = false
        return shadowOverlayView
    }()

    private lazy var selectionView = SelectionCheckView(style: .bordered)

    private var badgeConstraints: [NSLayoutConstraint] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
        constrain()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {
        contentView.clipsToBounds = true
        contentView.layer.cornerRadius = 5
        contentView.layer.borderWidth = 1
        contentView.layer.borderColor = UIColor.quaternarySystemFill.cgColor

        imageView.image = UIImage(named: "MangaPlaceholder")
        imageView.contentMode = .scaleAspectFill
        contentView.addSubview(imageView)

        gradient.frame = bounds
        gradient.locations = [0.6, 1]
        gradient.colors = [
            UIColor(white: 0, alpha: 0).cgColor,
            UIColor(white: 0, alpha: 0.7).cgColor
        ]
        gradient.cornerRadius = layer.cornerRadius
        gradient.needsDisplayOnBoundsChange = true

        overlayView.layer.insertSublayer(gradient, at: 0)
        overlayView.layer.cornerRadius = layer.cornerRadius
        contentView.addSubview(overlayView)

        progressBarTrack.addSubview(progressBarFill)
        contentView.addSubview(progressBarTrack)

        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        contentView.addSubview(titleLabel)

        contentView.addSubview(badgeView)

        bookmarkView.isHidden = true
        bookmarkView.image = UIImage(named: "bookmark")
        bookmarkView.contentMode = .scaleAspectFit
        contentView.addSubview(bookmarkView)

        highlightView.alpha = 0
        highlightView.backgroundColor = UIColor(white: 0, alpha: 0.5)
        highlightView.layer.cornerRadius = layer.cornerRadius
        contentView.addSubview(highlightView)

        selectionView.isHidden = true

        contentView.addSubview(progressBadge)

        contentView.addSubview(shadowOverlayView)
        contentView.addSubview(selectionView)
    }

    func constrain() {
        imageView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        bookmarkView.translatesAutoresizingMaskIntoConstraints = false
        highlightView.translatesAutoresizingMaskIntoConstraints = false
        selectionView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            overlayView.topAnchor.constraint(equalTo: contentView.topAnchor),
            overlayView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),

            badgeView.heightAnchor.constraint(equalToConstant: 20),
            badgeView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            badgeView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 5),

            bookmarkView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            bookmarkView.topAnchor.constraint(equalTo: contentView.topAnchor),
            bookmarkView.widthAnchor.constraint(equalToConstant: 17),
            bookmarkView.heightAnchor.constraint(equalToConstant: 27),

            highlightView.topAnchor.constraint(equalTo: contentView.topAnchor),
            highlightView.leftAnchor.constraint(equalTo: contentView.leftAnchor),
            highlightView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            highlightView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            shadowOverlayView.topAnchor.constraint(equalTo: contentView.topAnchor),
            shadowOverlayView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            shadowOverlayView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            shadowOverlayView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            selectionView.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: -10),
            selectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            selectionView.widthAnchor.constraint(equalToConstant: 24),
            selectionView.heightAnchor.constraint(equalToConstant: 24),

            progressBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5),
            progressBadge.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),
            progressBadge.heightAnchor.constraint(equalToConstant: 18),

            progressBarTrack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            progressBarTrack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            progressBarTrack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            progressBarTrack.heightAnchor.constraint(equalToConstant: 4),

            progressBarFill.leadingAnchor.constraint(equalTo: progressBarTrack.leadingAnchor),
            progressBarFill.topAnchor.constraint(equalTo: progressBarTrack.topAnchor),
            progressBarFill.bottomAnchor.constraint(equalTo: progressBarTrack.bottomAnchor)
        ])
    }

    /// Updates the bottom progress-bar fill to the given 0...1 fraction.
    private func setProgressBar(fraction: Double) {
        progressBarFillWidth?.isActive = false
        let clamped = CGFloat(min(1, max(0, fraction)))
        // A zero multiplier is invalid, so use a tiny sliver for empty progress.
        let width = progressBarFill.widthAnchor.constraint(
            equalTo: progressBarTrack.widthAnchor,
            multiplier: max(0.0001, clamped)
        )
        width.isActive = true
        progressBarFillWidth = width
        progressBarTrack.isHidden = false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = contentView.bounds
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = UIImage(named: "MangaPlaceholder")
        imageTask?.cancel()
        imageTask = nil
        highlightView.alpha = 0
        progressTaskId = nil
        progressBadge.isHidden = true
        progressBadge.text = nil
        progressBarTrack.isHidden = true
    }
}

// MARK: - Reading progress overlay
extension MangaGridCell {
    /// Loads and displays the reading-progress overlay for the current identifier.
    /// Runs a background Core Data query and applies the result only if the cell
    /// hasn't been reused for a different manga.
    func loadReadingProgress() {
        let mode = ProgressIndicatorMode.current
        guard mode != .none, let identifier else {
            progressBadge.isHidden = true
            progressBarTrack.isHidden = true
            return
        }
        progressTaskId = identifier
        Task.detached(priority: .utility) {
            let progress = await CoreDataManager.shared.container.performBackgroundTask { context -> ReadingProgress in
                let filters = CoreDataManager.shared.getMangaChapterFilters(
                    sourceId: identifier.sourceKey,
                    mangaId: identifier.mangaKey,
                    context: context
                )
                let read = CoreDataManager.shared.readCount(
                    sourceId: identifier.sourceKey,
                    mangaId: identifier.mangaKey,
                    lang: filters.language,
                    scanlators: filters.scanlators,
                    context: context
                )
                let unread = CoreDataManager.shared.unreadCount(
                    sourceId: identifier.sourceKey,
                    mangaId: identifier.mangaKey,
                    lang: filters.language,
                    scanlators: filters.scanlators,
                    context: context
                )
                return ReadingProgress(read: read, total: read + unread, mode: mode)
            }
            await MainActor.run {
                guard self.progressTaskId == identifier else { return }
                if progress.isValid {
                    self.progressBadge.text = progress.label
                    self.progressBadge.isHidden = false
                    self.setProgressBar(fraction: progress.fillFraction)
                } else {
                    self.progressBadge.isHidden = true
                    self.progressBarTrack.isHidden = true
                }
            }
        }
    }
}

/// Label with horizontal insets, used for the progress badge pill.
private class PaddedLabel: UILabel {
    private let insets = UIEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height)
    }
}

extension MangaGridCell {
    func highlight() {
        highlightView.alpha = 1
    }

    func unhighlight(animated: Bool = true) {
        UIView.animate(withDuration: animated ? 0.3 : 0) {
            self.highlightView.alpha = 0
        }
    }

    func setEditing(_ editing: Bool, animated: Bool = true) {
        guard isEditing != editing else { return }
        isEditing = editing
        if editing {
            selectionView.setSelected(false, animated: false)
        }
        if animated {
            if editing {
                self.selectionView.isHidden = false
            }
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                self.shadowOverlayView.alpha = editing ? 1 : 0
            } completion: { _ in
                if !editing {
                    self.selectionView.isHidden = true
                }
            }
        } else {
            self.shadowOverlayView.alpha = editing ? 1 : 0
            self.selectionView.isHidden = !editing
        }
    }

    func setSelected(_ selected: Bool, animated: Bool = true) {
        guard isEditing else { return }
        selectionView.setSelected(selected, animated: animated)
        if animated {
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                self.shadowOverlayView.alpha = selected ? 0 : 1
            }
        } else {
            self.shadowOverlayView.alpha = selected ? 0 : 1
        }
    }
}

extension MangaGridCell {
    func loadImage(url: URL?) async {
        guard let url else { return }

        if let imageTask, imageTask.state == .running {
            return
        }

        self.imageView.stopAnimatingGIF()

        var urlRequest = URLRequest(url: url)
        var cached = ImagePipeline.shared.cache.containsCachedImage(for: .init(urlRequest: urlRequest))

        if !cached {
            if let fileUrl = url.toAidokuFileUrl() {
                urlRequest = URLRequest(url: fileUrl)
            } else if let sourceId = identifier?.sourceKey {
                // ensure sources are loaded so we can get the modified image request
                await SourceManager.shared.waitForSourcesLoad()
                if let source = SourceManager.shared.source(for: sourceId) {
                    urlRequest = await source.getModifiedImageRequest(url: url, context: nil)
                }
            }
        }

        self.url = (urlRequest.url ?? url).absoluteString

        let request = ImageRequest(
            urlRequest: urlRequest,
            processors: [DownsampleProcessor(width: bounds.width)]
        )

        cached = cached || ImagePipeline.shared.cache.containsCachedImage(for: request)

        imageTask = ImagePipeline.shared.loadImage(with: request) { [weak self] result in
            guard let self else { return }
            switch result {
                case .success(let response):
                    if response.request.imageID != self.url {
                        return
                    }
                    Task { @MainActor in
                        if cached {
                            self.imageView.image = response.image
                        } else {
                            UIView.transition(with: self.imageView, duration: 0.3, options: .transitionCrossDissolve) {
                                self.imageView.image = response.image
                            }
                        }
                        if response.container.type == .gif, let data = response.container.data {
                            self.imageView.animate(withGIFData: data)
                        }
                    }
                case .failure(let error):
                    imageTask = nil
                    guard let identifier else { return }
                    Task { @MainActor [weak self] in
                        guard
                            let newUrl = await CoverRecovery.recover(from: error, identifier: identifier),
                            self?.identifier == identifier
                        else { return }
                        await self?.loadImage(url: newUrl)
                    }
            }
        }
    }
}
