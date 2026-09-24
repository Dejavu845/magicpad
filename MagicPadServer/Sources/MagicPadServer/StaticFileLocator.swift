import Foundation
import zlib

enum StaticFileLocator {
    // 仅用于去重日志;Swift 6 全局可变状态需标 unsafe
    nonisolated(unsafe) private static var loggedResolved: String?

    static var projectRoot: String {
        let file = #filePath
        let url = URL(fileURLWithPath: file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return url.path
    }

    /// 是否在本机源码树里跑 `build/MagicPad.app`（开发机）。拷走的 .app 必须走 bundle。
    static func runningFromSourceTree() -> Bool {
        let source = projectRoot + "/MagicPadClient/index.html"
        guard FileManager.default.isReadableFile(atPath: source) else { return false }
        guard let exe = Bundle.main.executablePath else { return false }
        return exe.hasPrefix(projectRoot + "/build/")
            || exe.hasPrefix(projectRoot + "/MagicPadServer/")
    }

    /// 全部候选路径(去重、保序)
    /// 安装环境优先：env → 本 .app Resources → /Applications →（仅开发机）源码
    static func indexHTMLCandidates() -> [String] {
        var candidates: [String] = []
        if let custom = ProcessInfo.processInfo.environment["MAGICPAD_INDEX_HTML"], !custom.isEmpty {
            candidates.append(custom)
        }
        // 当前正在跑的这个 .app（朋友拷走 / 装到 Applications 都靠它）
        if let res = Bundle.main.resourceURL?.appendingPathComponent("index.html").path {
            candidates.append(res)
        }
        if let res = Bundle.main.path(forResource: "index", ofType: "html") {
            candidates.append(res)
        }
        if let exePath = Bundle.main.executablePath {
            let exe = URL(fileURLWithPath: exePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/index.html").path
            candidates.append(exe)
        }
        candidates.append("/Applications/MagicPad.app/Contents/Resources/index.html")
        // 开发机：源码可热读。编译进 binary 的 #filePath 在别人电脑上不存在，不会误中。
        if runningFromSourceTree() {
            candidates.append(projectRoot + "/MagicPadClient/index.html")
            let cwd = FileManager.default.currentDirectoryPath
            candidates.append(cwd + "/MagicPadClient/index.html")
            candidates.append(cwd + "/index.html")
        }

        var seen = Set<String>()
        return candidates.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// 日志/health 用：bundle | source | env | other。不写家目录。
    static func sourceLabel(_ path: String) -> String {
        if path.contains(".app/Contents/Resources/") { return "bundle" }
        if path.hasSuffix("/MagicPadClient/index.html") { return "source" }
        if ProcessInfo.processInfo.environment["MAGICPAD_INDEX_HTML"] == path { return "env" }
        return "other"
    }

    /// 第一个可读路径;找不到返回 nil(不要假装路径存在)
    static func resolvedIndexHTMLPath() -> String? {
        let candidates = indexHTMLCandidates()
        for p in candidates {
            if FileManager.default.isReadableFile(atPath: p) {
                if loggedResolved != p {
                    MagicLog.server("index.html → \(sourceLabel(p))")
                    loggedResolved = p
                }
                return p
            }
        }
        MagicLog.server("index.html NOT FOUND, tried \(candidates.count) candidates")
        return nil
    }

    /// 多候选: 环境变量 → 本 app Resources → /Applications →（仅开发机）源码树。
    /// 找不到时仍返回首选路径字符串(给日志用),但 loadIndexHTML 会返回 nil。缓存不改变这个顺序。
    static func indexHTMLPath() -> String {
        if let p = resolvedIndexHTMLPath() { return p }
        return indexHTMLCandidates().first ?? (projectRoot + "/MagicPadClient/index.html")
    }

    /// Page bytes + htmlRev, keyed by path + mtime + size.
    /// Candidate order is unchanged (env → this app's Resources → /Applications → source tree only when the binary lives in this repo).
    private struct IndexSnapshot {
        var path: String
        var mtime: TimeInterval
        var size: UInt64
        var bytes: Data
        var gzip: Data?
        var rev: String
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var indexSnapshot: IndexSnapshot?

    private static func fileStamp(_ path: String) -> (mtime: TimeInterval, size: UInt64)? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        if size == 0 { return nil }
        return (mtime, size)
    }

    /// Reloads only when the chosen file's path, mtime, or size changes. Does not search a different path.
    private static func snapshot(path: String) -> IndexSnapshot? {
        guard let stamp = fileStamp(path) else { return nil }
        cacheLock.lock()
        if let hit = indexSnapshot,
           hit.path == path,
           hit.mtime == stamp.mtime,
           hit.size == stamp.size,
           !hit.bytes.isEmpty {
            cacheLock.unlock()
            return hit
        }
        cacheLock.unlock()

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), !data.isEmpty else {
            MagicLog.server("index.html unreadable/empty (\(sourceLabel(path)))")
            return nil
        }
        guard let after = fileStamp(path), after.size == UInt64(data.count) else {
            return nil
        }
        let snap = IndexSnapshot(
            path: path,
            mtime: after.mtime,
            size: after.size,
            bytes: data,
            gzip: gzipData(data),
            rev: parseHTMLRev(data)
        )
        cacheLock.lock()
        indexSnapshot = snap
        cacheLock.unlock()
        return snap
    }

    /// 可读则返回 Data,否则 nil → 调用方应回退明确错误 HTML(非空白)
    static func loadIndexHTML() -> (Data, String)? {
        guard let path = resolvedIndexHTMLPath() else { return nil }
        guard let snap = snapshot(path: path) else { return nil }
        return (snap.bytes, path)
    }

    /// HTML body for the pad page. Gzip is the cached compression of the same bytes, not a second disk read.
    static func indexBody(gzip: Bool) -> (data: Data, path: String, gzipped: Bool)? {
        guard let path = resolvedIndexHTMLPath() else { return nil }
        guard let snap = snapshot(path: path) else { return nil }
        if gzip, let gz = snap.gzip, !gz.isEmpty, gz.count < snap.bytes.count {
            return (gz, path, true)
        }
        return (snap.bytes, path, false)
    }

    /// Token from `MAGICPAD_HTML_REV = '…'` so phone can detect a stale cached page.
    static func htmlRev() -> String {
        guard let path = resolvedIndexHTMLPath() else { return "" }
        return snapshot(path: path)?.rev ?? ""
    }

    private static func parseHTMLRev(_ data: Data) -> String {
        guard let s = String(data: data, encoding: .utf8) else { return "" }
        guard let marker = s.range(of: "MAGICPAD_HTML_REV") else { return "" }
        let rest = s[marker.upperBound...]
        guard let eq = rest.firstIndex(of: "=") else { return "" }
        var i = rest.index(after: eq)
        while i < rest.endIndex, rest[i] == " " || rest[i] == "'" || rest[i] == "\"" {
            i = rest.index(after: i)
        }
        var out = ""
        while i < rest.endIndex {
            let ch = rest[i]
            if ch == "'" || ch == "\"" || ch == ";" || ch == "\n" { break }
            out.append(ch)
            i = rest.index(after: i)
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// gzip wrapper (windowBits = 15+16). Nil if zlib refuses. Called only when the file stamp changes.
    private static func gzipData(_ source: Data) -> Data? {
        guard !source.isEmpty else { return nil }
        var stream = z_stream()
        let rc = deflateInit2_(
            &stream,
            Z_DEFAULT_COMPRESSION,
            Z_DEFLATED,
            MAX_WBITS + 16,
            8,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard rc == Z_OK else { return nil }
        defer { deflateEnd(&stream) }
        let bound = Int(deflateBound(&stream, uLong(source.count)))
        guard bound > 0 else { return nil }
        var dst = Data(count: bound)
        let inCount = source.count
        let outCount = dst.count
        let status: Int32 = source.withUnsafeBytes { srcBuf in
            dst.withUnsafeMutableBytes { dstBuf in
                stream.next_in = UnsafeMutablePointer(mutating: srcBuf.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(inCount)
                stream.next_out = dstBuf.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(outCount)
                return deflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END else { return nil }
        let produced = outCount - Int(stream.avail_out)
        guard produced > 0, produced <= dst.count else { return nil }
        dst.count = produced
        return dst
    }

    static func staticResourcePath(_ relative: String) -> String {
        return projectRoot + "/MagicPadClient/" + relative
    }
}
