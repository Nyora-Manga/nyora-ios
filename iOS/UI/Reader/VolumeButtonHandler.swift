//
//  VolumeButtonHandler.swift
//  Aidoku (iOS)
//
//  Ported from nyora-android reader volume-button page turning.
//

import UIKit
import AVFoundation
import MediaPlayer

/// Detects hardware volume button presses and reports up/down events.
///
/// iOS exposes no public API for hardware volume buttons, so this observes the audio
/// session's `outputVolume` and immediately resets it via a hidden `MPVolumeView`
/// slider. Resetting keeps the buttons usable indefinitely and suppresses the system
/// volume HUD (the volume view lives offscreen inside the reader's view hierarchy).
final class VolumeButtonHandler {
    /// Called when the volume-up button is pressed.
    var onVolumeUp: (() -> Void)?
    /// Called when the volume-down button is pressed.
    var onVolumeDown: (() -> Void)?

    private let session = AVAudioSession.sharedInstance()
    private weak var containerView: UIView?

    private var volumeView: MPVolumeView?
    private var volumeSlider: UISlider?
    private var observation: NSKeyValueObservation?

    private var baselineVolume: Float = 0.5
    private(set) var isActive = false
    /// Skip the next observed change (it's the one we triggered by resetting volume).
    private var suppressNext = false

    init(containerView: UIView) {
        self.containerView = containerView
    }

    deinit {
        stop()
    }

    func start() {
        guard !isActive else { return }
        isActive = true

        // hidden volume view: keeps the system HUD from appearing and lets us reset volume
        let volumeView = MPVolumeView(frame: CGRect(x: -4000, y: -4000, width: 1, height: 1))
        volumeView.alpha = 0.0001
        volumeView.isUserInteractionEnabled = false
        containerView?.addSubview(volumeView)
        self.volumeView = volumeView
        self.volumeSlider = volumeView.subviews.compactMap { $0 as? UISlider }.first

        do {
            try session.setCategory(.ambient, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // non-fatal: observation may still work while another category is active
        }

        // start from a mid-range volume so both up and down presses are detectable
        baselineVolume = clampBaseline(session.outputVolume)
        setSystemVolume(baselineVolume)

        observation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let self, let newValue = change.newValue else { return }
            Task { @MainActor in
                self.handleVolumeChange(newValue)
            }
        }
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        observation?.invalidate()
        observation = nil
        volumeView?.removeFromSuperview()
        volumeView = nil
        volumeSlider = nil
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func clampBaseline(_ value: Float) -> Float {
        min(max(value, 0.125), 0.875)
    }

    @MainActor
    private func handleVolumeChange(_ newValue: Float) {
        if suppressNext {
            suppressNext = false
            return
        }
        let diff = newValue - baselineVolume
        guard abs(diff) > 0.0001 else { return }

        if diff > 0 {
            onVolumeUp?()
        } else {
            onVolumeDown?()
        }

        // reset back to baseline so the next press is detectable; consume the resulting change
        suppressNext = true
        setSystemVolume(baselineVolume)
    }

    private func setSystemVolume(_ value: Float) {
        // setting via the slider (rather than a private API) avoids showing the system HUD
        DispatchQueue.main.async { [weak self] in
            self?.volumeSlider?.value = value
        }
    }
}
