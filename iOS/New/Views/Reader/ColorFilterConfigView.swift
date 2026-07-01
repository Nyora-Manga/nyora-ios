//
//  ColorFilterConfigView.swift
//  Aidoku (iOS)
//
//  Dedicated reader colour-filter configuration screen (NP-005).
//
//  Provides contrast, invert, warm-book background and multitone palette
//  controls (alongside the existing brightness/grayscale ones) feeding the
//  NP-002 colour-filter pipeline, with a live preview swatch that updates as
//  the user adjusts each control.
//
//  Mirrors nyora-android `reader/ui/colorfilter/ColorFilterConfigActivity.kt`
//  and nyora-mac `Views/ColorCorrectionSheet.swift`, re-implemented natively.
//

import SwiftUI

struct ColorFilterConfigView: View {
    // Persisted colour-filter values.
    @State private var brightness: Double
    @State private var contrast: Double
    @State private var isInverted: Bool
    @State private var isGrayscale: Bool
    @State private var isBookBackground: Bool
    @State private var multitone: Int

    // Cached sample image the preview is rendered from.
    private static let sampleImage: UIImage = ColorFilterSampleImage.make()

    init() {
        let defaults = UserDefaults.standard
        _brightness = State(initialValue: defaults.double(forKey: "Reader.cfBrightness"))
        _contrast = State(initialValue: defaults.double(forKey: "Reader.cfContrast"))
        _isInverted = State(initialValue: defaults.bool(forKey: "Reader.cfInvert"))
        _isGrayscale = State(initialValue: defaults.bool(forKey: "Reader.cfGrayscale"))
        _isBookBackground = State(initialValue: defaults.bool(forKey: "Reader.cfBookBackground"))
        _multitone = State(initialValue: defaults.integer(forKey: "Reader.cfMultitone"))
    }

    private var currentSettings: ReaderColorFilterSettings {
        ReaderColorFilterSettings(
            brightness: brightness,
            contrast: contrast,
            isInverted: isInverted,
            isGrayscale: isGrayscale,
            isBookBackground: isBookBackground,
            multitonePreset: multitone
        )
    }

    private var previewImage: UIImage {
        ColorFilterEngine.apply(Self.sampleImage, settings: currentSettings)
    }

    var body: some View {
        List {
            // Live preview
            Section {
                Image(uiImage: previewImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(height: 130)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            } header: {
                Text(NSLocalizedString("PREVIEW"))
            }

            // Adjustments
            Section {
                sliderRow(
                    title: NSLocalizedString("BRIGHTNESS"),
                    value: $brightness,
                    key: "Reader.cfBrightness"
                )
                sliderRow(
                    title: NSLocalizedString("CONTRAST"),
                    value: $contrast,
                    key: "Reader.cfContrast"
                )
                Toggle(NSLocalizedString("GRAYSCALE"), isOn: $isGrayscale)
                    .onChange(of: isGrayscale) { newValue in
                        commitBool(newValue, key: "Reader.cfGrayscale")
                    }
                Toggle(NSLocalizedString("INVERT_COLORS"), isOn: $isInverted)
                    .onChange(of: isInverted) { newValue in
                        commitBool(newValue, key: "Reader.cfInvert")
                    }
                Toggle(NSLocalizedString("WARM_BOOK_BACKGROUND"), isOn: $isBookBackground)
                    .onChange(of: isBookBackground) { newValue in
                        commitBool(newValue, key: "Reader.cfBookBackground")
                    }
            } header: {
                Text(NSLocalizedString("COLOR_FILTER"))
            }

            // Palette picker
            Section {
                ForEach(paletteGroups, id: \.group) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.group)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(entry.presets, id: \.id) { preset in
                                    paletteSwatch(preset: preset)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                HStack {
                    Text(NSLocalizedString("COLOR_PALETTE"))
                    Spacer()
                    if multitone != 0 {
                        Button(NSLocalizedString("NONE")) {
                            setMultitone(0)
                        }
                        .font(.caption)
                        .textCase(nil)
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("COLOR_FILTER"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(NSLocalizedString("RESET")) {
                    resetAll()
                }
                .disabled(currentSettings.isNeutral)
            }
        }
    }

    // MARK: - Rows

    private func sliderRow(title: String, value: Binding<Double>, key: String) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int((value.wrappedValue * 100).rounded()))")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: -1...1, step: 0.01) { editing in
                if !editing {
                    UserDefaults.standard.set(value.wrappedValue, forKey: key)
                    notifyChanged()
                }
            }
        }
    }

    private func paletteSwatch(preset: ColorFilterPreset) -> some View {
        let selected = multitone == preset.id
        let swatchSettings = ReaderColorFilterSettings(
            brightness: 0,
            contrast: 0,
            isInverted: false,
            isGrayscale: false,
            isBookBackground: false,
            multitonePreset: preset.id
        )
        return Button {
            setMultitone(selected ? 0 : preset.id)
        } label: {
            VStack(spacing: 4) {
                Image(uiImage: ColorFilterEngine.apply(Self.sampleImage, settings: swatchSettings))
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 3)
                    )
                Text(preset.label)
                    .font(.caption2)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .lineLimit(1)
                    .frame(width: 64)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data

    private var paletteGroups: [(group: String, presets: [ColorFilterPreset])] {
        ColorFilterPreset.groupedForDisplay
    }

    // MARK: - Persistence

    private func commitBool(_ newValue: Bool, key: String) {
        UserDefaults.standard.set(newValue, forKey: key)
        notifyChanged()
    }

    private func setMultitone(_ id: Int) {
        multitone = id
        UserDefaults.standard.set(id, forKey: "Reader.cfMultitone")
        notifyChanged()
    }

    private func resetAll() {
        brightness = 0
        contrast = 0
        isInverted = false
        isGrayscale = false
        isBookBackground = false
        multitone = 0
        let defaults = UserDefaults.standard
        defaults.set(0.0, forKey: "Reader.cfBrightness")
        defaults.set(0.0, forKey: "Reader.cfContrast")
        defaults.set(false, forKey: "Reader.cfInvert")
        defaults.set(false, forKey: "Reader.cfGrayscale")
        defaults.set(false, forKey: "Reader.cfBookBackground")
        defaults.set(0, forKey: "Reader.cfMultitone")
        notifyChanged()
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: .init("Reader.colorFilter"), object: nil)
    }
}

// MARK: - Sample image

/// Builds a synthetic sample image (grayscale ramp + colour bars) used to
/// preview the colour filter without needing a real page loaded.
enum ColorFilterSampleImage {
    static func make() -> UIImage {
        let size = CGSize(width: 320, height: 130)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext

            // Top half: horizontal grayscale ramp.
            let rampHeight = size.height * 0.5
            let colors = [UIColor.black.cgColor, UIColor.white.cgColor] as CFArray
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 1]
            ) {
                cg.saveGState()
                cg.clip(to: CGRect(x: 0, y: 0, width: size.width, height: rampHeight))
                cg.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: size.width, y: 0),
                    options: []
                )
                cg.restoreGState()
            }

            // Bottom half: colour bars.
            let bars: [UIColor] = [
                .systemRed, .systemOrange, .systemYellow, .systemGreen,
                .systemTeal, .systemBlue, .systemIndigo, .systemPurple
            ]
            let barWidth = size.width / CGFloat(bars.count)
            for (index, color) in bars.enumerated() {
                cg.setFillColor(color.cgColor)
                cg.fill(CGRect(
                    x: CGFloat(index) * barWidth,
                    y: rampHeight,
                    width: barWidth,
                    height: size.height - rampHeight
                ))
            }
        }
    }
}
