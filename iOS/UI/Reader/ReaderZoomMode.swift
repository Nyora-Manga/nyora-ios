//
//  ReaderZoomMode.swift
//  Aidoku (iOS)
//
//  Ported from nyora-android core/model/ZoomMode.kt — controls how each page
//  is scaled to fit within the paged reader viewport.
//

import UIKit

enum ReaderZoomMode: String {
    /// Whole page visible, scaled to fit within both dimensions (default).
    case fitCenter = "fitCenter"
    /// Page scaled so its height fills the screen; pans horizontally if wider.
    case fitHeight = "fitHeight"
    /// Page scaled so its width fills the screen; pans vertically if taller.
    case fitWidth = "fitWidth"
    /// Like fit-width but anchored to the start (top) of the page.
    case keepStart = "keepStart"

    static var current: ReaderZoomMode {
        UserDefaults.standard.string(forKey: "Reader.zoomMode")
            .flatMap(ReaderZoomMode.init) ?? .fitCenter
    }
}
