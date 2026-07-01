//
//  ReaderSettingsView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 6/30/25.
//

import SwiftUI

struct ReaderSettingsView: View {
    let mangaId: MangaIdentifier
    let reader: ReaderViewController.Reader

    @State private var readingMode: ReadingMode?
    @State private var tapZones: DefaultTapZones
    @State private var cfBrightness: Double
    @StateObject private var downsampleImages = UserDefaultsBool(key: "Reader.downsampleImages")
    @StateObject private var upscaleImages = UserDefaultsBool(key: "Reader.upscaleImages")
    @StateObject private var splitWideImages = UserDefaultsBool(key: "Reader.splitWideImages")

    // All available font families on the system
    private static let availableFonts: [String] = {
        var fonts = UIFont.familyNames.sorted()
        // Add "System" at the beginning for the default SF font
        fonts.insert("System", at: 0)
        return fonts
    }()

    @Environment(\.dismiss) private var dismiss

    init(mangaId: MangaIdentifier, reader: ReaderViewController.Reader) {
        self.mangaId = mangaId
        self.reader = reader
        self._readingMode = State(
            initialValue: UserDefaults.standard.string(forKey: "Reader.readingMode.\(mangaId)")
                .flatMap(ReadingMode.init)
        )
        self._tapZones = State(
            initialValue: UserDefaults.standard.string(forKey: "Reader.tapZones")
                .flatMap(DefaultTapZones.init) ?? .disabled
        )
        self._cfBrightness = State(
            initialValue: UserDefaults.standard.double(forKey: "Reader.cfBrightness")
        )
    }

    var body: some View {
        PlatformNavigationStack {
            List {
                Section(NSLocalizedString("GENERAL")) {
                    let readingModeKey = "Reader.readingMode.\(mangaId)"
                    SettingView(
                        setting: .init(
                            key: readingModeKey,
                            title: NSLocalizedString("READING_MODE"),
                            notification: .init(readingModeKey),
                            value: .select(.init(
                                values: [
                                    "default",
                                    "auto",
                                    "rtl",
                                    "ltr",
                                    "vertical",
                                    "webtoon",
                                    "continuous"
                                ],
                                titles: [
                                    NSLocalizedString("DEFAULT"),
                                    NSLocalizedString("AUTOMATIC"),
                                    NSLocalizedString("RTL"),
                                    NSLocalizedString("LTR"),
                                    NSLocalizedString("VERTICAL"),
                                    NSLocalizedString("WEBTOON"),
                                    NSLocalizedString("CONTINUOUS_WITH_GAPS")
                                ]
                            ))
                        )
                    )
                    SettingView(
                        setting: .init(
                            key: "Reader.skipDuplicateChapters",
                            title: NSLocalizedString("SKIP_DUPLICATE_CHAPTERS"),
                            value: .toggle(.init())
                        )
                    )
                    SettingView(
                        setting: .init(
                            key: "Reader.markDuplicateChapters",
                            title: NSLocalizedString("MARK_DUPLICATE_CHAPTERS"),
                            value: .toggle(.init())
                        )
                    )
                    if reader != .text {
                        SettingView(
                            setting: .init(
                                key: "Reader.downsampleImages",
                                title: NSLocalizedString("DOWNSAMPLE_IMAGES"),
                                value: .toggle(.init())
                            )
                        )
                        SettingView(
                            setting: .init(
                                key: "Reader.cropBorders",
                                title: NSLocalizedString("CROP_BORDERS"),
                                value: .toggle(.init())
                            )
                        )
                        SettingView(
                            setting: .init(
                                key: "Reader.cfGrayscale",
                                title: NSLocalizedString("GRAYSCALE"),
                                notification: .init("Reader.cfGrayscale"),
                                value: .toggle(.init())
                            )
                        )
                        VStack(spacing: 4) {
                            HStack {
                                Text(NSLocalizedString("BRIGHTNESS"))
                                Spacer()
                                Text("\(Int((cfBrightness * 100).rounded()))")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Slider(value: $cfBrightness, in: -1...1, step: 0.01) { editing in
                                if !editing {
                                    UserDefaults.standard.set(cfBrightness, forKey: "Reader.cfBrightness")
                                    NotificationCenter.default.post(name: .init("Reader.cfBrightness"), object: nil)
                                }
                            }
                        }
                        NavigationLink(destination: ColorFilterConfigView()) {
                            Text(NSLocalizedString("COLOR_FILTER"))
                        }
                        SettingView(
                            setting: .init(
                                key: "Reader.disableQuickActions",
                                title: NSLocalizedString("DISABLE_QUICK_ACTIONS"),
                                value: .toggle(.init())
                            )
                        )
                        SettingView(
                            setting: .init(
                                key: "Reader.disableDoubleTap",
                                title: NSLocalizedString("DISABLE_DOUBLE_TAP_ZOOM"),
                                value: .toggle(.init())
                            )
                        )
                        SettingView(
                            setting: .init(
                                key: "Reader.liveText",
                                title: NSLocalizedString("LIVE_TEXT"),
                                value: .toggle(.init())
                            )
                        )
                    }
                    SettingView(
                        setting: .init(
                            key: "Reader.hideBarsOnSwipe",
                            title: NSLocalizedString("HIDE_BARS_ON_SWIPE"),
                            value: .toggle(.init())
                        )
                    )
                    SettingView(
                        setting: .init(
                            key: "Reader.keepScreenOn",
                            title: NSLocalizedString("KEEP_SCREEN_ON"),
                            notification: .init("Reader.keepScreenOn"),
                            value: .toggle(.init())
                        )
                    )
                    SettingView(
                        setting: .init(
                            key: "Reader.volumeButtons",
                            title: NSLocalizedString("VOLUME_BUTTON_PAGING"),
                            notification: .init("Reader.volumeButtons"),
                            value: .toggle(.init())
                        )
                    )
                    SettingView(
                        setting: .init(
                            key: "Reader.fullscreen",
                            title: NSLocalizedString("READER_FULLSCREEN"),
                            notification: .init("Reader.fullscreen"),
                            value: .toggle(.init())
                        )
                    )
                    SettingView(
                        setting: .init(
                            key: "Reader.infoBar",
                            title: NSLocalizedString("READER_INFO_BAR"),
                            notification: .init("Reader.infoBar"),
                            value: .toggle(.init(subtitle: NSLocalizedString("READER_INFO_BAR_SUBTITLE")))
                        )
                    )
                    SettingView(
                        setting: .init(
                            key: "Reader.infoBarTransparent",
                            title: NSLocalizedString("READER_INFO_BAR_TRANSPARENT"),
                            notification: .init("Reader.infoBarTransparent"),
                            requires: "Reader.infoBar",
                            value: .toggle(.init())
                        )
                    )
                    SettingView(
                        setting: .init(
                            key: "Reader.backgroundColor",
                            title: NSLocalizedString("READER_BG_COLOR"),
                            value: .select(.init(
                                values: ["system", "auto", "white", "black"],
                                titles: [
                                    NSLocalizedString("READER_BG_COLOR_SYSTEM"),
                                    NSLocalizedString("READER_BG_COLOR_AUTO"),
                                    NSLocalizedString("READER_BG_COLOR_WHITE"),
                                    NSLocalizedString("READER_BG_COLOR_BLACK")
                                ]
                            ))
                        )
                    )
                    if UIDevice.current.userInterfaceIdiom != .pad {
                        SettingView(
                            setting: .init(
                                key: "Reader.orientation",
                                title: NSLocalizedString("READER_ORIENTATION"),
                                notification: "Reader.orientation",
                                value: .select(.init(
                                    values: ["device", "portrait", "landscape"],
                                    titles: [
                                        NSLocalizedString("FOLLOW_DEVICE"),
                                        NSLocalizedString("PORTRAIT"),
                                        NSLocalizedString("LANDSCAPE")
                                    ]
                                ))
                            )
                        )
                    }
                }

                if reader != .text {
                    Section("Translation") {
                        SettingView(
                            setting: .init(
                                key: "Reader.translate",
                                title: "Translate pages",
                                notification: "Nyora.translationSettingsChanged",
                                value: .toggle(.init())
                            )
                        )
                        SettingView(
                            setting: .init(
                                key: "Reader.translateTarget",
                                title: "Translate to",
                                notification: "Nyora.translationSettingsChanged",
                                value: .select(.init(
                                    values: TranslationConfig.supportedLanguages.filter { $0 != "AUTO" },
                                    titles: TranslationConfig.supportedLanguages.filter { $0 != "AUTO" }
                                ))
                            )
                        )
                        SettingView(
                            setting: .init(
                                key: "Reader.translateUseAI",
                                title: "Refine with Apple Intelligence",
                                notification: "Nyora.translationSettingsChanged",
                                value: .toggle(.init())
                            )
                        )
                    }
                }

                Section {
                    NavigationLink(destination: TapZonesSelectView()) {
                        HStack {
                            Text(NSLocalizedString("TAP_ZONES"))
                            Spacer()
                            Text(tapZones.title)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if tapZones == .grid {
                        NavigationLink(destination: TapGridConfigView()) {
                            Text(NSLocalizedString("CONFIGURE_TAP_GRID"))
                        }
                    }

                    SettingView(
                        setting: .init(
                            key: "Reader.invertTapZones",
                            title: NSLocalizedString("INVERT_TAP_ZONES"),
                            value: .toggle(.init())
                        )
                    )

                    SettingView(
                        setting: .init(
                            key: "Reader.animation",
                            title: NSLocalizedString("PAGE_ANIMATION"),
                            value: .select(.init(
                                values: ["none", "slide", "advanced"],
                                titles: [
                                    NSLocalizedString("PAGE_ANIMATION_NONE"),
                                    NSLocalizedString("PAGE_ANIMATION_SLIDE"),
                                    NSLocalizedString("PAGE_ANIMATION_ADVANCED")
                                ]
                            ))
                        )
                    )
                } header: {
                    Text(NSLocalizedString("TAP_ZONES"))
                }

                if reader == .text {
                    // Text Reader Settings
                    Section(String(format: NSLocalizedString("%@_EXPERIMENTAL"), NSLocalizedString("TEXT_READER"))) {
                        SettingView(
                            setting: .init(
                                key: "Reader.textReaderStyle",
                                title: NSLocalizedString("TEXT_READER_STYLE"),
                                notification: .init("Reader.textReaderStyle"),
                                value: .select(.init(
                                    values: ["paged", "scroll"],
                                    titles: [
                                        NSLocalizedString("TEXT_READER_PAGED"),
                                        NSLocalizedString("TEXT_READER_SCROLL")
                                    ]
                                ))
                            )
                        )
                        SettingView(
                            setting: .init(
                                key: "Reader.textFontFamily",
                                title: NSLocalizedString("TEXT_FONT_FAMILY"),
                                notification: .init("Reader.textFontFamily"),
                                value: .select(.init(
                                    values: Self.availableFonts
                                ))
                            )
                        )
                        SettingView(
                            setting: .init(
                                key: "Reader.textFontSize",
                                title: NSLocalizedString("TEXT_FONT_SIZE"),
                                notification: .init("Reader.textFontSize"),
                                value: .stepper(.init(minimumValue: 12, maximumValue: 32, stepValue: 2))
                            )
                        )
                        SettingView(
                            setting: .init(
                                key: "Reader.textLineSpacing",
                                title: NSLocalizedString("TEXT_LINE_SPACING"),
                                notification: .init("Reader.textLineSpacing"),
                                value: .stepper(.init(minimumValue: 0, maximumValue: 24, stepValue: 2))
                            )
                        )
                        SettingView(
                            setting: .init(
                                key: "Reader.textHorizontalPadding",
                                title: NSLocalizedString("TEXT_HORIZONTAL_PADDING"),
                                notification: .init("Reader.textHorizontalPadding"),
                                value: .stepper(.init(minimumValue: 8, maximumValue: 48, stepValue: 4))
                            )
                        )
                    }
                } else {
                    if !downsampleImages.value {
                        Section {
                            SettingView(
                                setting: .init(
                                    key: "Reader.upscaleImages",
                                    title: String(format: NSLocalizedString("%@_EXPERIMENTAL"), NSLocalizedString("UPSCALE_IMAGES")),
                                    value: .toggle(.init())
                                )
                            )
                            if upscaleImages.value {
                                NavigationLink(destination: UpscaleModelListView()) {
                                    Text(NSLocalizedString("UPSCALING_MODELS"))
                                }
                                SettingView(
                                    setting: .init(
                                        key: "Reader.upscaleMaxHeight",
                                        title: NSLocalizedString("UPSCALE_MAX_IMAGE_HEIGHT"),
                                        value: .stepper(.init(
                                            minimumValue: 200,
                                            maximumValue: 4000,
                                            stepValue: 100
                                        ))
                                    )
                                )
                            }
                        } header: {
                            Text(NSLocalizedString("UPSCALING"))
                        } footer: {
                            if upscaleImages.value {
                                Text(NSLocalizedString("UPSCALE_MAX_IMAGE_HEIGHT_TEXT"))
                            }
                        }
                    }

                    if readingMode == .rtl || readingMode == .ltr || readingMode == .vertical || readingMode == nil {
                        Section(NSLocalizedString("PAGED")) {
                            SettingView(
                                setting: .init(
                                    key: "Reader.pagesToPreload",
                                    title: NSLocalizedString("PAGES_TO_PRELOAD"),
                                    value: .stepper(.init(minimumValue: 1, maximumValue: 10))
                                )
                            )
                            SettingView(
                                setting: .init(
                                    key: "Reader.zoomMode",
                                    title: NSLocalizedString("ZOOM_MODE"),
                                    notification: .init("Reader.zoomMode"),
                                    value: .select(.init(
                                        values: ["fitCenter", "fitHeight", "fitWidth", "keepStart"],
                                        titles: [
                                            NSLocalizedString("ZOOM_FIT_CENTER"),
                                            NSLocalizedString("ZOOM_FIT_HEIGHT"),
                                            NSLocalizedString("ZOOM_FIT_WIDTH"),
                                            NSLocalizedString("ZOOM_KEEP_START")
                                        ]
                                    ))
                                )
                            )
                            SettingView(
                                setting: .init(
                                    key: "Reader.pagedPageLayout",
                                    title: NSLocalizedString("PAGE_LAYOUT"),
                                    value: .select(.init(
                                        values: ["single", "double", "auto"],
                                        titles: [
                                            NSLocalizedString("SINGLE_PAGE"),
                                            NSLocalizedString("DOUBLE_PAGE"),
                                            NSLocalizedString("AUTOMATIC")
                                        ]
                                    ))
                                )
                            )
                            let pageOffsetKey = "Reader.pagedPageOffset.\(mangaId)"
                            SettingView(
                                setting: .init(
                                    key: pageOffsetKey,
                                    title: NSLocalizedString("PAGE_OFFSET"),
                                    notification: .init(pageOffsetKey),
                                    value: .toggle(.init())
                                )
                            )
                            SettingView(
                                setting: .init(
                                    key: "Reader.splitWideImages",
                                    title: NSLocalizedString("SPLIT_WIDE_IMAGES"),
                                    notification: .init("Reader.splitWideImages"),
                                    value: .toggle(.init())
                                )
                            )
                            if splitWideImages.value {
                                SettingView(
                                    setting: .init(
                                        key: "Reader.reverseSplitOrder",
                                        title: NSLocalizedString("REVERSE_SPLIT_ORDER"),
                                        notification: .init("Reader.reverseSplitOrder"),
                                        value: .toggle(.init())
                                    )
                                )
                            }
                        }
                    }

                    if readingMode == .webtoon || readingMode == .continuous || readingMode == nil {
                        Section {
                            SettingView(
                                setting: .init(
                                    key: "Reader.verticalInfiniteScroll",
                                    title: NSLocalizedString("INFINITE_VERTICAL_SCROLL"),
                                    value: .toggle(.init())
                                )
                            )
                            SettingView(
                                setting: .init(
                                    key: "Reader.pillarbox",
                                    title: NSLocalizedString("PILLARBOX"),
                                    value: .toggle(.init())
                                )
                            )
                            SettingView(
                                setting: .init(
                                    key: "Reader.pillarboxAmount",
                                    title: NSLocalizedString("PILLARBOX_AMOUNT"),
                                    requires: "Reader.pillarbox",
                                    value: .stepper(.init(minimumValue: 5, maximumValue: 95, stepValue: 5))
                                )
                            )
                            SettingView(
                                setting: .init(
                                    key: "Reader.pillarboxOrientation",
                                    title: NSLocalizedString("PILLARBOX_ORIENTATION"),
                                    requires: "Reader.pillarbox",
                                    value: .select(.init(
                                        values: ["both", "portrait", "landscape"],
                                        titles: [
                                            NSLocalizedString("BOTH"),
                                            NSLocalizedString("PORTRAIT"),
                                            NSLocalizedString("LANDSCAPE")
                                        ]
                                    ))
                                )
                            )
                        } header: {
                            Text(NSLocalizedString("WEBTOON"))
                        } footer: {
                            Text(NSLocalizedString("PILLARBOX_ORIENTATION_INFO"))
                        }
                    }
                }
            }
            .animation(.default, value: downsampleImages.value)
            .animation(.default, value: upscaleImages.value)
            .animation(.default, value: splitWideImages.value)
            .navigationTitle(NSLocalizedString("READER_SETTINGS"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton {
                        dismiss()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .readerReadingMode)) { _ in
                readingMode = UserDefaults.standard.string(forKey: "Reader.readingMode.\(mangaId)").flatMap(ReadingMode.init)
            }
            .onReceive(NotificationCenter.default.publisher(for: .readerTapZones)) { _ in
                tapZones = UserDefaults.standard.string(forKey: "Reader.tapZones").flatMap(DefaultTapZones.init) ?? .disabled
            }
        }
    }
}
