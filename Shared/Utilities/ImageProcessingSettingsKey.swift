//
//  ImageProcessingSettingsKey.swift
//  Aidoku
//
//  Created by 686udjie on 26/11/2025.
//

import Foundation

enum ImageProcessingSettingsKey {
    static func getProcessorSettingsKey() -> String {
        let crop = UserDefaults.standard.bool(forKey: "Reader.cropBorders")
        let downsample = UserDefaults.standard.bool(forKey: "Reader.downsampleImages")
        let upscale = UserDefaults.standard.bool(forKey: "Reader.upscaleImages")
        let maxHeight = UserDefaults.standard.integer(forKey: "Reader.upscaleMaxHeight")
        // Reader colour-filter settings (NP-002) — read inline so this stays
        // available to targets that don't include the iOS-only engine type.
        let defaults = UserDefaults.standard
        let cfBrightness = defaults.double(forKey: "Reader.cfBrightness")
        let cfContrast = defaults.double(forKey: "Reader.cfContrast")
        let cfInvert = defaults.bool(forKey: "Reader.cfInvert")
        let cfGrayscale = defaults.bool(forKey: "Reader.cfGrayscale")
        let cfBook = defaults.bool(forKey: "Reader.cfBookBackground")
        let cfMultitone = defaults.integer(forKey: "Reader.cfMultitone")
        let colorFilter = "\(cfBrightness)-\(cfContrast)-\(cfInvert)-\(cfGrayscale)-\(cfBook)-\(cfMultitone)"
        let enhancedColors = defaults.bool(forKey: "Reader.enhancedColors")
        return "\(crop)-\(downsample)-\(upscale)-\(maxHeight)-\(colorFilter)-\(enhancedColors)"
    }
}
