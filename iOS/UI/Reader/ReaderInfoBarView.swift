//
//  ReaderInfoBarView.swift
//  Aidoku (iOS)
//
//  Persistent, always-on reader information overlay (NP-018).
//  Ported natively from nyora-android's ReaderInfoBarView.kt.
//
//  Shows the current chapter / page position on the leading edge and the
//  battery level + clock on the trailing edge. Independent of the reader
//  toolbar: it is shown while the reader bars are hidden. Supports a
//  transparent style (outlined text, no background) driven by
//  Reader.infoBarTransparent, mirroring the android reader_bar_transparent
//  preference.
//

import UIKit

class ReaderInfoBarView: UIView {

    /// When false, a translucent material background is drawn behind the text.
    /// When true (default), no background is drawn and the text is outlined for
    /// legibility over arbitrary page content.
    var isTransparent: Bool = true {
        didSet {
            guard oldValue != isTransparent else { return }
            applyStyle()
            refresh()
        }
    }

    private var chapterNumber: Int = 0
    private var chaptersTotal: Int = 0
    private var currentPage: Int = 0
    private var totalPages: Int = 0

    private let backgroundView: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let infoLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return label
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.textAlignment = .right
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }()

    private var clockTimer: Timer?

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

        addSubview(backgroundView)
        addSubview(infoLabel)
        addSubview(statusLabel)

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            infoLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            infoLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            infoLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),

            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            statusLabel.centerYAnchor.constraint(equalTo: infoLabel.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: infoLabel.trailingAnchor, constant: 8)
        ])

        applyStyle()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            UIDevice.current.isBatteryMonitoringEnabled = true
            startClock()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(refresh),
                name: UIDevice.batteryLevelDidChangeNotification,
                object: nil
            )
            refresh()
        } else {
            stopClock()
            NotificationCenter.default.removeObserver(self, name: UIDevice.batteryLevelDidChangeNotification, object: nil)
        }
    }

    private func startClock() {
        stopClock()
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer
    }

    private func stopClock() {
        clockTimer?.invalidate()
        clockTimer = nil
    }

    private func applyStyle() {
        backgroundView.isHidden = isTransparent
    }

    /// Update the progress info shown on the leading edge.
    func update(chapterNumber: Int, chaptersTotal: Int, currentPage: Int, totalPages: Int) {
        self.chapterNumber = chapterNumber
        self.chaptersTotal = chaptersTotal
        self.currentPage = currentPage
        self.totalPages = totalPages
        refresh()
    }

    @objc private func refresh() {
        // leading: "Ch. x/y  Pg. a/b"
        let infoText: String
        if chaptersTotal > 0 && totalPages > 0 {
            infoText = String(
                format: NSLocalizedString("READER_INFO_PATTERN", comment: ""),
                chapterNumber, chaptersTotal, currentPage, totalPages
            )
        } else if totalPages > 0 {
            infoText = String(
                format: NSLocalizedString("READER_INFO_PAGE_PATTERN", comment: ""),
                currentPage, totalPages
            )
        } else {
            infoText = ""
        }

        // trailing: battery% + clock
        var statusText = Self.timeFormatter.string(from: Date())
        let batteryLevel = UIDevice.current.batteryLevel
        if batteryLevel >= 0 {
            let percent = Int((batteryLevel * 100).rounded())
            statusText = "\(percent)%  " + statusText
        }

        setText(infoText, on: infoLabel, alignment: .left)
        setText(statusText, on: statusLabel, alignment: .right)
    }

    private func setText(_ text: String, on label: UILabel, alignment: NSTextAlignment) {
        if isTransparent {
            // outline the text for legibility over arbitrary page content,
            // mirroring the android ReaderInfoBarView stroke approach.
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = alignment
            let attributes: [NSAttributedString.Key: Any] = [
                .font: label.font as Any,
                .foregroundColor: UIColor.label,
                .strokeColor: UIColor.systemBackground.withAlphaComponent(0.9),
                .strokeWidth: -2.5,
                .paragraphStyle: paragraph
            ]
            label.attributedText = NSAttributedString(string: text, attributes: attributes)
        } else {
            label.attributedText = nil
            label.textColor = .label
            label.text = text
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    deinit {
        stopClock()
        NotificationCenter.default.removeObserver(self)
    }
}
