// LocalWhisper.swift
// On-device OpenAI Whisper via WhisperKit (Core ML → Apple Neural Engine).
// No cloud API, no LLM. Lazy-load so idle MagicPad stays light.

import AVFoundation
import CoreMedia
import CoreML
import Foundation
import WhisperKit

final class LocalWhisper: @unchecked Sendable {
    static let shared = LocalWhisper()
    /// Prefer base when weights are complete; never leave the app without tiny as fallback.
    static var modelVariant: String { resolvedVariant() }

    private let lock = NSLock()
    private var kit: WhisperKit?
    private var _ready = false
    private var _loading = false
    private var _lastError = ""
    private var waiters: [(Bool, String?) -> Void] = []
    private var unloadWork: DispatchWorkItem?

    var isReady: Bool {
        lock.lock(); defer { lock.unlock() }
        return _ready
    }
    var isLoading: Bool {
        lock.lock(); defer { lock.unlock() }
        return _loading
    }
    var lastError: String {
        lock.lock(); defer { lock.unlock() }
        return _lastError
    }
    var modelLabel: String { Self.modelVariant }
    var isCached: Bool {
        lock.lock(); defer { lock.unlock() }
        return bundledOrCachedUnlocked()
    }
    private var _prefetching = false

    private init() {}

    /// HuggingFace is often blocked; WhisperKit's default endpoint is huggingface.co.
    /// Prefetch/download use this (env wins). Never logs the URL into health.
    static var hubEndpoint: String {
        let env = ProcessInfo.processInfo.environment["HF_ENDPOINT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return env.isEmpty ? "https://hf-mirror.com" : env
    }

    static func resolvedVariant() -> String {
        if folder(for: "base") != nil { return "base" }
        if folder(for: "tiny") != nil { return "tiny" }
        return "base"
    }

    /// Bundle first, then Application Support cache. Never logs home paths.
    static func bundledModelFolder() -> String? {
        guard let root = Bundle.main.resourceURL else { return nil }
        for name in ["openai_whisper-base", "openai_whisper-tiny"] {
            let url = root.appendingPathComponent("whisper/\(name)", isDirectory: true)
            if isCompleteModelFolder(url) { return url.path }
        }
        return nil
    }

    /// WhisperKit snapshot lands under models/argmaxinc/whisperkit-coreml/.
    /// Manual / vendor copy may sit at openai_whisper-tiny/ or openai_whisper-base/.
    static func resolvedModelFolder() -> String? {
        folder(for: "base") ?? folder(for: "tiny")
    }

    static func folder(for variant: String) -> String? {
        let name = "openai_whisper-\(variant)"
        var candidates: [URL] = []
        if let root = Bundle.main.resourceURL {
            candidates.append(root.appendingPathComponent("whisper/\(name)", isDirectory: true))
        }
        candidates.append(contentsOf: cachedCandidates(named: name))
        for url in candidates {
            if variant == "base" { seedTokenizerFromTiny(into: url) }
            if isCompleteModelFolder(url) { return url.path }
        }
        return nil
    }

    /// Multilingual Whisper tokenizers are shared across tiny/base. Copy so
    /// a Hub Core ML folder without tokenizer.json still counts as complete.
    static func seedTokenizerFromTiny(into dest: URL) {
        let tok = dest.appendingPathComponent("tokenizer.json")
        if FileManager.default.fileExists(atPath: tok.path) { return }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dest.path, isDirectory: &isDir), isDir.boolValue else {
            return
        }
        let names = [
            "tokenizer.json", "tokenizer_config.json", "vocab.json",
            "merges.txt", "special_tokens_map.json", "preprocessor_config.json",
        ]
        var tinyURL: URL?
        if let root = Bundle.main.resourceURL {
            let bundled = root.appendingPathComponent("whisper/openai_whisper-tiny", isDirectory: true)
            if FileManager.default.fileExists(atPath: bundled.appendingPathComponent("tokenizer.json").path) {
                tinyURL = bundled
            }
        }
        if tinyURL == nil {
            for url in cachedCandidates(named: "openai_whisper-tiny")
                where FileManager.default.fileExists(atPath: url.appendingPathComponent("tokenizer.json").path) {
                tinyURL = url
                break
            }
        }
        guard let tiny = tinyURL else { return }
        for name in names {
            let from = tiny.appendingPathComponent(name)
            let to = dest.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: from.path),
                  !FileManager.default.fileExists(atPath: to.path) else { continue }
            try? FileManager.default.copyItem(at: from, to: to)
        }
    }

    static func cachedModelCandidates() -> [URL] {
        cachedCandidates(named: "openai_whisper-base") + cachedCandidates(named: "openai_whisper-tiny")
    }

    static func cachedCandidates(named name: String) -> [URL] {
        let root = cacheDirectory()
        return [
            root.appendingPathComponent(name, isDirectory: true),
            root.appendingPathComponent("models/argmaxinc/whisperkit-coreml/\(name)", isDirectory: true),
        ]
    }

    static func isCompleteModelFolder(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        for name in ["MelSpectrogram.mlmodelc", "AudioEncoder.mlmodelc", "TextDecoder.mlmodelc"] {
            let p = url.appendingPathComponent(name, isDirectory: true)
            let core = p.appendingPathComponent("coremldata.bin")
            let weight = p.appendingPathComponent("weights/weight.bin")
            guard FileManager.default.fileExists(atPath: core.path)
                    || FileManager.default.fileExists(atPath: weight.path) else {
                return false
            }
        }
        // Hub folder has no tokenizer; first load must not hit huggingface.co.
        let tok = url.appendingPathComponent("tokenizer.json")
        return FileManager.default.fileExists(atPath: tok.path)
    }

    static func cacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("MagicPad/whisper", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func ensureReady(
        progress: ((String) -> Void)? = nil,
        completion: @escaping @Sendable (Bool, String?) -> Void
    ) {
        lock.lock()
        if _ready {
            lock.unlock()
            completion(true, nil)
            return
        }
        waiters.append(completion)
        if _loading {
            lock.unlock()
            return
        }
        _loading = true
        lock.unlock()
        progress?(bundledOrCachedUnlocked() ? "loading" : "downloading")

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let result: Result<WhisperKit, Error>
            do {
                result = .success(try await Self.makeKit())
            } catch {
                result = .failure(error)
            }
            DispatchQueue.global(qos: .userInitiated).async {
                switch result {
                case .success(let pipe):
                    self.finishLoad(pipe: pipe, error: nil)
                case .failure(let error):
                    self.finishLoad(pipe: nil, error: error)
                }
            }
        }
    }

    private func finishLoad(pipe: WhisperKit?, error: Error?) {
        lock.lock()
        if let pipe {
            kit = pipe
            _ready = true
            _loading = false
            _lastError = ""
            let done = waiters
            waiters.removeAll()
            lock.unlock()
            MagicLog.event("whisper ready model=\(Self.modelVariant) ane=1")
            done.forEach { $0(true, nil) }
            return
        }
        let msg = String((error?.localizedDescription ?? "load").prefix(80))
        kit = nil
        _ready = false
        _loading = false
        _lastError = msg
        let done = waiters
        waiters.removeAll()
        lock.unlock()
        MagicLog.event("whisper load failed: \(msg)")
        done.forEach { $0(false, "whisper_load") }
    }

    func transcribe(
        fileURL: URL,
        lang: String,
        completion: @escaping @Sendable (Bool, String, String?) -> Void
    ) {
        ensureReady { [weak self] ok, reason in
            guard let self else {
                completion(false, "", "whisper_unavailable")
                return
            }
            guard ok, let pipe = self.currentKit() else {
                completion(false, "", reason ?? "whisper_unavailable")
                return
            }
            self.bumpIdleUnload()
            Task.detached(priority: .userInitiated) {
                do {
                    let prepared = (try? Self.prepareAudioForWhisper(fileURL)) ?? fileURL
                    defer {
                        if prepared != fileURL {
                            try? FileManager.default.removeItem(at: prepared)
                        }
                    }
                    let opts = DecodingOptions(
                        verbose: false,
                        task: .transcribe,
                        language: Self.whisperLang(lang),
                        temperature: 0,
                        temperatureFallbackCount: 5,
                        usePrefillPrompt: true,
                        detectLanguage: false,
                        skipSpecialTokens: true,
                        compressionRatioThreshold: 2.4,
                        logProbThreshold: -1.2,
                        noSpeechThreshold: 0.45,
                        concurrentWorkerCount: 1
                    )
                    let results = try await pipe.transcribe(
                        audioPath: prepared.path,
                        decodeOptions: opts
                    )
                    let text = results
                        .map(\.text)
                        .joined(separator: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    completion(!text.isEmpty, text, text.isEmpty ? "empty" : nil)
                } catch {
                    let msg = String(error.localizedDescription.prefix(80))
                    MagicLog.event("whisper transcribe failed: \(msg)")
                    completion(false, "", "whisper_fail")
                }
            }
        }
    }

    private func currentKit() -> WhisperKit? {
        lock.lock(); defer { lock.unlock() }
        return kit
    }

    /// Download Core ML weights only (no ANE load). Safe after listen port is up.
    func prefetchWeights() {
        lock.lock()
        if _ready || _loading || _prefetching {
            lock.unlock()
            return
        }
        if Self.folder(for: "base") != nil {
            lock.unlock()
            MagicLog.event("whisper weights cached")
            return
        }
        _prefetching = true
        lock.unlock()
        MagicLog.event("whisper prefetch start")
        Task.detached(priority: .utility) { [weak self] in
            do {
                _ = try await WhisperKit.download(
                    variant: "base",
                    downloadBase: Self.cacheDirectory(),
                    endpoint: Self.hubEndpoint
                )
                MagicLog.event("whisper prefetch ok")
            } catch {
                MagicLog.event("whisper prefetch skip")
            }
            DispatchQueue.global(qos: .utility).async {
                self?.lock.lock()
                self?._prefetching = false
                self?.lock.unlock()
            }
        }
    }

    private func bundledOrCached() -> Bool { bundledOrCachedUnlocked() }

    private func bundledOrCachedUnlocked() -> Bool {
        Self.resolvedModelFolder() != nil
    }

    private static func makeKit() async throws -> WhisperKit {
        let local = resolvedModelFolder()
        let compute = ModelComputeOptions(
            melCompute: .cpuAndGPU,
            audioEncoderCompute: .cpuAndNeuralEngine,
            textDecoderCompute: .cpuAndNeuralEngine
        )
        let config = WhisperKitConfig(
            model: modelVariant,
            downloadBase: cacheDirectory(),
            modelEndpoint: hubEndpoint,
            modelFolder: local,
            tokenizerFolder: local.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? cacheDirectory(),
            computeOptions: compute,
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true,
            download: local == nil
        )
        return try await WhisperKit(config)
    }

    static func whisperLang(_ lang: String) -> String {
        let l = lang.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if l.hasPrefix("zh") || l == "cn" { return "zh" }
        if l.hasPrefix("ja") || l == "jp" { return "ja" }
        if l.hasPrefix("en") { return "en" }
        return "zh"
    }

    /// iPhone MediaRecorder is AAC-in-MP4 (often fMP4 / iso5). WhisperKit uses
    /// AVAudioFile. WAV/CAF pass through. MPEG-4 is remuxed via AVAssetReader
    /// to 16 kHz mono WAV. No AVAudioConverter (Swift 6 debug SIGTRAP).
    static func prepareAudioForWhisper(_ src: URL) throws -> URL {
        let ext = src.pathExtension.lowercased()
        if ext == "wav" || ext == "caf" { return src }
        if ["m4a", "mp4", "aac", "mov", "3gp"].contains(ext) || looksLikeFtyp(src) {
            if let wav = try? decodeWithAssetReader(src) { return wav }
        }
        return src
    }

    private static func looksLikeFtyp(_ url: URL) -> Bool {
        guard let fh = try? FileHandle(forReadingFrom: url),
              let data = try? fh.read(upToCount: 12),
              data.count >= 8 else { return false }
        try? fh.close()
        return data[4] == 0x66 && data[5] == 0x74 && data[6] == 0x79 && data[7] == 0x70
    }

    private static func decodeWithAssetReader(_ src: URL) throws -> URL {
        let asset = AVURLAsset(url: src)
        let sem = DispatchSemaphore(value: 0)
        asset.loadValuesAsynchronously(forKeys: ["tracks"]) { sem.signal() }
        _ = sem.wait(timeout: .now() + 4)
        var trackError: NSError?
        guard asset.statusOfValue(forKey: "tracks", error: &trackError) == .loaded else {
            throw trackError ?? NSError(domain: "magicpad.stt", code: 8)
        }
        guard let track = asset.tracks(withMediaType: .audio).first else {
            throw NSError(domain: "magicpad.stt", code: 9)
        }
        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 16_000,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = true
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? NSError(domain: "magicpad.stt", code: 10)
        }
        var pcm = Data()
        while reader.status == .reading {
            guard let sample = output.copyNextSampleBuffer() else { break }
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            var length = 0
            var dataPtr: UnsafeMutablePointer<Int8>?
            let status = CMBlockBufferGetDataPointer(
                block,
                atOffset: 0,
                lengthAtOffsetOut: nil,
                totalLengthOut: &length,
                dataPointerOut: &dataPtr
            )
            if status == kCMBlockBufferNoErr, let dataPtr, length > 0 {
                pcm.append(Data(bytes: dataPtr, count: length))
            }
        }
        guard reader.status == .completed || !pcm.isEmpty else {
            throw reader.error ?? NSError(domain: "magicpad.stt", code: 11)
        }
        return try writePcmWav16k(pcm)
    }

    private static func writePcmWav16k(_ pcm: Data) throws -> URL {
        guard pcm.count >= 320 else { throw NSError(domain: "magicpad.stt", code: 12) }
        var header = Data()
        func append4(_ s: String) { header.append(contentsOf: s.utf8) }
        func appendU32(_ v: UInt32) {
            var le = v.littleEndian
            header.append(Data(bytes: &le, count: 4))
        }
        func appendU16(_ v: UInt16) {
            var le = v.littleEndian
            header.append(Data(bytes: &le, count: 2))
        }
        append4("RIFF")
        appendU32(UInt32(36 + pcm.count))
        append4("WAVE")
        append4("fmt ")
        appendU32(16)
        appendU16(1)
        appendU16(1)
        appendU32(16_000)
        appendU32(32_000)
        appendU16(2)
        appendU16(16)
        append4("data")
        appendU32(UInt32(pcm.count))
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("magicpad-whisper-\(UUID().uuidString).wav")
        try (header + pcm).write(to: dest, options: .atomic)
        return dest
    }

    private func bumpIdleUnload() {
        lock.lock()
        unloadWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.unloadIfIdle()
        }
        unloadWork = work
        lock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 180, execute: work)
    }

    private func unloadIfIdle() {
        lock.lock()
        kit = nil
        _ready = false
        lock.unlock()
        MagicLog.event("whisper unloaded after idle (keep RAM)")
    }
}
