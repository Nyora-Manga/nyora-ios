//
//  ColorizationController.swift
//  Nyora (iOS)
//

import Combine
import Foundation
import UIKit

extension Notification.Name {
    /// Visible paged and webtoon reader cells listen for this and either start
    /// colorizing their current source page or restore its original image.
    static let colorizationSettingsChanged = Notification.Name("Nyora.colorizationSettingsChanged")
}

enum ColorizationModelStatus: Equatable {
    case checking
    case notInstalled
    case downloading(Double)
    case ready
    case failed(String)
}

/// Main-actor bridge between Settings/reader UIKit code and the isolated model
/// store + ONNX engine. It deliberately performs no automatic model download:
/// a user must download and verify the 62 MB weight file in Settings first.
@MainActor
final class ColorizationController: ObservableObject {
    static let shared = ColorizationController()

    @Published private(set) var modelStatus: ColorizationModelStatus = .checking
    @Published private(set) var lastNonfatalError: String?
    @Published private(set) var enabled: Bool

    private enum Keys {
        static let enabled = "Reader.colorize"
    }

    private struct CachedOutput {
        let image: UIImage
        let cost: Int
    }

    private let store = ColorizationModelStore.shared
    private let engine = MangaColorizer.shared
    private var isDownloading = false
    private var outputCache: [String: CachedOutput] = [:]
    private var outputCacheOrder: [String] = []
    private var outputCacheCost = 0
    // Several visible reader cells can request the same page while UIKit/Texture
    // is laying out neighbouring cells. Keep exactly one model pass per cache
    // identity rather than queuing identical, memory-heavy ONNX runs.
    private var inFlightColorizations: [String: Task<UIImage?, Never>] = [:]
    private var cacheEpoch = 0
    private var memoryWarningObserver: NSObjectProtocol?

    private var outputCacheLimit: Int {
        ProcessInfo.processInfo.physicalMemory >= 6_000_000_000 ? 96 * 1_024 * 1_024 : 48 * 1_024 * 1_024
    }
    private let outputCacheCountLimit = 8

    private init() {
        enabled = UserDefaults.standard.bool(forKey: Keys.enabled)
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.clearOutputCache()
            }
        }
        Task { [weak self] in
            await self?.refreshModelStatus()
        }
    }

    deinit {
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
    }

    var isModelReady: Bool {
        if case .ready = modelStatus { return true }
        return false
    }

    var isDownloadingModel: Bool { isDownloading }

    /// Enables only a verified local model. This closes the stale-preference
    /// loophole where a reader button might otherwise attempt an unsolicited
    /// 62 MB download while the user is reading.
    func setEnabled(_ enabled: Bool) {
        if enabled {
            guard isModelReady else {
                lastNonfatalError = "Download the colorization model in Settings first."
                postChanged()
                return
            }
            self.enabled = true
            UserDefaults.standard.set(true, forKey: Keys.enabled)
        } else {
            self.enabled = false
            UserDefaults.standard.set(false, forKey: Keys.enabled)
            clearOutputCache()
        }
        postChanged()
    }

    func refreshModelStatus() async {
        guard !isDownloading else { return }
        modelStatus = .checking
        do {
            if try await store.validatedModelURL() != nil {
                modelStatus = .ready
            } else {
                modelStatus = .notInstalled
                if enabled {
                    enabled = false
                    UserDefaults.standard.set(false, forKey: Keys.enabled)
                }
            }
        } catch {
            modelStatus = .failed(error.localizedDescription)
            if enabled {
                enabled = false
                UserDefaults.standard.set(false, forKey: Keys.enabled)
            }
        }
        postChanged()
    }

    /// Explicit Settings action. It never changes the reading toggle itself;
    /// the user decides whether to enable colorization after the verified
    /// download completes.
    func downloadModel() async {
        guard !isDownloading else { return }
        isDownloading = true
        lastNonfatalError = nil
        modelStatus = .downloading(0)
        do {
            _ = try await store.downloadAndValidate { [weak self] fraction in
                Task { @MainActor [weak self] in
                    guard let self, self.isDownloading else { return }
                    self.modelStatus = .downloading(fraction)
                }
            }
            modelStatus = .ready
        } catch is CancellationError {
            modelStatus = .notInstalled
        } catch {
            modelStatus = .failed(error.localizedDescription)
        }
        isDownloading = false
        postChanged()
    }

    func deleteModel() async {
        // Queue session disposal before deleting the file so an in-flight ONNX
        // run can never read a model that has just been removed.
        await engine.unload()
        do {
            try await store.deleteModel()
            modelStatus = .notInstalled
            lastNonfatalError = nil
        } catch {
            modelStatus = .failed(error.localizedDescription)
        }
        enabled = false
        UserDefaults.standard.set(false, forKey: Keys.enabled)
        clearOutputCache()
        postChanged()
    }

    /// Colorize one already-decoded reader page. `cacheKey` must identify the
    /// page plus reader processing settings; caller-side generation guards make
    /// a late result harmless when a reused reader cell changes page.
    func colorize(_ source: UIImage, cacheKey: String) async -> UIImage? {
        guard enabled else { return nil }
        let cacheKey = "v2|\(cacheKey)"
        if let cached = cachedOutput(for: cacheKey) { return cached }
        guard source.cgImage != nil else {
            lastNonfatalError = ColorizationError.invalidImage.localizedDescription
            return nil
        }

        if let inFlight = inFlightColorizations[cacheKey] {
            let result = await inFlight.value
            return Task.isCancelled ? nil : result
        }

        let epoch = cacheEpoch
        let task: Task<UIImage?, Never> = Task { [weak self, source] () -> UIImage? in
            guard let self else { return nil }
            return await self.makeColorizedOutput(source, cacheKey: cacheKey, cacheEpoch: epoch)
        }
        inFlightColorizations[cacheKey] = task
        let result = await task.value
        // This task is the only producer for this key until it completes, so
        // removing the entry cannot discard a newer producer.
        inFlightColorizations.removeValue(forKey: cacheKey)
        return Task.isCancelled ? nil : result
    }

    private func makeColorizedOutput(_ source: UIImage, cacheKey: String, cacheEpoch: Int) async -> UIImage? {
        guard enabled, let cgImage = source.cgImage else { return nil }
        do {
            guard let modelURL = try await store.validatedModelURL() else {
                modelStatus = .notInstalled
                enabled = false
                UserDefaults.standard.set(false, forKey: Keys.enabled)
                postChanged()
                return nil
            }
            if !isModelReady { modelStatus = .ready }
            let output = try await engine.colorize(cgImage: cgImage, modelURL: modelURL)
            // A settings change while inference ran means do not retain or hand
            // a now-disallowed output back to a reader task.
            guard enabled else { return nil }
            let image = UIImage(cgImage: output, scale: source.scale, orientation: source.imageOrientation)
            // Do not repopulate a cache that was deliberately cleared because
            // of a memory warning or a page invalidation while inference ran.
            if cacheEpoch == self.cacheEpoch {
                storeOutput(image, for: cacheKey)
            }
            return image
        } catch is CancellationError {
            return nil
        } catch {
            handleColorizationError(error)
            return nil
        }
    }

    func invalidateOutputCache(pagePrefix: String) {
        cacheEpoch &+= 1
        let prefix = "v2|\(pagePrefix)"
        let keys = outputCache.keys.filter { $0.hasPrefix(prefix) }
        for key in keys { removeCachedOutput(for: key) }
    }

    func clearOutputCache() {
        cacheEpoch &+= 1
        outputCache.removeAll(keepingCapacity: false)
        outputCacheOrder.removeAll(keepingCapacity: false)
        outputCacheCost = 0
    }

    private func handleColorizationError(_ error: Error) {
        let localized = error.localizedDescription
        lastNonfatalError = localized
        switch error {
        case ColorizationError.modelMissing, ColorizationError.modelIntegrity:
            modelStatus = .notInstalled
            enabled = false
            UserDefaults.standard.set(false, forKey: Keys.enabled)
            postChanged()
        default:
            // A page that is too large or malformed should simply remain in its
            // original form. It is not a model failure and must not turn the
            // feature off for every other page in the chapter.
            break
        }
    }

    private func cachedOutput(for key: String) -> UIImage? {
        guard let cached = outputCache[key] else { return nil }
        touchCacheKey(key)
        return cached.image
    }

    private func storeOutput(_ image: UIImage, for key: String) {
        let cost = imageCost(image)
        guard cost > 0, cost <= outputCacheLimit else { return }
        removeCachedOutput(for: key)
        outputCache[key] = CachedOutput(image: image, cost: cost)
        outputCacheOrder.append(key)
        outputCacheCost += cost
        while outputCacheOrder.count > outputCacheCountLimit || outputCacheCost > outputCacheLimit {
            guard let oldest = outputCacheOrder.first else { break }
            removeCachedOutput(for: oldest)
        }
    }

    private func touchCacheKey(_ key: String) {
        outputCacheOrder.removeAll { $0 == key }
        outputCacheOrder.append(key)
    }

    private func removeCachedOutput(for key: String) {
        if let cached = outputCache.removeValue(forKey: key) {
            outputCacheCost = max(0, outputCacheCost - cached.cost)
        }
        outputCacheOrder.removeAll { $0 == key }
    }

    private func imageCost(_ image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        let product = cgImage.bytesPerRow.multipliedReportingOverflow(by: cgImage.height)
        guard !product.overflow else { return 0 }
        return product.partialValue
    }

    private func postChanged() {
        NotificationCenter.default.post(name: .colorizationSettingsChanged, object: nil)
    }
}
