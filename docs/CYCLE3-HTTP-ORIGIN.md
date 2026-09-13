# Cycle 3 — Origin check on `POST /drop` and `POST /stt`

Cycle 7 wired `HTTPPostOrigin.allows` in local `beginHTTPPost`. GitHub still
has the 140-byte stub (MCP-upload truncates the 62 KB file). A human `git push`
is required before the remote server has this check.

## Why CORS echo is not the fix

`POST /drop` writes the pasteboard and, with `autoPaste` defaulting to true,
simulates Cmd+V. A CORS-simple `text/plain` `fetch(..., {mode:'no-cors'})` needs
no readable response. Changing `Access-Control-Allow-Origin` (old MP-04) only
affects who may *read* replies. The write succeeds regardless.

MP-01's `OriginPolicy.isAllowed` lives only in `handleHandshake` (Upgrade:
websocket). HTTP POST never reaches it.

## Exact `beginHTTPPost` insertion

In `WSConnection.beginHTTPPost(path:header:)` (`WebSocketServer.swift`), **after**
the `isStt || isDrop` guard and **before** `contentLength` / `dispatchPostBody` /
`pendingPost`:

```swift
// TODO(cycle3): Origin on HTTP POST — same carve-out as WS handshake.
let origin = HTTPHeaderValue.first(header, name: "origin")
let lanIPs = LANDetector.allPrivateIPs
if !HTTPPostOrigin.allows(origin, lanIPs: lanIPs) {
    let host = OriginPolicy.host(fromOrigin: origin) ?? "?"  // log-only
    MagicLog.ws("POST origin rejected host=\(host)")
    serveJSON(status: "HTTP/1.1 403 Forbidden", obj: [
        "ok": false, "reason": "origin_rejected",
    ])
    return
}
```

Helpers already in `MagicPadCore` (Cycle 2):

- `HTTPHeaderValue.first` — empty `Origin:` → `""`, not the literal `"Origin"`.
- `HTTPPostOrigin.allows` — delegates to `OriginPolicy.isAllowed`.

Missing Origin (`first` returns `nil`) → allow (curl / `smoke-all.sh` POST /drop).
Present-but-empty → allow (`""`). Cycle 8 deleted `WebSocketServer.headerValue`;
`beginHTTPPost` reads length / type / lang / filename / autopaste through
`HTTPHeaderValue.first` as well.

Handshake Origin / `Sec-WebSocket-Key` / version already use `HTTPHeaderValue.first`.

## Smoke (owner Mac, after the Swift wire)

```bash
# before: record dropCount from GET /health
python3 scripts/smoke-ws.py --origin http://evil.example --expect-reject
# POST /drop with Origin: http://evil.example must 403 and must not increment dropCount
```

`Access-Control-Allow-Origin: *` on `GET /health` remains a recon oracle (`ip`,
`ips`, `ifaces`). Fold that into MP-04: echo an allowlisted Origin, keep `*` only
when Origin is missing.
