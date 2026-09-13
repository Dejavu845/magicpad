// Filenames.swift
// Path-component sanitize copied from FileDropPasteboard (no Date, no UTType).

import Foundation

public enum Filenames {
    public static let maxLength = 120
    public static let fallback = "magicpad-file.bin"

    public static func sanitize(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        name = (name as NSString).lastPathComponent
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._- ()[]"))
        name = String(name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        if name.count > maxLength { name = String(name.prefix(maxLength)) }
        if name.isEmpty || name == "." || name == ".." {
            return fallback
        }
        return name
    }
}
