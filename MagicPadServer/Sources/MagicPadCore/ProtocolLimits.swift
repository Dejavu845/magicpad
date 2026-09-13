// ProtocolLimits.swift
// Shared WS / JSON / HTTP size caps. Cycle 7 wired maxFrameBytes /
// maxHeaderBytes / allowedOpcodes into local WebSocketServer.parseFrame
// (docs/CYCLE4-WIRING.md). Remote stub unrestored until a human git push.
// maxTypeChars / maxVoiceChars / proto / version 13 mirror existing code —
// do not invent a second pair of type/voice numbers; read KeyProtocol.

import Foundation

public enum ProtocolLimits {
    public static let maxFrameBytes = 1_048_576
    public static let maxHeaderBytes = 16_384
    public static let maxTypeChars = KeyProtocol.maxTypeChars
    public static let maxVoiceChars = KeyProtocol.maxVoiceChars
    public static let proto = 1
    public static let requiredWebSocketVersion = "13"
    /// 0x0 is listed so a later insert does not 1003-disconnect fragmented
    /// browsers. Reassembly is not implemented (docs/CYCLE4-WIRING.md).
    public static let allowedOpcodes: Set<UInt8> = [0x0, 0x1, 0x2, 0x8, 0x9, 0xA]
    public static let closeMessageTooBig: UInt16 = 1009
    public static let closeUnsupportedData: UInt16 = 1003
}
