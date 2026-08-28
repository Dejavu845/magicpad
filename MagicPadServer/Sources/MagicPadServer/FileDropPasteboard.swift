// FileDropPasteboard.swift
// Phone uploads audio/photo/file → save on Mac → NSPasteboard → optional Cmd+V into focus.
// Not LLM. Works only when the focused app accepts paste of files/images.

import AppKit
import Foundation
import UniformTypeIdentifiers

/// Last drop/upload outcome for /health (H1-5)
enum DropTelemetry {
    nonisolated(unsafe) static var lastOk = false
    nonisolated(unsafe) static var lastReason = ""
    nonisolated(unsafe) static var lastKind = ""
    nonisolated(unsafe) static var lastAt: Double = 0
    nonisolated(unsafe) static var count = 0

    static func note(ok: Bool, reason: String?, kind: String) {
        lastOk = ok
        lastReason = reason ?? (ok ? "ok" : "fail")
        lastKind = kind
        lastAt = Date().timeIntervalSince1970
        count += 1
    }
}

enum FileDropPasteboard {
    private static let maxBytes = 50_000_000 // 50MB

    struct Result {
        let ok: Bool
        let reason: String?
        let path: String
        let name: String
        let bytes: Int
        let kind: String
        let pasted: Bool
    }

    static func ingest(
        data: Data,
        filename: String?,
        contentType: String?,
        autoPaste: Bool
    ) -> Result {
        guard !data.isEmpty else {
            DropTelemetry.note(ok: false, reason: "empty_body", kind: "unknown")
            return Result(ok: false, reason: "empty_body", path: "", name: "", bytes: 0, kind: "unknown", pasted: false)
        }
        guard data.count <= maxBytes else {
            return Result(ok: false, reason: "too_large", path: "", name: "", bytes: data.count, kind: "unknown", pasted: false)
        }

        let name = sanitizeFilename(filename, contentType: contentType, data: data)
        let kind = classify(name: name, contentType: contentType)
        let dir = dropDirectory()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            DropTelemetry.note(ok: false, reason: "mkdir", kind: kind)
            return Result(ok: false, reason: "mkdir:\(error.localizedDescription)", path: "", name: name, bytes: data.count, kind: kind, pasted: false)
        }

        // Unique name to avoid overwrite collisions
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        let unique = base + "-" + String(Int(Date().timeIntervalSince1970)) +
            (ext.isEmpty ? "" : ".\(ext)")
        let url = dir.appendingPathComponent(unique)

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            DropTelemetry.note(ok: false, reason: "write", kind: kind)
            return Result(ok: false, reason: "write:\(error.localizedDescription)", path: "", name: unique, bytes: data.count, kind: kind, pasted: false)
        }

        // Pasteboard on main (AppKit); Cmd+V on InjectRuntime (H12)
        var pasted = false
        var axOk = false
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                (pasted, axOk) = writePasteboard(url: url, kind: kind, autoPaste: autoPaste)
            }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    (pasted, axOk) = writePasteboard(url: url, kind: kind, autoPaste: autoPaste)
                }
            }
        }
        MagicLog.event("drop \(unique) \(data.count)B kind=\(kind) pasted=\(pasted)")
        InjectTelemetry.note("drop \(kind)")
        // telemetry filled after reason resolved below

        let reason: String?
        if pasted {
            reason = nil
        } else if !axOk {
            reason = "ax_denied_clipboard_ok"
        } else {
            reason = "clipboard_only"
        }

        DropTelemetry.note(ok: true, reason: reason, kind: kind)
        return Result(
            ok: true,
            reason: reason,
            path: url.path,
            name: unique,
            bytes: data.count,
            kind: kind,
            pasted: pasted
        )
    }

    private static func dropDirectory() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return caches.appendingPathComponent("MagicPadDrop", isDirectory: true)
    }

    private static func sanitizeFilename(_ raw: String?, contentType: String?, data: Data) -> String {
        var name = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            let ext = preferredExt(contentType: contentType, data: data)
            name = "magicpad-\(Int(Date().timeIntervalSince1970)).\(ext)"
        }
        // Strip path components and unsafe chars
        name = (name as NSString).lastPathComponent
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._- ()[]"))
        name = String(name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        if name.count > 120 { name = String(name.prefix(120)) }
        if name.isEmpty || name == "." || name == ".." {
            name = "magicpad-file.bin"
        }
        return forceMp4IfAacContainer(name, contentType: contentType)
    }

    /// AAC-in-MP4 / .m4a → .mp4 so focused chat apps attach a file multimodal models ingest.
    private static func forceMp4IfAacContainer(_ name: String, contentType: String?) -> String {
        let ct = (contentType ?? "").lowercased()
        let ext = (name as NSString).pathExtension.lowercased()
        let keep = ["png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "bmp", "pdf", "zip", "txt", "doc", "docx"]
        if keep.contains(ext) { return name }
        let isFamily = ext == "m4a" || ext == "aac" || ext == "mp4"
            || ct.contains("mp4") || ct.contains("m4a") || ct.contains("aac")
        guard isFamily else { return name }
        let base = (name as NSString).deletingPathExtension
        return (base.isEmpty ? "web-recording" : base) + ".mp4"
    }

    private static func preferredExt(contentType: String?, data: Data) -> String {
        let ct = (contentType ?? "").lowercased()
        if ct.contains("png") { return "png" }
        if ct.contains("jpeg") || ct.contains("jpg") { return "jpg" }
        if ct.contains("heic") || ct.contains("heif") { return "heic" }
        if ct.contains("gif") { return "gif" }
        if ct.contains("webp") { return "webp" }
        if ct.contains("mp4") { return "mp4" }
        if ct.contains("m4a") || ct.contains("aac") { return "mp4" }
        if ct.contains("mpeg") || ct.contains("mp3") { return "mp3" }
        if ct.contains("wav") { return "wav" }
        if ct.contains("caf") { return "caf" }
        if ct.contains("quicktime") || ct.contains("mov") { return "mov" }
        if ct.contains("pdf") { return "pdf" }
        if data.count >= 8 {
            let b = [UInt8](data.prefix(8))
            if b[0] == 0x89 && b[1] == 0x50 { return "png" }
            if b[0] == 0xFF && b[1] == 0xD8 { return "jpg" }
            if b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70 { return "mp4" }
        }
        return "bin"
    }

    private static func classify(name: String, contentType: String?) -> String {
        let ct = (contentType ?? "").lowercased()
        let ext = (name as NSString).pathExtension.lowercased()
        if ct.hasPrefix("image/") || ["png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "bmp"].contains(ext) {
            return "image"
        }
        if ct.hasPrefix("video/") || ["mp4", "mov", "m4v"].contains(ext) {
            return "video"
        }
        if ct.contains("mp4") || ct.contains("m4a") || ct.contains("aac") {
            return "video"
        }
        if ct.hasPrefix("audio/") || ["m4a", "mp3", "wav", "caf", "aac", "ogg"].contains(ext) {
            return "audio"
        }
        return "file"
    }

    /// Write file (and image if applicable) to general pasteboard; optionally Cmd+V.
    /// Returns (pastedIntoFocus, axAllowed). Caller must be on MainActor.
    @MainActor
    private static func writePasteboard(url: URL, kind: String, autoPaste: Bool) -> (Bool, Bool) {
        let pb = NSPasteboard.general
        pb.clearContents()

        var writers: [NSPasteboardWriting] = [url as NSURL]
        if kind == "image", let img = NSImage(contentsOf: url) {
            writers.append(img)
        }
        let wrote = pb.writeObjects(writers)
        guard wrote else { return (false, EventInjector.hasAccessibilityPermission) }

        if kind == "video" || url.pathExtension.lowercased() == "mp4" {
            if let data = try? Data(contentsOf: url), !data.isEmpty, data.count <= maxBytes {
                pb.setData(data, forType: NSPasteboard.PasteboardType("public.mpeg-4"))
                pb.setData(data, forType: NSPasteboard.PasteboardType(UTType.mpeg4Movie.identifier))
            }
        }

        let ax = EventInjector.hasAccessibilityPermission
        if autoPaste && ax {
            // H12: Cmd+V on the same inject queue as pointer (never race leftButtonDown)
            InjectRuntime.sync {
                EventInjector.releaseStuckButtons(reason: "before-drop-paste")
                EventInjector.releaseAllModifiers()
                usleep(8_000)
                EventInjector.injectEditAction("paste", count: 1)
                usleep(4_000)
                EventInjector.releaseAllModifiers()
            }
            return (true, true)
        }
        // On clipboard even if not auto-pasted
        return (false, ax)
    }
}
