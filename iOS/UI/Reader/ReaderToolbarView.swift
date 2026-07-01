//
//  ReaderToolbarView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/15/22.
//

import Combine
import UIKit

class ReaderToolbarView: UIView {
    var currentPageValue: Int? {
        didSet {
            if oldValue != currentPageValue {
                let feedbackGenerator = UISelectionFeedbackGenerator()
                feedbackGenerator.selectionChanged()
            }
        }
    }
    var currentPage: Int? {
        didSet { updatePageLabels() }
    }
    var totalPages: Int? {
        didSet { updatePageLabels() }
    }

    let sliderView = ReaderSliderView()
    private let incognitoModeLabel = UILabel()
    private let currentPageLabel = UILabel()
    private let pagesLeftLabel = UILabel()

    // Nyora reader chrome (ND-020): prev/next chapter buttons flanking the slider,
    // all inside a floating rounded pill. The buttons' actions are wired by the
    // reader view controller.
    let prevChapterButton = UIButton(type: .system)
    let nextChapterButton = UIButton(type: .system)
    private let pillView = UIView()
    private let pillBlur = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))

    private var cancellables: [AnyCancellable] = []

    init() {
        super.init(frame: .zero)
        configure()
        constrain()
        observe()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {
        // floating rounded pill background behind the slider + chapter buttons
        pillView.backgroundColor = .clear
        pillView.layer.borderWidth = 1
        pillView.layer.borderColor = NyoraTheme.indigo.withAlphaComponent(0.18).cgColor
        pillView.clipsToBounds = true
        pillBlur.isUserInteractionEnabled = false
        pillView.addSubview(pillBlur)
        addSubview(pillView)

        prevChapterButton.setImage(UIImage(systemName: "chevron.left.2"), for: .normal)
        prevChapterButton.tintColor = NyoraTheme.indigo
        addSubview(prevChapterButton)

        nextChapterButton.setImage(UIImage(systemName: "chevron.right.2"), for: .normal)
        nextChapterButton.tintColor = NyoraTheme.indigo
        addSubview(nextChapterButton)

        incognitoModeLabel.font = NyoraTheme.poppins(10, .medium)
        incognitoModeLabel.textColor = .secondaryLabel
        incognitoModeLabel.textAlignment = .left
        incognitoModeLabel.isHidden = !UserDefaults.standard.bool(forKey: "General.incognitoMode")
        addSubview(incognitoModeLabel)

        currentPageLabel.font = NyoraTheme.poppins(10, .medium)
        currentPageLabel.textAlignment = .center
        currentPageLabel.sizeToFit()
        addSubview(currentPageLabel)

        pagesLeftLabel.font = NyoraTheme.poppins(10)
        pagesLeftLabel.textColor = .secondaryLabel
        pagesLeftLabel.textAlignment = .right
        addSubview(pagesLeftLabel)

        sliderView.semanticContentAttribute = .playback // for rtl languages
        addSubview(sliderView)
    }

    func constrain() {
        incognitoModeLabel.translatesAutoresizingMaskIntoConstraints = false
        currentPageLabel.translatesAutoresizingMaskIntoConstraints = false
        pagesLeftLabel.translatesAutoresizingMaskIntoConstraints = false
        sliderView.translatesAutoresizingMaskIntoConstraints = false
        pillView.translatesAutoresizingMaskIntoConstraints = false
        pillBlur.translatesAutoresizingMaskIntoConstraints = false
        prevChapterButton.translatesAutoresizingMaskIntoConstraints = false
        nextChapterButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            // floating pill spanning the top row
            pillView.topAnchor.constraint(equalTo: topAnchor),
            pillView.leadingAnchor.constraint(equalTo: leadingAnchor),
            pillView.trailingAnchor.constraint(equalTo: trailingAnchor),
            pillView.heightAnchor.constraint(equalToConstant: 34),

            pillBlur.topAnchor.constraint(equalTo: pillView.topAnchor),
            pillBlur.bottomAnchor.constraint(equalTo: pillView.bottomAnchor),
            pillBlur.leadingAnchor.constraint(equalTo: pillView.leadingAnchor),
            pillBlur.trailingAnchor.constraint(equalTo: pillView.trailingAnchor),

            prevChapterButton.leadingAnchor.constraint(equalTo: pillView.leadingAnchor, constant: 8),
            prevChapterButton.centerYAnchor.constraint(equalTo: pillView.centerYAnchor),
            prevChapterButton.widthAnchor.constraint(equalToConstant: 34),

            nextChapterButton.trailingAnchor.constraint(equalTo: pillView.trailingAnchor, constant: -8),
            nextChapterButton.centerYAnchor.constraint(equalTo: pillView.centerYAnchor),
            nextChapterButton.widthAnchor.constraint(equalToConstant: 34),

            sliderView.heightAnchor.constraint(equalToConstant: 12),
            sliderView.centerYAnchor.constraint(equalTo: pillView.centerYAnchor),
            sliderView.leadingAnchor.constraint(equalTo: prevChapterButton.trailingAnchor, constant: 4),
            sliderView.trailingAnchor.constraint(equalTo: nextChapterButton.leadingAnchor, constant: -4),

            currentPageLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            currentPageLabel.topAnchor.constraint(equalTo: pillView.bottomAnchor, constant: 1),

            incognitoModeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            incognitoModeLabel.centerYAnchor.constraint(equalTo: currentPageLabel.centerYAnchor),

            pagesLeftLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            pagesLeftLabel.centerYAnchor.constraint(equalTo: currentPageLabel.centerYAnchor)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        pillView.layer.cornerRadius = pillView.bounds.height / 2 // capsule
        pillView.layer.cornerCurve = .continuous
    }

    /// Shows or hides the flanking prev/next chapter buttons (driven by Reader.controls).
    func setChapterButtons(prev: Bool, next: Bool) {
        prevChapterButton.isHidden = !prev
        nextChapterButton.isHidden = !next
    }

    func observe() {
        NotificationCenter.default.publisher(for: .incognitoMode)
            .sink { [weak self] _ in
                self?.incognitoModeLabel.isHidden = !UserDefaults.standard.bool(forKey: "General.incognitoMode")
            }
            .store(in: &cancellables)
    }

    /// Shows or hides the slider + page labels (customizable reader controls, NP-022).
    func setSliderVisible(_ visible: Bool) {
        sliderView.isHidden = !visible
        currentPageLabel.isHidden = !visible
        pagesLeftLabel.isHidden = !visible
    }

    // allow slider thumb to be touched outside bounds
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        for subview in subviews where subview is ReaderSliderView {
            if subview.subviews.contains(where: { $0.bounds.contains(convert(point, to: $0)) }) {
                return subview
            }
        }
        return super.hitTest(point, with: event)
    }

    func displayPage(_ page: Int) {
        guard let totalPages = totalPages else {
            return
        }
        var page = page
        if page > totalPages {
            page = totalPages
        } else if page < 1 {
            page = 1
        }
        currentPageLabel.text = String(format: NSLocalizedString("%i_OF_%i", comment: ""), page, totalPages)
        currentPageValue = page
    }

    func updatePageLabels() {
        guard var currentPage = currentPage, let totalPages = totalPages else {
            currentPageLabel.text = nil
            pagesLeftLabel.text = nil
            return
        }

        if currentPage > totalPages {
            currentPage = totalPages
        } else if currentPage < 1 {
            currentPage = 1
        }
        let pagesLeft = totalPages - currentPage
        currentPageLabel.text = String(format: NSLocalizedString("%i_OF_%i", comment: ""), currentPage, totalPages)
        if pagesLeft < 1 {
            pagesLeftLabel.text = nil
        } else {
            pagesLeftLabel.text = pagesLeft == 1
                ? NSLocalizedString("ONE_PAGE_LEFT", comment: "")
                : String(format: NSLocalizedString("%i_PAGES_LEFT", comment: ""), pagesLeft)
        }
        incognitoModeLabel.text = NSLocalizedString("INCOGNITO_MODE")
    }

    func updateSliderPosition() {
        guard let currentPage = currentPage, let totalPages = totalPages else { return }
        sliderView.move(toValue: CGFloat(currentPage - 1) / max(CGFloat(totalPages - 1), 1))
    }
}
