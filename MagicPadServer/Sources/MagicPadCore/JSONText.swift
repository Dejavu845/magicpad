// JSONText.swift
// Sorted-key JSON for /health and acks. Cycle 10 wired local healthJSON /
// hello_ack (docs/CYCLE4-WIRING.md). Remote stub unrestored.
// `.withoutEscapingSlashes` matches Python json.dumps (no \/ ).

import Foundation

public enum JSONText {
    public static func encode(_ obj: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(obj) else { return nil }
        guard let data = try? JSONSerialization.data(
            withJSONObject: obj,
            options: [.sortedKeys, .withoutEscapingSlashes]
        ) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
