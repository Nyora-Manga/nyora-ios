//
//  UINavigationItem.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/15/22.
//

import UIKit

extension UINavigationItem {

    func setTitle(upper: String?, lower: String) {
        if let upper = upper {
            // Nyora reader chrome (ND-020): centered Poppins title + subtitle.
            let lowerLabel = UILabel()
            lowerLabel.text = lower
            lowerLabel.font = NyoraTheme.poppins(15, .semibold)
            lowerLabel.textAlignment = .center

            let upperLabel = UILabel()
            upperLabel.text = upper
            upperLabel.font = NyoraTheme.poppins(11, .medium)
            upperLabel.textColor = .secondaryLabel
            upperLabel.textAlignment = .center

            let stackView = UIStackView(arrangedSubviews: [lowerLabel, upperLabel])
            stackView.distribution = .equalCentering
            stackView.axis = .vertical
            stackView.alignment = .center
            stackView.spacing = 1

            upperLabel.sizeToFit()
            lowerLabel.sizeToFit()

            let width = max(upperLabel.frame.size.width, lowerLabel.frame.size.width)
            stackView.frame = CGRect(x: 0, y: 0, width: width, height: 35)

            self.titleView = stackView
        } else {
            self.titleView = nil
            self.title = lower
        }
    }
}
