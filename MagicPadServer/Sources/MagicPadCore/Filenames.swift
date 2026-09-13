// Filenames.swift
// Path-component sanitize. Unicode letters/digits stay (文件.txt).
// Backslash is a separator. Truncate the base and keep the suffix.

import Foundation

public enum Filenames {
    public static let maxLength = 120
    public static let fallback = "magicpad-file.bin"

    public static func sanitize(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        name = name.replacingOccurrences(of: "\\", with: "/")
        while name.hasSuffix("/") { name.removeLast() }
        name = (name as NSString).lastPathComponent
        // APFS often hands NFD. Compose first so `e` + U+0301 matches `é`.
        name = name.precomposedStringWithCanonicalMapping
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._- ()[]"))
        name = String(name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        if name.count > maxLength {
            let ns = name as NSString
            let ext = ns.pathExtension
            if !ext.isEmpty {
                let suffix = "." + ext
                let keep = max(1, maxLength - suffix.count)
                let base = ns.deletingPathExtension
                name = String(base.prefix(keep)) + suffix
                if name.count > maxLength { name = String(name.prefix(maxLength)) }
            } else {
                name = String(name.prefix(maxLength))
            }
        }
        if name.isEmpty || name == "." || name == ".." || name == "..." {
            return fallback
        }
        return name
    }
}
