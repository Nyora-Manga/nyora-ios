//
//  NyoraSearchHeroView.swift
//  Aidoku (iOS) — Nyora fork
//
//  Explore "search hero": a large fully-rounded pill card ported from
//  nyora-android's item_explore_search_hero.xml. Flat tinted surface + 1px
//  indigo outline, a leading magnifier glyph, and a Poppins placeholder label.
//  Tapping it activates the host screen's existing search flow.
//

import UIKit

final class NyoraSearchHeroView: UIControl {
    /// Full header height (pill height + vertical padding above/below).
    static let preferredHeight: CGFloat = 72
    static let horizontalMargin: CGFloat = 16
    static let verticalPadding: CGFloat = 8

    private let container = UIView()
    private let iconView = UIImageView()
    private let label = UILabel()

    /// Called when the hero is tapped (touch up inside).
    var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private var cardSurface: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? NyoraTheme.hex("1E293B") // slate 800
                : NyoraTheme.hex("F1F5F9") // slate 100
        }
    }

    private var cardOutline: UIColor {
        UIColor { traits in
            NyoraTheme.indigo.withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.22 : 0.14)
        }
    }

    private func setup() {
        container.isUserInteractionEnabled = false
        container.backgroundColor = cardSurface
        container.layer.borderColor = cardOutline.cgColor
        container.layer.borderWidth = 1
        container.layer.masksToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)

        iconView.image = UIImage(systemName: "magnifyingglass")
        iconView.tintColor = .secondaryLabel
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(iconView)

        label.text = NSLocalizedString("SEARCH", comment: "")
        label.font = NyoraTheme.poppins(16, .regular)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor, constant: Self.verticalPadding),
            container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.verticalPadding),
            container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalMargin),
            container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalMargin),

            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 14),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -18),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        addTarget(self, action: #selector(handleTap), for: .touchUpInside)
        addTarget(self, action: #selector(setPressed), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(setReleased), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Fully-rounded pill (capsule) based on the card height.
        container.layer.cornerRadius = min(NyoraTheme.cornerPill, container.bounds.height / 2)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // Refresh dynamic colors resolved into the CALayer border.
        container.layer.borderColor = cardOutline.cgColor
    }

    @objc private func handleTap() {
        onTap?()
    }

    @objc private func setPressed() {
        UIView.animate(withDuration: 0.12) {
            self.container.alpha = 0.7
            self.container.transform = CGAffineTransform(scaleX: 0.985, y: 0.985)
        }
    }

    @objc private func setReleased() {
        UIView.animate(withDuration: 0.12) {
            self.container.alpha = 1
            self.container.transform = .identity
        }
    }
}
