// ProtocolLimits.swift
// Shared WS / JSON / HTTP size caps. Wire in WebSocketServer after the
// 62 KB file is restored (docs/CYCLE4-WIRING.md). Do not invent new limits.

import Foundation

public enum ProtocolLimits {
    public static let maxFrameBytes = 1_048_576
    public static let maxHeaderBytes = 16_384
    public static let maxTypeChars = 2_000
    public static let maxVoiceChars = 20_000
    public static let proto = 1
    public static let requiredWebSocketVersion = "13"
    public static let allowedOpcodes: Set<UInt8> = [0x1, 0x2, 0x8, 0x9, 0xA]
    public static let closeMessageTooBig: UInt16 = 1009
    public static let closeUnsupportedData: UInt16 = 1003
}
