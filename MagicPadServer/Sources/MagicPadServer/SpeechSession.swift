// SpeechSession.swift
// Mac-side STT (SFSpeechRecognizer + AVAudioEngine).
// Pass-through only: text → phone client; no LLM.
//
// Crash fix (2026-08-09): SpeechSession must NOT be fully @MainActor.
// SFSpeechRecognizer.requestAuthorization / AVAudioApplication mic callbacks
// run on TCC/background queues; a MainActor-isolated closure there traps with
// EXC_BREAKPOINT (_dispatch_assert_queue_fail / swift_task_checkIsolatedSwift).

import Foundation
import Speech
import AVFoundation
import AppKit

final class SpeechSession: @unchecked Sendable {
    static let shared = SpeechSession()

    private let lock = NSLock()
    private var _isListening = false
    private var _lastPartial = ""
    private var _authSpeech = "unknown"
    private var _supportsOnDevice = false

    var isListening: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isListening
    }
    var lastPartial: String {
        lock.lock(); defer { lock.unlock() }
        return _lastPartial
    }
    var authSpeech: String {
        lock.lock(); defer { lock.unlock() }
        return _authSpeech
    }
    var supportsOnDevice: Bool {
        lock.lock(); defer { lock.unlock() }
        return _supportsOnDevice
    }

    /// Deliver recognition text to WebSocket clients (JSON strings). Called off-main OK.
    var onEvent: ((String) -> Void)?

    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var currentLang: String = "zh-CN"
    private var preferOnDevice: Bool = true
    private var startedAt: Date?
    private let maxSeconds: TimeInterval = 55
    /// Serial queue for engine start/stop + recognition lifecycle (not TCC callbacks).
    private let sessionQueue = DispatchQueue(label: "app.magicpad.stt.session")
    /// "whisper" (ANE) or "apple". Live capture writes WAV then WhisperKit.
    private var engineName: String = "whisper"
    private var liveWavURL: URL?
    private var liveAudioFile: AVAudioFile?

    private init() {
        refreshAuthStatus()
    }

    func refreshAuthStatus() {
        let status = SFSpeechRecognizer.authorizationStatus()
        let auth: String
        switch status {
        case .authorized: auth = "authorized"
        case .denied: auth = "denied"
        case .restricted: auth = "restricted"
        case .notDetermined: auth = "notDetermined"
        @unknown default: auth = "unknown"
        }
        let onDev = SFSpeechRecognizer(locale: Locale(identifier: currentLang))?
            .supportsOnDeviceRecognition ?? false
        lock.lock()
        _authSpeech = auth
        _supportsOnDevice = onDev
        lock.unlock()
    }

    // MARK: - Start / Stop (live Mac mic)

    func start(lang: String?, preferOnDevice: Bool = true) {
        if isListening {
            push(["type": "stt_status", "state": "already", "lang": currentLang])
            return
        }
        currentLang = normalizeLang(lang)
        self.preferOnDevice = preferOnDevice

        requestMic { [weak self] micOk, micReason in
            guard let self else { return }
            if !micOk {
                self.push([
                    "type": "stt_final",
                    "ok": false,
                    "reason": micReason ?? "mic_denied",
                    "text": "",
                ])
                return
            }
            // H783: 先开麦，模型在后台加载。不要让下载挡住第一句话。
            self.sessionQueue.async {
                self.beginWhisperCapture()
            }
            LocalWhisper.shared.ensureReady { ready, _ in
                if !ready {
                    MagicLog.event("whisper load failed while recording — Apple fallback on stop")
                }
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.isListening else {
                self.push(["type": "stt_status", "state": "idle"])
                return
            }
            self.finishCapture(cancelled: false)
        }
    }

    // MARK: - Auth (nonisolated callbacks — must not be MainActor-isolated)

    /// Speech + Mic for live capture. Completions always hop via sessionQueue / free thread.
    private func ensureAuthorized(completion: @escaping @Sendable (Bool, String?) -> Void) {
        refreshAuthStatus()
        let speechStatus = SFSpeechRecognizer.authorizationStatus()

        let afterSpeech: @Sendable () -> Void = { [weak self] in
            self?.requestMic { micOk, micReason in
                if !micOk {
                    completion(false, micReason ?? "mic_denied")
                    return
                }
                completion(true, nil)
            }
        }

        switch speechStatus {
        case .authorized:
            afterSpeech()
        case .denied, .restricted:
            completion(false, "speech_\(authSpeech)")
        case .notDetermined:
            // Callback is on TCC queue — keep this closure nonisolated (class is not @MainActor).
            SFSpeechRecognizer.requestAuthorization { status in
                SpeechSession.shared.refreshAuthStatus()
                if status == .authorized {
                    afterSpeech()
                } else {
                    completion(false, "speech_denied")
                }
            }
        @unknown default:
            completion(false, "speech_unknown")
        }
    }

    private func requestMic(completion: @escaping @Sendable (Bool, String?) -> Void) {
        if #available(macOS 14.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                completion(granted, granted ? nil : "mic_denied")
            }
        } else {
            completion(true, nil)
        }
    }

    /// Speech-only auth for POST /stt file uploads (no Mac mic).
    func ensureSpeechAuthorized(completion: @escaping @Sendable (Bool, String?) -> Void) {
        refreshAuthStatus()
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            completion(true, nil)
        case .denied, .restricted:
            completion(false, "speech_\(authSpeech)")
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { status in
                SpeechSession.shared.refreshAuthStatus()
                MagicLog.event("stt speech auth → \(status.rawValue)")
            }
            // Do not block HTTP waiting for sheet.
            completion(false, "speech_auth_required")
        @unknown default:
            completion(false, "speech_unknown")
        }
    }

    // MARK: - File STT

    func transcribeFile(
        data: Data,
        lang: String?,
        contentType: String?,
        preferOnDevice: Bool = true,
        completion: @escaping @Sendable (_ ok: Bool, _ text: String, _ reason: String?, _ onDevice: Bool) -> Void
    ) {
        guard !data.isEmpty else {
            completion(false, "", "empty_body", false)
            return
        }
        guard data.count <= 10_000_000 else {
            completion(false, "", "too_large", false)
            return
        }

        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.runWhisperFileThenApple(
                data: data,
                lang: lang,
                contentType: contentType,
                preferOnDevice: preferOnDevice,
                completion: completion
            )
        }
    }

    private func runFileRecognition(
        data: Data,
        lang: String?,
        contentType: String?,
        preferOnDevice: Bool,
        completion: @escaping @Sendable (_ ok: Bool, _ text: String, _ reason: String?, _ onDevice: Bool) -> Void
    ) {
        let localeId = normalizeLang(lang)
        let locale = Locale(identifier: localeId)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            completion(false, "", "recognizer_unavailable", false)
            return
        }
        lock.lock()
        _supportsOnDevice = recognizer.supportsOnDeviceRecognition
        lock.unlock()

        let ext = Self.fileExtension(for: contentType, data: data)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("magicpad-stt-\(UUID().uuidString).\(ext)")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            completion(false, "", "write_temp:\(error.localizedDescription)", false)
            return
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        let onDeviceFlag: Bool
        if preferOnDevice && recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
            onDeviceFlag = true
        } else {
            request.requiresOnDeviceRecognition = false
            onDeviceFlag = false
        }

        MagicLog.event("stt file \(data.count)B ext=\(ext) lang=\(localeId) onDevice=\(onDeviceFlag)")

        final class Gate: @unchecked Sendable {
            private let lock = NSLock()
            private var done = false
            let url: URL
            private let onDone: @Sendable (Bool, String, String?, Bool) -> Void
            init(url: URL, onDone: @escaping @Sendable (Bool, String, String?, Bool) -> Void) {
                self.url = url
                self.onDone = onDone
            }
            func finish(_ ok: Bool, _ text: String, _ reason: String?, _ od: Bool) {
                lock.lock()
                defer { lock.unlock() }
                guard !done else { return }
                done = true
                try? FileManager.default.removeItem(at: url)
                onDone(ok, text, reason, od)
            }
        }
        let gate = Gate(url: url, onDone: completion)

        let timeoutSec: TimeInterval = data.count < 8_000 ? 12 : 45
        sessionQueue.asyncAfter(deadline: .now() + timeoutSec) {
            gate.finish(false, "", "timeout", onDeviceFlag)
        }

        recognizer.recognitionTask(with: request) { result, error in
            if let result, result.isFinal {
                let text = result.bestTranscription.formattedString
                let nonempty = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                gate.finish(nonempty, text, nonempty ? nil : "empty", onDeviceFlag)
                return
            }
            if let error {
                let ns = error as NSError
                if ns.domain == "kAFAssistantErrorDomain" && (ns.code == 216 || ns.code == 1110) {
                    gate.finish(false, "", "no_speech", onDeviceFlag)
                    return
                }
                gate.finish(false, "", "err:\(error.localizedDescription)", onDeviceFlag)
            }
        }
    }

    private static func fileExtension(for contentType: String?, data: Data) -> String {
        // Magic first: iPhone MediaRecorder is AAC-in-MP4 (ftyp iso5/mp42),
        // and the Content-Type may be audio/mp4, video/mp4, or empty.
        if data.count >= 12 {
            if data.prefix(4).elementsEqual([0x52, 0x49, 0x46, 0x46]) { return "wav" }
            if data.prefix(4).elementsEqual([0x63, 0x61, 0x66, 0x66]) { return "caf" }
            if data[4] == 0x66 && data[5] == 0x74 && data[6] == 0x79 && data[7] == 0x70 {
                let brand = String(bytes: data[8..<min(12, data.count)], encoding: .ascii) ?? ""
                if brand.hasPrefix("M4A") { return "m4a" }
                return "mp4"
            }
        }
        let ct = (contentType ?? "").lowercased()
        if ct.contains("wav") || ct.contains("wave") { return "wav" }
        if ct.contains("caf") { return "caf" }
        if ct.contains("ogg") { return "ogg" }
        if ct.contains("webm") { return "webm" }
        if ct.contains("mpeg") || ct.contains("mp3") { return "mp3" }
        if ct.contains("m4a") || (ct.contains("aac") && !ct.contains("mp4")) { return "m4a" }
        if ct.contains("mp4") { return "mp4" }
        return "mp4"
    }

    private func runWhisperFileThenApple(
        data: Data,
        lang: String?,
        contentType: String?,
        preferOnDevice: Bool,
        completion: @escaping @Sendable (_ ok: Bool, _ text: String, _ reason: String?, _ onDevice: Bool) -> Void
    ) {
        let ext = Self.fileExtension(for: contentType, data: data)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("magicpad-stt-\(UUID().uuidString).\(ext)")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            completion(false, "", "write_temp", false)
            return
        }
        let localeId = normalizeLang(lang)
        LocalWhisper.shared.transcribe(fileURL: url, lang: localeId) { [weak self] ok, text, reason in
            try? FileManager.default.removeItem(at: url)
            if ok {
                completion(true, text, reason, true)
                return
            }
            MagicLog.event("whisper file miss (\(reason ?? "?")) → Apple Speech")
            guard let self else {
                completion(false, "", reason ?? "whisper_fail", false)
                return
            }
            self.ensureSpeechAuthorized { authOk, authReason in
                if !authOk {
                    completion(false, "", reason ?? authReason ?? "whisper_fail", false)
                    return
                }
                self.sessionQueue.async {
                    self.runFileRecognition(
                        data: data,
                        lang: lang,
                        contentType: contentType,
                        preferOnDevice: preferOnDevice,
                        completion: completion
                    )
                }
            }
        }
    }

    // MARK: - Live Whisper (record WAV → ANE)

    private func beginWhisperCapture() {
        stopEngineOnly()
        closeLiveWav()
        engineName = "whisper"

        let engine = AVAudioEngine()
        let input = engine.inputNode
        var format = input.inputFormat(forBus: 0)
        if format.sampleRate <= 0 || format.channelCount <= 0 {
            engine.prepare()
            format = input.inputFormat(forBus: 0)
        }
        guard format.sampleRate > 0, format.channelCount > 0 else {
            push([
                "type": "stt_final",
                "ok": false,
                "reason": "no_input_device",
                "text": "",
                "engine": "whisper",
            ])
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("magicpad-whisper-\(UUID().uuidString).wav")
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            liveWavURL = url
            liveAudioFile = file
        } catch {
            push([
                "type": "stt_final",
                "ok": false,
                "reason": "whisper_write",
                "text": "",
                "engine": "whisper",
            ])
            return
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let file = self?.liveAudioFile else { return }
            try? file.write(from: buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            closeLiveWav()
            push([
                "type": "stt_final",
                "ok": false,
                "reason": "engine:\(error.localizedDescription)",
                "text": "",
                "engine": "whisper",
            ])
            return
        }

        audioEngine = engine
        lock.lock()
        _isListening = true
        _lastPartial = ""
        lock.unlock()
        startedAt = Date()
        push([
            "type": "stt_status",
            "state": "listening",
            "lang": currentLang,
            "onDevice": true,
            "engine": "whisper",
            "modelPending": !LocalWhisper.shared.isReady,
            "maxSeconds": Int(maxSeconds),
        ])
        MagicLog.event("stt whisper start lang=\(currentLang) sr=\(format.sampleRate)")

        sessionQueue.asyncAfter(deadline: .now() + maxSeconds) { [weak self] in
            guard let self, self.isListening, self.engineName == "whisper" else { return }
            MagicLog.event("stt whisper auto-stop at \(self.maxSeconds)s")
            self.finishWhisperCapture()
        }
    }

    private func finishWhisperCapture() {
        guard isListening, engineName == "whisper" else { return }
        stopEngineOnly()
        let url = liveWavURL
        closeLiveWav()
        lock.lock()
        _isListening = false
        lock.unlock()
        guard let url else {
            emitFinal(text: "", ok: false, reason: "empty", engine: "whisper", onDevice: true)
            return
        }
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        if bytes < 4000 {
            try? FileManager.default.removeItem(at: url)
            emitFinal(text: "", ok: false, reason: "empty", engine: "whisper", onDevice: true)
            return
        }
        push([
            "type": "stt_status",
            "state": "transcribing",
            "engine": "whisper",
            "lang": currentLang,
        ])
        LocalWhisper.shared.transcribe(fileURL: url, lang: currentLang) { [weak self] ok, text, reason in
            guard let session = self else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            if ok {
                try? FileManager.default.removeItem(at: url)
                session.sessionQueue.async {
                    session.emitFinal(text: text, ok: true, reason: reason, engine: "whisper", onDevice: true)
                }
                return
            }
            MagicLog.event("whisper miss (\(reason ?? "?")) → Apple on live wav")
            session.fallbackAppleFile(url: url, lang: session.currentLang) { aOk, aText, aReason in
                try? FileManager.default.removeItem(at: url)
                session.sessionQueue.async {
                    session.emitFinal(
                        text: aText,
                        ok: aOk,
                        reason: aReason ?? reason,
                        engine: aOk ? "apple" : "whisper",
                        onDevice: aOk
                    )
                }
            }
        }
    }

    private func closeLiveWav() {
        liveAudioFile = nil
        liveWavURL = nil
    }

    private func fallbackAppleFile(
        url: URL,
        lang: String,
        completion: @escaping @Sendable (Bool, String, String?) -> Void
    ) {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            completion(false, "", "whisper_fail")
            return
        }
        ensureSpeechAuthorized { [weak self] authOk, authReason in
            guard let self, authOk else {
                completion(false, "", authReason ?? "whisper_fail")
                return
            }
            self.sessionQueue.async {
                self.runFileRecognition(
                    data: data,
                    lang: lang,
                    contentType: "audio/wav",
                    preferOnDevice: true,
                    completion: { ok, text, reason, _ in
                        completion(ok, text, reason)
                    }
                )
            }
        }
    }

    // MARK: - Live capture

    private func beginCapture() {
        stopEngineOnly()
        task?.cancel()
        task = nil
        request = nil

        let locale = Locale(identifier: currentLang)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            push([
                "type": "stt_final",
                "ok": false,
                "reason": "recognizer_unavailable",
                "text": "",
                "lang": currentLang,
            ])
            return
        }
        self.recognizer = recognizer
        engineName = "apple"
        lock.lock()
        _supportsOnDevice = recognizer.supportsOnDeviceRecognition
        lock.unlock()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Prefer on-device only when supported; forcing unsupported crashes some builds.
        if preferOnDevice && recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        } else {
            request.requiresOnDeviceRecognition = false
        }
        self.request = request

        let engine = AVAudioEngine()
        let input = engine.inputNode
        // Use hardware input format (installTap with mismatched format → crash/bad audio).
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            // Fallback: some drivers report input after prepare
            engine.prepare()
            let fmt2 = input.inputFormat(forBus: 0)
            guard fmt2.sampleRate > 0, fmt2.channelCount > 0 else {
                push([
                    "type": "stt_final",
                    "ok": false,
                    "reason": "no_input_device",
                    "text": "",
                ])
                return
            }
            return beginCaptureWith(engine: engine, input: input, format: fmt2, request: request, recognizer: recognizer)
        }
        beginCaptureWith(engine: engine, input: input, format: format, request: request, recognizer: recognizer)
    }

    private func beginCaptureWith(
        engine: AVAudioEngine,
        input: AVAudioInputNode,
        format: AVAudioFormat,
        request: SFSpeechAudioBufferRecognitionRequest,
        recognizer: SFSpeechRecognizer
    ) {
        // Safe remove (ignore if no tap).
        input.removeTap(onBus: 0)

        let req = request
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            // Only append while request still active.
            req.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            MagicLog.event("stt engine start failed: \(error.localizedDescription)")
            input.removeTap(onBus: 0)
            push([
                "type": "stt_final",
                "ok": false,
                "reason": "engine:\(error.localizedDescription)",
                "text": "",
            ])
            return
        }

        self.audioEngine = engine
        lock.lock()
        _isListening = true
        _lastPartial = ""
        lock.unlock()
        self.startedAt = Date()

        let onDevice = request.requiresOnDeviceRecognition
        push([
            "type": "stt_status",
            "state": "listening",
            "lang": currentLang,
            "onDevice": onDevice,
            "maxSeconds": Int(maxSeconds),
        ])
        MagicLog.event("stt start lang=\(currentLang) onDevice=\(onDevice) sr=\(format.sampleRate)")

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            self.sessionQueue.async {
                if let result {
                    let text = result.bestTranscription.formattedString
                    self.lock.lock()
                    self._lastPartial = text
                    let listening = self._isListening
                    self.lock.unlock()
                    guard listening else { return }
                    if result.isFinal {
                        self.emitFinal(text: text, ok: true, reason: nil, engine: "apple")
                    } else if !text.isEmpty {
                        self.push([
                            "type": "stt_partial",
                            "text": text,
                            "lang": self.currentLang,
                        ])
                    }
                }
                if let error {
                    let ns = error as NSError
                    // 216 = cancelled
                    if ns.domain == "kAFAssistantErrorDomain" && ns.code == 216 {
                        return
                    }
                    self.lock.lock()
                    let listening = self._isListening
                    let partial = self._lastPartial
                    self.lock.unlock()
                    guard listening else { return }
                    if !partial.isEmpty {
                        self.emitFinal(text: partial, ok: true, reason: "partial_on_error", engine: "apple")
                    } else {
                        self.emitFinal(
                            text: "",
                            ok: false,
                            reason: "err:\(error.localizedDescription)",
                            engine: "apple"
                        )
                    }
                }
            }
        }

        sessionQueue.asyncAfter(deadline: .now() + maxSeconds) { [weak self] in
            guard let self, self.isListening else { return }
            MagicLog.event("stt auto-stop at \(self.maxSeconds)s")
            self.finishCapture(cancelled: false)
        }
    }

    private func finishCapture(cancelled: Bool) {
        guard isListening else { return }
        if engineName == "whisper" {
            if cancelled {
                stopEngineOnly()
                if let url = liveWavURL { try? FileManager.default.removeItem(at: url) }
                closeLiveWav()
                emitFinal(text: lastPartial, ok: false, reason: "cancelled", engine: "whisper", onDevice: true)
                return
            }
            finishWhisperCapture()
            return
        }
        request?.endAudio()
        stopEngineOnly()
        if cancelled {
            emitFinal(text: lastPartial, ok: false, reason: "cancelled", engine: "apple")
            MagicLog.event("stt cancelled")
            return
        }
        let snapshot = lastPartial
        sessionQueue.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.isListening else { return }
            let text = self.lastPartial.isEmpty ? snapshot : self.lastPartial
            let nonempty = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            self.emitFinal(text: text, ok: nonempty, reason: nonempty ? "forced" : "empty", engine: "apple")
        }
        MagicLog.event("stt stop requested")
    }

    private func emitFinal(
        text: String,
        ok: Bool,
        reason: String?,
        engine: String? = nil,
        onDevice: Bool? = nil
    ) {
        let wasListening = isListening
        task?.cancel()
        task = nil
        request = nil
        stopEngineOnly()
        lock.lock()
        _isListening = false
        lock.unlock()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let success = ok && !trimmed.isEmpty
        let eng = engine ?? engineName
        var payload: [String: Any] = [
            "type": "stt_final",
            "ok": success,
            "text": text,
            "lang": currentLang,
            "onDevice": onDevice ?? (eng == "whisper" || (preferOnDevice && supportsOnDevice)),
            "engine": eng,
        ]
        if !wasListening && eng != "whisper" { return }
        if let reason { payload["reason"] = reason }
        if let startedAt {
            payload["ms"] = Int(Date().timeIntervalSince(startedAt) * 1000)
        }
        push(payload)
        lock.lock()
        _lastPartial = ""
        lock.unlock()
        MagicLog.event("stt final ok=\(success) len=\(text.count)")
    }

    private func stopEngineOnly() {
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            if engine.isRunning {
                engine.stop()
            }
        }
        audioEngine = nil
    }

    private func normalizeLang(_ lang: String?) -> String {
        let l = (lang ?? "zh-CN").trimmingCharacters(in: .whitespacesAndNewlines)
        switch l {
        case "zh", "zh-Hans", "cn", "zh_CN": return "zh-CN"
        case "en", "en_US": return "en-US"
        case "ja", "jp", "ja_JP": return "ja-JP"
        default:
            if l.hasPrefix("zh") { return "zh-CN" }
            if l.hasPrefix("en") { return "en-US" }
            if l.hasPrefix("ja") { return "ja-JP" }
            return l.isEmpty ? "zh-CN" : l
        }
    }

    private func push(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let s = String(data: data, encoding: .utf8) else { return }
        // Deliver on main so UI/WS observers stay consistent without isolation traps.
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(s)
        }
    }
}
