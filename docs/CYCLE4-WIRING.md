# Cycle 4 — wire ProtocolLimits, HTML escape, CORS echo

`WebSocketServer.swift` stays unrestored on GitHub (62 KB; MCP truncates it).
Helpers below are in `MagicPadCore`. Insert after a human `git push` of the
local 1466-line file. Do **not** claim HTTP Origin is closed until
`docs/CYCLE3-HTTP-ORIGIN.md` is also wired.

## 1. Frame / header caps (`ProtocolLimits`) — MP-02

`parseFrame` already holds a **non-recursive** `NSLock` for its whole body
(`lock.lock()` + `defer { lock.unlock() }`). `closeInternal()` takes that
same lock. **Do not call `closeInternal()` or `sendCloseFrame` from inside
`parseFrame`.** One 2 MiB length announcement would deadlock the connection
thread (Opus C4 B2).

Existing `sendCloseFrame()` takes **no arguments** and writes a status-free
close (`0x88` + zero payload). `1009` / `1003` have no delivery path until
you add the overload below (Opus C4 B3).

Add this overload on the connection type (lock **not** held, or already
documented as held by a `…Locked` variant):

```swift
func sendCloseFrame(code: UInt16) {
    var frame = Data()
    frame.append(0x88) // FIN + close
    frame.append(0x02) // two-byte payload
    frame.append(UInt8(code >> 8))
    frame.append(UInt8(code & 0xFF))
    // write frame to the socket
}
```

In `parseFrame`, after computing `len`, **set a flag and return `nil`**:

```swift
// lock is held — do not close here
if len > ProtocolLimits.maxFrameBytes {
    pendingCloseCode = ProtocolLimits.closeMessageTooBig
    return nil
}
if !ProtocolLimits.allowedOpcodes.contains(opcode) {
    pendingCloseCode = ProtocolLimits.closeUnsupportedData
    return nil
}
```

After `parseFrame` returns and the lock is released, the caller:

```swift
if let code = pendingCloseCode {
    sendCloseFrame(code: code)
    closeInternal()
}
```

Alternatively, add `closeInternalLocked()` that documents the lock as
already held, and still send the close **before** taking the lock again.

### Fragmentation (opcode `0x0`)

`ProtocolLimits.allowedOpcodes` **includes `0x0`** so a later insert does
not 1003-disconnect a browser that fragments a `voice` or file-drop
payload. **Reassembly is not in this insert.** Today's dispatch still
delivers the first fragment and drops continuations. Do not treat `0x0`
as `closeUnsupportedData`. Implementing reassembly is a separate change.

## 2. `fallbackHTML` escape + CSP (Opus H1) + home-path (Opus C4 H2)

```swift
let safe = HTMLEscape.escape(error)
// interpolate `safe` only — never raw `error` / `cleanPath`
// headers: Content-Security-Policy: \(HTMLEscape.errorPageCSP)
//          X-Content-Type-Options: \(HTMLEscape.nosniff)
```

`HTMLEscape.errorPageCSP` is `default-src 'none'; style-src 'unsafe-inline'`
so the error page's existing inline `style=` attributes still apply.

**Home path (product rule, not an HTML-escape problem).** The 503 that
lists `index.html` candidates must **not** interpolate
`StaticFileLocator.indexHTMLCandidates()`. Those are absolute paths
(`Bundle.main`, cwd, `#filePath` build directory — including
`/Users/<name>`). Use `sourceLabel()` (comment: `不写家目录`), which the
success log already uses one line earlier:

```swift
let tried = StaticFileLocator.indexHTMLCandidates()
    .map(StaticFileLocator.sourceLabel)
    .joined(separator: " · ")
body = Self.fallbackHTML(error: "index.html missing — tried: \(HTMLEscape.escape(tried))")
```

Escaping a home path still ships the home path. Label, do not list.

## 3. CORS echo (`CORSPolicy`) — not the write control

```swift
if let acao = CORSPolicy.accessControl(origin: origin, lanIPs: lanIPs) {
    // Access-Control-Allow-Origin: \(acao.allowOrigin)
    if acao.needsVary {
        // Vary: Origin
    }
}
```

`needsVary` is false only for `*`. A CORS-simple `no-cors` POST still
writes without a readable reply. `HTTPPostOrigin.allows` in
`beginHTTPPost` is the write control (`docs/CYCLE3-HTTP-ORIGIN.md`).

## 4. `/health` via `JSONText.encode`

Build a `[String: Any]` with every existing `smoke-all.sh` key, then
`JSONText.encode`. Keep `proto: ProtocolLimits.proto` additive.

## Smoke (owner Mac, after wire)

```bash
python3 scripts/smoke-ws.py --origin http://evil.example --expect-reject
# announce 2 MiB frame → close 1009, /health still answers, server not hung
# POST /drop + Origin: http://evil.example → 403, dropCount unchanged
# 503 with missing index.html → body has bundle/source/env/other, no /Users/
```
