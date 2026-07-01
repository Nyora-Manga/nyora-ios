//
//  AutoScrollController.swift
//  Aidoku (iOS)
//
//  Ported from nyora-android ScrollTimer / ScrollTimerControlView (NP-019).
//

import UIKit

/// Drives a continuous, timed auto-scroll using a display link.
///
/// The controller itself is UI-agnostic: it calls `scrollHandler` every frame with the number of
/// points to advance and stops when the handler reports that no more content is available.
@MainActor
final class AutoScrollController {
    /// Called each frame with the number of points to advance.
    /// Returns whether more content remains (return `false` to stop the timer).
    var scrollHandler: ((CGFloat) -> Bool)?

    /// Notifies observers whenever the active state changes.
    var onActiveChanged: ((Bool) -> Void)?

    private(set) var isActive = false {
        didSet {
            guard oldValue != isActive else { return }
            onActiveChanged?(isActive)
        }
    }

    /// Normalized speed in `0...1`, persisted to `Reader.autoScrollSpeed`.
    var speed: Double {
        get {
            let value = UserDefaults.standard.double(forKey: "Reader.autoScrollSpeed")
            return min(1, max(0, value))
        }
        set {
            UserDefaults.standard.set(min(1, max(0, newValue)), forKey: "Reader.autoScrollSpeed")
        }
    }

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0

    /// Maps the normalized speed onto a scroll rate in points per second.
    private var pointsPerSecond: CGFloat {
        let s = CGFloat(speed)
        // ease-in curve so the low end of the slider stays gentle
        return 30 + s * s * 620
    }

    func start() {
        guard displayLink == nil else {
            isActive = true
            return
        }
        lastTimestamp = 0
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        isActive = true
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        isActive = false
    }

    func toggle() {
        if isActive {
            stop()
        } else {
            start()
        }
    }

    @objc private func step(_ link: CADisplayLink) {
        guard lastTimestamp != 0 else {
            lastTimestamp = link.timestamp
            return
        }
        let dt = link.timestamp - lastTimestamp
        lastTimestamp = link.timestamp
        // clamp dt to avoid a big jump after a stall
        let clampedDt = min(dt, 1.0 / 30.0)
        let delta = pointsPerSecond * CGFloat(clampedDt)
        let canContinue = scrollHandler?(delta) ?? false
        if !canContinue {
            stop()
        }
    }

    deinit {
        displayLink?.invalidate()
    }
}

/// A compact on-screen control for auto-scroll: play/pause toggle, speed slider and close button.
final class AutoScrollControlView: UIView {
    var onToggle: (() -> Void)?
    var onClose: (() -> Void)?
    var onSpeedChanged: ((Float) -> Void)?

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let playButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let slider = UISlider()

    init() {
        super.init(frame: .zero)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false

        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.layer.cornerRadius = 20
        blurView.layer.cornerCurve = .continuous
        blurView.clipsToBounds = true
        addSubview(blurView)

        playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        playButton.addTarget(self, action: #selector(toggleTapped), for: .touchUpInside)
        playButton.translatesAutoresizingMaskIntoConstraints = false

        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.tintColor = .secondaryLabel
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        let slowIcon = UIImageView(image: UIImage(systemName: "tortoise.fill"))
        slowIcon.tintColor = .secondaryLabel
        slowIcon.contentMode = .scaleAspectFit
        let fastIcon = UIImageView(image: UIImage(systemName: "hare.fill"))
        fastIcon.tintColor = .secondaryLabel
        fastIcon.contentMode = .scaleAspectFit

        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.value = Float(min(1, max(0, UserDefaults.standard.double(forKey: "Reader.autoScrollSpeed"))))
        slider.addTarget(self, action: #selector(sliderChanged(_:)), for: .valueChanged)
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [playButton, slowIcon, slider, fastIcon, closeButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        blurView.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),

            stack.topAnchor.constraint(equalTo: blurView.contentView.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: blurView.contentView.bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor, constant: -16),

            playButton.widthAnchor.constraint(equalToConstant: 28),
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            slowIcon.widthAnchor.constraint(equalToConstant: 18),
            slowIcon.heightAnchor.constraint(equalToConstant: 18),
            fastIcon.widthAnchor.constraint(equalToConstant: 18),
            fastIcon.heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    func setActive(_ active: Bool) {
        playButton.setImage(
            UIImage(systemName: active ? "pause.fill" : "play.fill"),
            for: .normal
        )
    }

    @objc private func toggleTapped() {
        onToggle?()
    }

    @objc private func closeTapped() {
        onClose?()
    }

    @objc private func sliderChanged(_ sender: UISlider) {
        onSpeedChanged?(sender.value)
    }
}
