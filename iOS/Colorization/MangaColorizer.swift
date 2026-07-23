//
//  MangaColorizer.swift
//  Nyora (iOS)
//
//  Local, integrity-checked ONNX manga colourization. The model, tensor
//  contract, resize/pad geometry, and luminance/chroma composition intentionally
//  match Nyora Web, macOS, Android, Windows, and Linux.
//

import CoreGraphics
import CryptoKit
import Foundation
import OnnxRuntimeBindings

enum ColorizationError: LocalizedError {
    case modelMissing
    case modelIntegrity
    case modelDownload(String)
    case insufficientStorage
    case invalidImage
    case inputTooLarge
    case tooManyTiles
    case outputInvalid

    var errorDescription: String? {
        switch self {
        case .modelMissing:
            return "Download the colorization model in Settings before enabling this feature."
        case .modelIntegrity:
            return "The colorization model failed its integrity check."
        case let .modelDownload(message):
            return "Colorization model download failed: \(message)"
        case .insufficientStorage:
            return "There is not enough free storage to download the colorization model."
        case .invalidImage:
            return "This page image cannot be colorized."
        case .inputTooLarge:
            return "This page is too large to colorize safely on this device."
        case .tooManyTiles:
            return "This page is too long to colorize safely on this device."
        case .outputInvalid:
            return "The colorization model produced an invalid result."
        }
    }
}

enum ColorizationModelSpec {
    // Pinned Hugging Face revision + independently verified digest. Never use a
    // mutable /resolve/main endpoint for executable model bytes.
    static let url = URL(string: "https://huggingface.co/Faridzar/manga-colorization-v2-onnx/resolve/5515e06d31b08ffd107af686cba5e98e95e8d4cf/manga-colorize-fp16.onnx")!
    static let filename = "manga-colorize-v2-fp16.onnx"
    static let byteCount: Int64 = 61_650_260
    static let sha256 = "39660d0047ea6f1a0ddee6aa89054997f95ea566f4d56ff762f66dbcf1a1a7ef"
}

/// Serializes access to the persistent model cache. The cache is trusted only
/// after its exact length and SHA-256 have passed in this app process.
actor ColorizationModelStore {
    static let shared = ColorizationModelStore()

    private var verifiedModelURL: URL?

    nonisolated static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("Nyora/models", isDirectory: true)
    }

    nonisolated static var localModelURL: URL {
        directory.appendingPathComponent(ColorizationModelSpec.filename, isDirectory: false)
    }

    /// Returns a verified cached model, or nil when there is no valid local copy.
    func validatedModelURL() throws -> URL? {
        let destination = Self.localModelURL
        let fm = FileManager.default

        if verifiedModelURL == destination, fm.fileExists(atPath: destination.path) {
            return destination
        }
        guard fm.fileExists(atPath: destination.path) else { return nil }

        guard try isExpectedModelFile(destination) else {
            // A corrupt cache must never survive to a later launch. It is an
            // internal, regenerable cache, so removing it is safer than letting
            // ONNX Runtime attempt to parse untrusted bytes.
            try? fm.removeItem(at: destination)
            verifiedModelURL = nil
            return nil
        }
        verifiedModelURL = destination
        return destination
    }

    /// User-initiated settings download. It first accepts an already-valid
    /// cached file, otherwise downloads to a temporary file, verifies it, then
    /// atomically promotes it into Application Support.
    func downloadAndValidate(progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        if let existing = try validatedModelURL() { return existing }

        let fm = FileManager.default
        let directory = Self.directory
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try ensureStorage(in: directory)

        let temporary = try await download(progress: progress)
        defer { try? fm.removeItem(at: temporary) }

        try Task.checkCancellation()
        guard try isExpectedModelFile(temporary) else { throw ColorizationError.modelIntegrity }
        try Task.checkCancellation()

        // Moving the verified download into the destination directory first
        // keeps the final promotion within one filesystem. A reader can only see
        // either the previously verified copy or the new verified copy.
        let staged = directory.appendingPathComponent(".\(ColorizationModelSpec.filename).\(UUID().uuidString).partial")
        try fm.moveItem(at: temporary, to: staged)
        do {
            let destination = Self.localModelURL
            if fm.fileExists(atPath: destination.path) {
                // `replaceItemAt` keeps a previously verified destination in
                // place until the staged, hash-checked file can replace it.
                // Never create a delete-then-move window that could leave a
                // reader without a usable model after an interrupted update.
                _ = try fm.replaceItemAt(destination, withItemAt: staged, backupItemName: nil)
            } else {
                try fm.moveItem(at: staged, to: destination)
            }
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableDestination = destination
            try? mutableDestination.setResourceValues(values)
            verifiedModelURL = destination
            progress(1)
            return destination
        } catch {
            try? fm.removeItem(at: staged)
            throw error
        }
    }

    func deleteModel() throws {
        let destination = Self.localModelURL
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        verifiedModelURL = nil
    }

    private func isExpectedModelFile(_ url: URL) throws -> Bool {
        let values = try FileManager.default.attributesOfItem(atPath: url.path)
        let bytes = (values[.size] as? NSNumber)?.int64Value ?? -1
        guard bytes == ColorizationModelSpec.byteCount else { return false }
        return try Self.sha256(of: url) == ColorizationModelSpec.sha256
    }

    private func ensureStorage(in directory: URL) throws {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey]
        if let values = try? directory.resourceValues(forKeys: keys),
           let available = values.volumeAvailableCapacityForImportantUsage {
            // Keep enough room for both the final 62 MB model and its temporary
            // download; this avoids filling the app container mid-download.
            let required = ColorizationModelSpec.byteCount * 2 + 32 * 1_024 * 1_024
            guard available >= required else { throw ColorizationError.insufficientStorage }
        }
    }

    private func download(progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let delegate = ColorizationDownloadDelegate(expectedByteCount: ColorizationModelSpec.byteCount, progress: progress)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 15 * 60
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: ColorizationModelSpec.url)
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let task = session.downloadTask(with: request)
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                delegate.start(task: task, continuation: continuation)
                task.resume()
            }
        }, onCancel: {
            delegate.cancel()
        })
    }

    nonisolated private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// URLSession's delegate callbacks arrive on a non-Swift-concurrency queue, so
/// this tiny object uses a lock solely to guarantee its continuation is resumed
/// exactly once across cancellation, HTTP failures, and completion.
private final class ColorizationDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let expectedByteCount: Int64
    private let progress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private weak var task: URLSessionDownloadTask?
    private var redirectCount = 0

    init(expectedByteCount: Int64, progress: @escaping @Sendable (Double) -> Void) {
        self.expectedByteCount = expectedByteCount
        self.progress = progress
    }

    func start(task: URLSessionDownloadTask, continuation: CheckedContinuation<URL, Error>) {
        lock.lock()
        self.task = task
        self.continuation = continuation
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        let task = task
        lock.unlock()
        task?.cancel()
        finish(.failure(CancellationError()))
    }

    /// The model endpoint is pinned, but Hugging Face legitimately redirects
    /// large files to its HTTPS delivery hosts. Permit only that trust domain,
    /// reject credential-bearing URLs and HTTP downgrades, and cap redirect
    /// chains before a request can be bounced indefinitely.
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let destination = request.url, isPermittedModelDownloadURL(destination) else {
            completionHandler(nil)
            finish(.failure(ColorizationError.modelDownload("unsafe download redirect rejected")))
            return
        }

        lock.lock()
        redirectCount += 1
        let allowed = redirectCount <= 5
        lock.unlock()
        guard allowed else {
            completionHandler(nil)
            finish(.failure(ColorizationError.modelDownload("too many download redirects")))
            return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        // `URLSessionDownloadDelegate` does not receive the data-delegate
        // response-disposition callback. Validate the final response as soon
        // as it is available here, then validate it again before promoting the
        // completed temporary file below.
        if let response = downloadTask.response {
            do {
                try validateResponse(response)
            } catch {
                downloadTask.cancel()
                finish(.failure(error))
                return
            }
        }
        if totalBytesWritten > expectedByteCount {
            downloadTask.cancel()
            finish(.failure(ColorizationError.modelIntegrity))
            return
        }
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedByteCount
        progress(min(1, max(0, Double(totalBytesWritten) / Double(max(1, total)))) )
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        do {
            try validateResponse(downloadTask.response)
            let attrs = try FileManager.default.attributesOfItem(atPath: location.path)
            let bytes = (attrs[.size] as? NSNumber)?.int64Value ?? -1
            guard bytes == expectedByteCount else { throw ColorizationError.modelIntegrity }
            let temporaryDirectory = FileManager.default.temporaryDirectory
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            let temporary = temporaryDirectory
                .appendingPathComponent("nyora-colorization-\(UUID().uuidString)")
                .appendingPathExtension("onnx")
            try FileManager.default.moveItem(at: location, to: temporary)
            finish(.success(temporary))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }

    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        task = nil
        lock.unlock()
        guard let continuation else { return }
        switch result {
        case let .success(url): continuation.resume(returning: url)
        case let .failure(error): continuation.resume(throwing: error)
        }
    }

    private func validateResponse(_ response: URLResponse?) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ColorizationError.modelDownload("server returned an invalid HTTP response")
        }
        let length = http.expectedContentLength
        if length > 0, length != expectedByteCount {
            throw ColorizationError.modelIntegrity
        }
    }

    private func isPermittedModelDownloadURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              url.user == nil,
              url.password == nil
        else {
            return false
        }
        // The exact model bytes are SHA-256 checked after download. This list
        // is deliberately still narrow so a redirect cannot consume bandwidth
        // from an arbitrary host before the integrity check rejects it.
        return host == "huggingface.co"
            || host.hasSuffix(".huggingface.co")
            || host == "hf.co"
            || host.hasSuffix(".hf.co")
    }
}

/// Owns the non-Sendable ONNX Runtime session and serializes inferences. One
/// forward pass at a time keeps peak memory bounded when reader pages are
/// preloaded or reused rapidly.
actor MangaColorizer {
    static let shared = MangaColorizer()

    private var environment: ORTEnv?
    private var session: ORTSession?
    private var loadedPath: String?

    func colorize(cgImage: CGImage, modelURL: URL) throws -> CGImage {
        try Task.checkCancellation()
        try validateInput(cgImage)
        try ensureSession(modelURL: modelURL)
        let maxModelPixels = ColorizationPipeline.maxModelPixels
        guard let geometry = ColorizationPipeline.geometry(width: cgImage.width, height: cgImage.height) else {
            throw ColorizationError.invalidImage
        }
        if geometry.pixelCount <= maxModelPixels,
           geometry.width <= ColorizationPipeline.maxModelSide,
           geometry.height <= ColorizationPipeline.maxModelSide {
            return try colorizeOne(cgImage)
        }
        return try colorizeTiled(cgImage, maxModelPixels: maxModelPixels)
    }

    func unload() {
        // Actor isolation means an unload waits for a currently running forward
        // pass instead of closing the native session underneath it.
        session = nil
        environment = nil
        loadedPath = nil
    }

    private func validateInput(_ image: CGImage) throws {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { throw ColorizationError.invalidImage }
        guard width <= ColorizationPipeline.maxSourceSide,
              height <= ColorizationPipeline.maxSourceSide else { throw ColorizationError.inputTooLarge }
        let pixels = width.multipliedReportingOverflow(by: height)
        guard !pixels.overflow, pixels.partialValue <= ColorizationPipeline.maxInputPixels else {
            throw ColorizationError.inputTooLarge
        }
    }

    private func ensureSession(modelURL: URL) throws {
        if session != nil, loadedPath == modelURL.path { return }

        // CPU is deliberately the baseline. The reference Android app found
        // some mobile accelerator drivers produce grayscale/incorrect results
        // for this fp16 GAN; CPU gives deterministic parity and the actor keeps
        // it from competing with rendering. A future Core ML provider can be
        // enabled only after device-matrix output validation.
        let environment = try ORTEnv(loggingLevel: ORTLoggingLevel.warning)
        let options = try ORTSessionOptions()
        try? options.setGraphOptimizationLevel(ORTGraphOptimizationLevel.all)
        let threads = min(4, max(1, ProcessInfo.processInfo.activeProcessorCount - 1))
        try? options.setIntraOpNumThreads(Int32(threads))
        session = try ORTSession(env: environment, modelPath: modelURL.path, sessionOptions: options)
        self.environment = environment
        loadedPath = modelURL.path
    }

    private func colorizeOne(_ original: CGImage) throws -> CGImage {
        try Task.checkCancellation()
        guard let prepared = ColorizationPipeline.preprocess(original) else {
            throw ColorizationError.invalidImage
        }
        let output = try run(input: prepared.input, height: prepared.modelHeight, width: prepared.modelWidth)
        try Task.checkCancellation()
        guard let image = ColorizationPipeline.postprocess(original: original, rgb: output, prepared: prepared) else {
            throw ColorizationError.outputInvalid
        }
        return image
    }

    private func colorizeTiled(_ original: CGImage, maxModelPixels: Int) throws -> CGImage {
        let width = original.width
        let height = original.height
        let vertical = height >= width
        let longSide = vertical ? height : width
        let fixedSide = vertical ? width : height

        // Binary search the largest source tile that stays within the ONNX
        // tensor budget. This supports tall webtoon strips without allocating a
        // gigantic [1,5,H,W] tensor for the full strip.
        var low = 128
        var high = longSide
        var largest = 0
        while low <= high {
            let middle = low + (high - low) / 2
            let candidateWidth = vertical ? fixedSide : middle
            let candidateHeight = vertical ? middle : fixedSide
            if let geometry = ColorizationPipeline.geometry(width: candidateWidth, height: candidateHeight),
               geometry.pixelCount <= maxModelPixels,
               geometry.width <= ColorizationPipeline.maxModelSide,
               geometry.height <= ColorizationPipeline.maxModelSide {
                largest = middle
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        guard largest >= min(longSide, 128) else { throw ColorizationError.inputTooLarge }
        let coreLength = min(longSide, largest)
        let tileCount = Int(ceil(Double(longSide) / Double(coreLength)))
        guard tileCount <= ColorizationPipeline.maxTileCount else { throw ColorizationError.tooManyTiles }
        let overlap = min(96, max(24, coreLength / 12))

        guard let output = ColorizationPipeline.makeContext(width: width, height: height) else {
            throw ColorizationError.invalidImage
        }
        output.setFillColor(CGColor(gray: 1, alpha: 1))
        output.fill(CGRect(x: 0, y: 0, width: width, height: height))

        var coreStart = 0
        while coreStart < longSide {
            try Task.checkCancellation()
            let coreEnd = min(longSide, coreStart + coreLength)
            let tileStart = max(0, coreStart - overlap)
            let tileEnd = min(longSide, coreEnd + overlap)
            let tileRect: CGRect
            if vertical {
                tileRect = CGRect(x: 0, y: tileStart, width: width, height: tileEnd - tileStart)
            } else {
                tileRect = CGRect(x: tileStart, y: 0, width: tileEnd - tileStart, height: height)
            }
            guard let tile = original.cropping(to: tileRect) else { throw ColorizationError.invalidImage }
            let colorizedTile = try colorizeOne(tile)
            let coreRect: CGRect
            if vertical {
                coreRect = CGRect(x: 0, y: coreStart - tileStart, width: width, height: coreEnd - coreStart)
            } else {
                coreRect = CGRect(x: coreStart - tileStart, y: 0, width: coreEnd - coreStart, height: height)
            }
            guard let core = colorizedTile.cropping(to: coreRect) else { throw ColorizationError.outputInvalid }

            // CGContext coordinates are bottom-left while CGImage crop rects are
            // top-left. Convert only the destination Y coordinate.
            let destination = vertical
                ? CGRect(x: 0, y: height - coreEnd, width: width, height: coreEnd - coreStart)
                : CGRect(x: coreStart, y: 0, width: coreEnd - coreStart, height: height)
            output.interpolationQuality = .none
            output.draw(core, in: destination)
            coreStart = coreEnd
        }
        guard let image = output.makeImage() else { throw ColorizationError.outputInvalid }
        return image
    }

    private func run(input: [Float], height: Int, width: Int) throws -> [Float] {
        guard let session else { throw ColorizationError.modelMissing }
        let data = input.withUnsafeBufferPointer {
            NSMutableData(bytes: $0.baseAddress!, length: $0.count * MemoryLayout<Float>.stride)
        }
        let shape: [NSNumber] = [1, 5, NSNumber(value: height), NSNumber(value: width)]
        let value = try ORTValue(tensorData: data, elementType: ORTTensorElementDataType.float, shape: shape)
        let outputs = try session.run(withInputs: ["input": value], outputNames: ["rgb"], runOptions: nil)
        guard let rgb = outputs["rgb"] else { throw ColorizationError.outputInvalid }
        let tensor = try rgb.tensorData() as Data
        let expected = 3 * width * height
        guard tensor.count >= expected * MemoryLayout<Float>.stride else { throw ColorizationError.outputInvalid }
        return tensor.withUnsafeBytes { raw in
            Array(UnsafeBufferPointer(start: raw.bindMemory(to: Float.self).baseAddress!, count: expected))
        }
    }
}

private enum ColorizationPipeline {
    struct Geometry {
        let width: Int
        let height: Int
        var pixelCount: Int { width * height }
    }

    struct Prepared {
        let input: [Float] // [1,5,H,W], channel 0 grayscale; hint channels 1...4 are zero.
        let modelWidth: Int
        let modelHeight: Int
        let validWidth: Int
        let validHeight: Int
        let originalWidth: Int
        let originalHeight: Int
    }

    static let maxSourceSide = 16_384
    static let maxModelSide = 8_192
    static let maxTileCount = 12

    static var maxInputPixels: Int {
        // Full-resolution input, output, and blend buffers coexist briefly.
        // Reserve extra headroom on lower-RAM devices rather than risking an
        // OS jetsam termination during a reader page turn.
        let memory = ProcessInfo.processInfo.physicalMemory
        if memory >= 6_000_000_000 { return 10_000_000 }
        if memory >= 4_000_000_000 { return 8_000_000 }
        return 5_000_000
    }

    static var maxModelPixels: Int {
        ProcessInfo.processInfo.physicalMemory >= 6_000_000_000 ? 1_843_200 : 1_152_000
    }

    static func geometry(width: Int, height: Int) -> Geometry? {
        guard width > 0, height > 0 else { return nil }
        let size = 576.0
        let validWidth: Int
        let validHeight: Int
        if height < width {
            validHeight = 864
            validWidth = Int(ceil(Double(width) / (Double(height) / 864.0)))
        } else {
            validWidth = 576
            validHeight = Int(ceil(Double(height) / (Double(width) / size)))
        }
        guard validWidth > 0, validHeight > 0, validWidth <= 1_000_000, validHeight <= 1_000_000 else {
            return nil
        }
        let modelWidth = max(32, Int(ceil(Double(validWidth) / 32.0)) * 32)
        let modelHeight = max(32, Int(ceil(Double(validHeight) / 32.0)) * 32)
        let product = modelWidth.multipliedReportingOverflow(by: modelHeight)
        guard !product.overflow else { return nil }
        return Geometry(width: modelWidth, height: modelHeight)
    }

    static func preprocess(_ image: CGImage) -> Prepared? {
        let originalWidth = image.width
        let originalHeight = image.height
        guard let geometry = geometry(width: originalWidth, height: originalHeight) else { return nil }

        let validWidth: Int
        let validHeight: Int
        if originalHeight < originalWidth {
            validHeight = 864
            validWidth = Int(ceil(Double(originalWidth) / (Double(originalHeight) / 864.0)))
        } else {
            validWidth = 576
            validHeight = Int(ceil(Double(originalHeight) / (Double(originalWidth) / 576.0)))
        }

        guard let context = makeContext(width: geometry.width, height: geometry.height), let buffer = context.data else {
            return nil
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: geometry.width, height: geometry.height))
        context.interpolationQuality = .high
        // Put the valid page at the top-left, leaving white padding on the
        // right/bottom. The context coordinate conversion is deliberate.
        context.draw(image, in: CGRect(x: 0, y: geometry.height - validHeight, width: validWidth, height: validHeight))

        let bytesPerRow = context.bytesPerRow
        let pixels = buffer.bindMemory(to: UInt8.self, capacity: bytesPerRow * geometry.height)
        let plane = geometry.pixelCount
        var input = [Float](repeating: 0, count: plane * 5)
        input.withUnsafeMutableBufferPointer { destination in
            let destination = destination.baseAddress!
            DispatchQueue.concurrentPerform(iterations: geometry.height) { y in
                let row = y * bytesPerRow
                for x in 0..<geometry.width {
                    let sourceIndex = row + x * 4
                    let red = Float(pixels[sourceIndex])
                    let green = Float(pixels[sourceIndex + 1])
                    let blue = Float(pixels[sourceIndex + 2])
                    destination[y * geometry.width + x] = (0.299 * red + 0.587 * green + 0.114 * blue) / 255.0
                }
            }
        }
        return Prepared(
            input: input,
            modelWidth: geometry.width,
            modelHeight: geometry.height,
            validWidth: validWidth,
            validHeight: validHeight,
            originalWidth: originalWidth,
            originalHeight: originalHeight
        )
    }

    static func postprocess(original: CGImage, rgb: [Float], prepared: Prepared) -> CGImage? {
        let modelWidth = prepared.modelWidth
        let modelHeight = prepared.modelHeight
        let plane = modelWidth * modelHeight
        guard rgb.count >= 3 * plane else { return nil }

        guard let modelContext = makeContext(width: modelWidth, height: modelHeight), let modelBuffer = modelContext.data else {
            return nil
        }
        let modelBytesPerRow = modelContext.bytesPerRow
        let modelPixels = modelBuffer.bindMemory(to: UInt8.self, capacity: modelBytesPerRow * modelHeight)
        DispatchQueue.concurrentPerform(iterations: modelHeight) { y in
            let row = y * modelBytesPerRow
            for x in 0..<modelWidth {
                let i = y * modelWidth + x
                let p = row + x * 4
                modelPixels[p] = clamp255(rgb[i] * 255)
                modelPixels[p + 1] = clamp255(rgb[plane + i] * 255)
                modelPixels[p + 2] = clamp255(rgb[2 * plane + i] * 255)
                modelPixels[p + 3] = 255
            }
        }
        guard let modelImage = modelContext.makeImage(),
              let unpadded = modelImage.cropping(to: CGRect(x: 0, y: 0, width: prepared.validWidth, height: prepared.validHeight)),
              let upscaledContext = makeContext(width: prepared.originalWidth, height: prepared.originalHeight),
              let upscaledBuffer = upscaledContext.data,
              let sourceContext = makeContext(width: prepared.originalWidth, height: prepared.originalHeight),
              let sourceBuffer = sourceContext.data,
              let outputContext = makeContext(width: prepared.originalWidth, height: prepared.originalHeight),
              let outputBuffer = outputContext.data else {
            return nil
        }

        upscaledContext.interpolationQuality = .high
        upscaledContext.draw(unpadded, in: CGRect(x: 0, y: 0, width: prepared.originalWidth, height: prepared.originalHeight))
        sourceContext.draw(original, in: CGRect(x: 0, y: 0, width: prepared.originalWidth, height: prepared.originalHeight))

        let upscaled = upscaledBuffer.bindMemory(to: UInt8.self, capacity: upscaledContext.bytesPerRow * prepared.originalHeight)
        let source = sourceBuffer.bindMemory(to: UInt8.self, capacity: sourceContext.bytesPerRow * prepared.originalHeight)
        let output = outputBuffer.bindMemory(to: UInt8.self, capacity: outputContext.bytesPerRow * prepared.originalHeight)
        let saturation: Float = 1.28
        DispatchQueue.concurrentPerform(iterations: prepared.originalHeight) { y in
            let sourceRow = y * sourceContext.bytesPerRow
            let upscaledRow = y * upscaledContext.bytesPerRow
            let outputRow = y * outputContext.bytesPerRow
            for x in 0..<prepared.originalWidth {
                let s = sourceRow + x * 4
                let c = upscaledRow + x * 4
                let o = outputRow + x * 4
                let sr = Float(source[s])
                let sg = Float(source[s + 1])
                let sb = Float(source[s + 2])
                let luminance = 0.299 * sr + 0.587 * sg + 0.114 * sb
                let cr = Float(upscaled[c])
                let cg = Float(upscaled[c + 1])
                let cb = Float(upscaled[c + 2])
                let chromaBlue = (-0.168736 * cr - 0.331264 * cg + 0.5 * cb) * saturation
                let chromaRed = (0.5 * cr - 0.418688 * cg - 0.081312 * cb) * saturation
                output[o] = clamp255(luminance + 1.402 * chromaRed)
                output[o + 1] = clamp255(luminance - 0.344136 * chromaBlue - 0.714136 * chromaRed)
                output[o + 2] = clamp255(luminance + 1.772 * chromaBlue)
                output[o + 3] = 255
            }
        }
        return outputContext.makeImage()
    }

    static func makeContext(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0 else { return nil }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            // Big-endian RGBA byte layout is explicit; default byte order is
            // platform-dependent and would swap channels on some devices.
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue
        )
    }

    static func clamp255(_ value: Float) -> UInt8 {
        if value <= 0 { return 0 }
        if value >= 255 { return 255 }
        return UInt8(value)
    }
}
