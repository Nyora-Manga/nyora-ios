//
//  ReaderReaderDelegate.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/16/22.
//

import UIKit
import AidokuRunner

@MainActor
// swiftlint:disable:next class_delegate_protocol
protocol ReaderReaderDelegate: UIViewController {
    var readingMode: ReadingMode { get set }
    var delegate: ReaderHoldingDelegate? { get set }

    func moveLeft()
    func moveRight()
    func toggleOffset()

    func sliderMoved(value: CGFloat)
    func sliderStopped(value: CGFloat)
    func setChapter(_ chapter: AidokuRunner.Chapter, startPage: Int)

    /// Advance the reader by `points` for auto-scroll (NP-019).
    /// Returns `false` when there is no more content to scroll.
    func autoScrollBy(_ points: CGFloat) -> Bool
}

extension ReaderReaderDelegate {
    func toggleOffset() {
        // do nothing by default
    }

    func autoScrollBy(_ points: CGFloat) -> Bool {
        // only supported by scrolling readers
        false
    }
}
