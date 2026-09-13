// JSONText.swift
// Sorted-key JSON for /health and acks. Replaces string-interpolated JSON
// once WebSocketServer.swift is restored (docs/CYCLE4-WIRING.md).

import Foundation

public enum JSONText {
    public static func encode(_ obj: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(obj) else { return nil }
        guard let data = try? JSONSerialization.data(
            withJSONObject: obj,
            options: [.sortedKeys]
        ) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
