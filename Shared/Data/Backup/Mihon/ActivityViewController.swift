//
//  ActivityViewController.swift
//  Nyora
//

import SwiftUI
import UIKit

/// Share-sheet wrapper used to hand an exported backup file to another app.
struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// `sheet(item:)` needs an Identifiable; a file URL identifies itself.
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
