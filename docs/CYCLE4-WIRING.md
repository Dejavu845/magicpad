# Cycle 4 — wire ProtocolLimits, HTML escape, CORS echo

`WebSocketServer.swift` stays unrestored on GitHub (62 KB; MCP truncates it).
Helpers below are in `MagicPadCore`. Insert after a human `git push` of the
local 1466-line file. Do **not** claim HTTP Origin is closed until
`docs/CYCLE3-HTTP-ORIGIN.md` is also wired.

## 1. Frame / header caps (`ProtocolLimits`) — MP-02

In `parseFrame`, after computing `len`:

```swift
guard len <= ProtocolLimits.maxFrameBytes else {
    sendCloseFrame(code: ProtocolLimits.closeMessageTooBig)
    closeInternal()
    return nil
}
guard ProtocolLimits.allowedOpcodes.contains(opcode) else {
    sendCloseFrame(code: ProtocolLimits.closeUnsupportedData)
    closeInternal()
    return nil
}
```

In `handleData` pre-handshake: if `buffer.count > ProtocolLimits.maxHeaderBytes`
and the `\r\n\r\n` separator is missing → `431 Request Header Fields Too Large`
and close.

In `handleHandshake`: require `Sec-WebSocket-Version: 13`
(`ProtocolLimits.requiredWebSocketVersion`) else `426 Upgrade Required`
with `Sec-WebSocket-Version: 13`.

## 2. `fallbackHTML` escape + CSP (Opus H1)

```swift
let safe = HTMLEscape.escape(error)
// interpolate `safe` only — never raw `error` / `cleanPath`
// headers: Content-Security-Policy: default-src 'none'
//          X-Content-Type-Options: nosniff
```

Do not list `indexHTMLCandidates()` paths in the HTML body.

## 3. CORS echo (`CORSPolicy`) — not the write control

```swift
if let acao = CORSPolicy.accessControlAllowOrigin(origin: origin, lanIPs: lanIPs) {
    // Access-Control-Allow-Origin: \(acao)
    // if acao != "*" { Vary: Origin }
}
```

A CORS-simple `no-cors` POST still writes without a readable reply.
`HTTPPostOrigin.allows` in `beginHTTPPost` is the write control
(`docs/CYCLE3-HTTP-ORIGIN.md`).

## 4. `/health` via `JSONText.encode`

Build a `[String: Any]` with every existing `smoke-all.sh` key, then
`JSONText.encode`. Keep `proto: ProtocolLimits.proto` additive.

## Smoke (owner Mac, after wire)

```bash
python3 scripts/smoke-ws.py --origin http://evil.example --expect-reject
# announce 2 MiB frame → close, /health still answers
# POST /drop + Origin: http://evil.example → 403, dropCount unchanged
```
