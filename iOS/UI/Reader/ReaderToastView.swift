//
//  ReaderToastView.swift
//  Aidoku (iOS)
//
//  Transient in-reader toast (NP-035).
//  Ported natively from nyora-android's ReaderToastView.kt.
//
//  Shows a short-lived pill with a message (used to announce the chapter name
//  when a new chapter begins). Fades in, stays for a fixed duration, then fades
//  out; calling `showTemporary` again cancels any pending hide and resets the
//  timer.
//

import UIKit

class ReaderToastView: UIView {

    /// Default on-screen duration for a temporary toast, mirroring android's
    /// TOAST_DURATION.
    static let defaultDuration: TimeInterval = 2.0

    private let backgroundView: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 16
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        return view
    }()

    private let label: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .label
        label.textAlignment = .center
        label.numberOfLines = 2
        return label
    }()

    private var hideWorkItem: DispatchWorkItem?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        alpha = 0
        isHidden = true

        addSubview(backgroundView)
        backgroundView.contentView.addSubview(label)

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            label.topAnchor.constraint(equalTo: backgroundView.contentView.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: backgroundView.contentView.bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(equalTo: backgroundView.contentView.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: backgroundView.contentView.trailingAnchor, constant: -16)
        ])
    }

    /// Show the toast with the given message and hide it after `duration`.
    func showTemporary(_ message: String, duration: TimeInterval = ReaderToastView.defaultDuration) {
        guard !message.isEmpty else { return }
        hideWorkItem?.cancel()
        label.text = message
        show()

        let work = DispatchWorkItem { [weak self] in
            self?.hide()
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func show() {
        isHidden = false
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.alpha = 1
        }
    }

    func hide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) {
            self.alpha = 0
        } completion: { _ in
            if self.alpha == 0 {
                self.isHidden = true
            }
        }
    }

    deinit {
        hideWorkItem?.cancel()
    }
}
