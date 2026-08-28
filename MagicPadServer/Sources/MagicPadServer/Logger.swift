// Logger.swift
// 双通道日志:os.Logger(给 Console.app)+ 文件(给 CLI 调试)
//
// 命名注意: 不叫 Logger 是因为会和 os.Logger 撞名

import Foundation
import os

enum LogSubsystem: String {
    case app
    case menu
    case server
    case ws
    case bonjour
    case event
}

enum MagicLog {
    private static let subsystem = "app.magicpad.server"
    private static let logger = os.Logger(subsystem: subsystem, category: "core")

    // 写到 /tmp/magicpad-server.log(append 模式)
    // Swift Foundation 没有 forAppendingTo,要手动 seekToEnd
    private static let logFile: FileHandle? = {
        let path = "/tmp/magicpad-server.log"
        let fm = FileManager.default
        if !fm.fileExists(atPath: path) {
            fm.createFile(atPath: path, contents: nil)
        }
        // forWritingAtPath 打开 mode = write,默认 offset 0(会覆盖)
        // 立刻 seekToEndOfFile() 跳到文件尾,后续 write 就在文件尾追加
        guard let fh = FileHandle(forWritingAtPath: path) else { return nil }
        fh.seekToEndOfFile()
        return fh
    }()

    static func app(_ msg: String)    { write(.app, msg) }
    static func menu(_ msg: String)   { write(.menu, msg) }
    static func server(_ msg: String) { write(.server, msg) }
    static func ws(_ msg: String)     { write(.ws, msg) }
    static func bonjour(_ msg: String){ write(.bonjour, msg) }
    static func event(_ msg: String)  { write(.event, msg) }

    private static func write(_ sub: LogSubsystem, _ msg: String) {
        // 1. os.Logger
        logger.info("[\(sub.rawValue, privacy: .public)] \(msg, privacy: .public)")

        // 2. 文件
        let ts = isoTimestamp()
        let line = "\(ts) [\(sub.rawValue)] \(msg)\n"
        if let data = line.data(using: .utf8) {
            logFile?.write(data)
        }
    }

    private static func isoTimestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f.string(from: Date())
    }
}
