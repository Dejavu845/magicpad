// BinaryFrame.swift
// Cycle 26: pointer / gesture payload lives in Core (MP-18).
// Mirrors scripts/magicpad_proto.py parse_binary_frame.
// No inject. <7 bytes → nil (EventInjector must no-op).

import Foundation

public struct BinaryFrame: Equatable, Sendable {
    public static let minBytes = 7
    public static let pointerBytes = 13
    public static let gestureBytes = 18

    /// Same table as Python PHASES. Unknown phase → "unknown" (no inject invent).
    public static let knownPhases: [UInt8: String] = [
        0: "down",
        1: "move",
        2: "up",
        3: "cancel",
        10: "dbl",
        11: "right",
        20: "scroll",
        21: "pinch",
        22: "triple",
        23: "smartzoom",
        24: "mission",
    ]

    public let phase: UInt8
    public let dx: Int16
    public let dy: Int16
    public let pressure: UInt8
    public let buttons: UInt8
    public let tMs: UInt32
    public let seq: UInt16
    public let fingers: UInt8
    public let gesture: UInt8
    public let ext: Int16
    public let byteCount: Int

    public var kind: String { Self.knownPhases[phase] ?? "unknown" }
    public var isGesture: Bool { phase >= 10 }

    public init(
        phase: UInt8,
        dx: Int16,
        dy: Int16,
        pressure: UInt8,
        buttons: UInt8,
        tMs: UInt32,
        seq: UInt16,
        fingers: UInt8,
        gesture: UInt8,
        ext: Int16,
        byteCount: Int
    ) {
        self.phase = phase
        self.dx = dx
        self.dy = dy
        self.pressure = pressure
        self.buttons = buttons
        self.tMs = tMs
        self.seq = seq
        self.fingers = fingers
        self.gesture = gesture
        self.ext = ext
        self.byteCount = byteCount
    }

    /// Decode a WS binary payload. Nil when shorter than 7 bytes (no inject).
    public static func parse(_ data: Data) -> BinaryFrame? {
        guard data.count >= minBytes else { return nil }
        let phase = data[0]
        let dx = Int16(data[1]) | (Int16(data[2]) << 8)
        let dy = Int16(data[3]) | (Int16(data[4]) << 8)
        let pressure = data[5]
        let buttons = data[6]
        var tMs: UInt32 = 0
        var seq: UInt16 = 0
        if data.count >= pointerBytes {
            tMs = UInt32(data[7])
                | (UInt32(data[8]) << 8)
                | (UInt32(data[9]) << 16)
                | (UInt32(data[10]) << 24)
            seq = UInt16(data[11]) | (UInt16(data[12]) << 8)
        }
        var fingers: UInt8 = 1
        var gesture: UInt8 = 0
        var ext: Int16 = 0
        if data.count >= gestureBytes {
            fingers = data[13]
            gesture = data[14]
            ext = Int16(data[15]) | (Int16(data[16]) << 8)
        }
        return BinaryFrame(
            phase: phase,
            dx: dx,
            dy: dy,
            pressure: pressure,
            buttons: buttons,
            tMs: tMs,
            seq: seq,
            fingers: fingers,
            gesture: gesture,
            ext: ext,
            byteCount: data.count
        )
    }
}
