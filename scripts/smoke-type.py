#!/usr/bin/env python3
"""MagicPad keyboard inject smoke: type + backspace + clearField + burst + clamp/alias + edit battery over WebSocket."""
from __future__ import annotations

import json
import sys
import time

HOST = "127.0.0.1"
PORT = 7878


def main() -> int:
    try:
        import websocket  # type: ignore
    except ImportError:
        print("NEED: pip3 install websocket-client")
        return 2

    url = f"ws://{HOST}:{PORT}"
    print(f"smoke-type → {url}")
    try:
        ws = websocket.create_connection(url, timeout=8)
    except Exception as e:
        print(f"ws open FAIL: {e}")
        return 1

    def send(obj: dict) -> dict | None:
        ws.send(json.dumps(obj))
        try:
            raw = ws.recv()
            if isinstance(raw, bytes):
                return None
            return json.loads(raw)
        except Exception as e:
            print(f"recv err: {e}")
            return None

    ok = True
    ax_denied = False

    def check(ack: dict | None, label: str, *, expect_ok: bool | None = True,
              expect_reason: str | None = None) -> None:
        """expect_ok: True require ok; False require not ok; None ignore ok (ax/protocol only).
        expect_reason: if set, reason must equal (or match when not ax_denied).
        """
        nonlocal ok, ax_denied
        print(f"{label}:", ack)
        if not ack:
            ok = False
            return
        # Protocol contract: every key/type ack must carry ok + reason
        if "ok" not in ack or "reason" not in ack:
            print(f"  FAIL protocol: missing ok/reason in {label}")
            ok = False
            return
        reason = ack.get("reason")
        if reason == "ax_denied":
            ax_denied = True
            # Still allow expected-failure cases to assert reason when not ax
            if expect_ok is False and expect_reason and expect_reason != "ax_denied":
                # Server blocked by AX before mapping; protocol still OK for inject path
                return
            return  # protocol OK; inject blocked until Accessibility
        if expect_reason is not None and reason != expect_reason:
            print(f"  FAIL reason: want {expect_reason!r} got {reason!r}")
            ok = False
            return
        if expect_ok is True and not ack.get("ok"):
            print(f"  FAIL expected ok=true")
            ok = False
        elif expect_ok is False and ack.get("ok"):
            print(f"  FAIL expected ok=false")
            ok = False

    send({"type": "hello", "ts": time.time()})

    # --- baseline sequence (P4-3) ---
    check(send({"type": "type", "text": "Ab12测", "ts": time.time()}), "type")
    check(send({"type": "key", "action": "backspace", "count": 2, "ts": time.time()}), "backspace×2")
    check(send({"type": "key", "action": "backspace", "count": 40, "ts": time.time()}), "backspace×40")
    check(send({"type": "key", "action": "clearField", "ts": time.time()}), "clearField")
    check(send({"type": "key", "action": "unstick", "ts": time.time()}), "unstick")

    # --- OPT-02 burst: type → backspace×N → type → clearField → unstick interleaved ---
    print("--- burst ---")
    burst = [
        ("burst type short", {"type": "type", "text": "xy", "ts": time.time()}),
        ("burst backspace×2", {"type": "key", "action": "backspace", "count": 2, "ts": time.time()}),
        ("burst type mid", {"type": "type", "text": "Z9", "ts": time.time()}),
        ("burst backspace×1", {"type": "key", "action": "backspace", "count": 1, "ts": time.time()}),
        ("burst clearField", {"type": "key", "action": "clearField", "ts": time.time()}),
        ("burst unstick", {"type": "key", "action": "unstick", "ts": time.time()}),
        ("burst type again", {"type": "type", "text": "ok", "ts": time.time()}),
        ("burst backspace×2 again", {"type": "key", "action": "backspace", "count": 2, "ts": time.time()}),
        ("burst clearField again", {"type": "key", "action": "clearField", "ts": time.time()}),
        ("burst unstick final", {"type": "key", "action": "unstick", "ts": time.time()}),
    ]
    for label, msg in burst:
        check(send(msg), label)

    # --- OPT-03: empty_type + oversize clamp (2001 → type_truncated) ---
    print("--- type clamp ---")
    check(
        send({"type": "type", "text": "", "ts": time.time()}),
        "empty_type",
        expect_ok=False,
        expect_reason="empty_type",
    )
    oversize = "z" * 2001
    check(
        send({"type": "type", "text": oversize, "ts": time.time()}),
        "type_truncated 2001",
        expect_ok=True,
        expect_reason="type_truncated",
    )
    # cleanup after oversize inject
    check(send({"type": "key", "action": "clearField", "ts": time.time()}), "clear after trunc")
    check(send({"type": "key", "action": "unstick", "ts": time.time()}), "unstick after trunc")

    # --- OPT-04: unknown_action fails; alias return → enter ---
    print("--- action alias / unknown ---")
    check(
        send({"type": "key", "action": "explode_hack", "ts": time.time()}),
        "unknown_action",
        expect_ok=False,
        expect_reason="unknown_action",
    )
    check(
        send({"type": "key", "action": "return", "count": 1, "ts": time.time()}),
        "alias return→enter",
        expect_ok=True,
        expect_reason="enter",
    )
    check(
        send({"type": "key", "action": "unstick", "ts": time.time()}),
        "unstick after alias",
        expect_ok=True,
        expect_reason="unstick",
    )

    # --- OPT-05: casefold + short aliases (Backspace / RETURN / BS / ESC) ---
    print("--- casefold / short alias ---")
    check(
        send({"type": "key", "action": "Backspace", "count": 1, "ts": time.time()}),
        "casefold Backspace",
        expect_ok=True,
        expect_reason="backspace",
    )
    check(
        send({"type": "key", "action": "RETURN", "count": 1, "ts": time.time()}),
        "casefold RETURN→enter",
        expect_ok=True,
        expect_reason="enter",
    )
    check(
        send({"type": "key", "action": "BS", "count": 1, "ts": time.time()}),
        "alias BS→backspace",
        expect_ok=True,
        expect_reason="backspace",
    )
    check(
        send({"type": "key", "action": "ESC", "ts": time.time()}),
        "alias ESC→escape",
        expect_ok=True,
        expect_reason="escape",
    )
    check(
        send({"type": "key", "action": "unstick", "ts": time.time()}),
        "unstick after casefold",
        expect_ok=True,
        expect_reason="unstick",
    )

    # --- OPT-07: edit-key battery (canonical reason; ax_denied still protocol PASS) ---
    print("--- edit-key battery ---")
    check(
        send({"type": "key", "action": "wordBackspace", "count": 2, "ts": time.time()}),
        "wordBackspace×2",
        expect_ok=True,
        expect_reason="wordBackspace",
    )
    check(
        send({"type": "key", "action": "wb", "count": 1, "ts": time.time()}),
        "alias wb→wordBackspace",
        expect_ok=True,
        expect_reason="wordBackspace",
    )
    check(
        send({"type": "key", "action": "altbs", "count": 1, "ts": time.time()}),
        "alias altbs→wordBackspace",
        expect_ok=True,
        expect_reason="wordBackspace",
    )
    check(
        send({"type": "key", "action": "left", "count": 3, "ts": time.time()}),
        "left×3",
        expect_ok=True,
        expect_reason="left",
    )
    check(
        send({"type": "key", "action": "right", "count": 2, "ts": time.time()}),
        "right×2",
        expect_ok=True,
        expect_reason="right",
    )
    check(
        send({"type": "key", "action": "up", "count": 1, "ts": time.time()}),
        "up×1",
        expect_ok=True,
        expect_reason="up",
    )
    check(
        send({"type": "key", "action": "down", "count": 1, "ts": time.time()}),
        "down×1",
        expect_ok=True,
        expect_reason="down",
    )
    check(
        send({"type": "key", "action": "selectAll", "ts": time.time()}),
        "selectAll",
        expect_ok=True,
        expect_reason="selectAll",
    )
    check(
        send({"type": "key", "action": "undo", "ts": time.time()}),
        "undo",
        expect_ok=True,
        expect_reason="undo",
    )
    check(
        send({"type": "key", "action": "cut", "ts": time.time()}),
        "cut",
        expect_ok=True,
        expect_reason="cut",
    )
    check(
        send({"type": "key", "action": "copy", "ts": time.time()}),
        "copy",
        expect_ok=True,
        expect_reason="copy",
    )
    check(
        send({"type": "key", "action": "paste", "ts": time.time()}),
        "paste",
        expect_ok=True,
        expect_reason="paste",
    )
    check(
        send({"type": "key", "action": "delete", "count": 1, "ts": time.time()}),
        "delete×1",
        expect_ok=True,
        expect_reason="delete",
    )
    check(
        send({"type": "key", "action": "forwardDelete", "count": 1, "ts": time.time()}),
        "forwardDelete×1",
        expect_ok=True,
        expect_reason="forwardDelete",
    )
    check(
        send({"type": "key", "action": "fwd", "count": 1, "ts": time.time()}),
        "alias fwd→forwardDelete",
        expect_ok=True,
        expect_reason="forwardDelete",
    )
    check(
        send({"type": "key", "action": "fwdDel", "count": 1, "ts": time.time()}),
        "alias fwdDel→forwardDelete",
        expect_ok=True,
        expect_reason="forwardDelete",
    )
    check(
        send({"type": "key", "action": "unstick", "ts": time.time()}),
        "unstick after edit battery",
        expect_ok=True,
        expect_reason="unstick",
    )

    # --- OPT-08: empty / missing action → empty_action ok=false ---
    print("--- empty_action ---")
    check(
        send({"type": "key", "action": "", "ts": time.time()}),
        "empty action string",
        expect_ok=False,
        expect_reason="empty_action",
    )
    check(
        send({"type": "key", "ts": time.time()}),
        "missing action field",
        expect_ok=False,
        expect_reason="empty_action",
    )
    check(
        send({"type": "key", "action": "   ", "ts": time.time()}),
        "whitespace action",
        expect_ok=False,
        expect_reason="empty_action",
    )

    # --- OPT-09: type payload pure parse (malformed hardening) ---
    print("--- type parse malformed ---")
    check(
        send({"type": "type", "ts": time.time()}),
        "type missing text",
        expect_ok=False,
        expect_reason="empty_type",
    )
    check(
        send({"type": "type", "text": None, "ts": time.time()}),
        "type text null",
        expect_ok=False,
        expect_reason="empty_type",
    )
    check(
        send({"type": "type", "text": 123, "ts": time.time()}),
        "type text number→bad_type",
        expect_ok=False,
        expect_reason="bad_type",
    )
    check(
        send({"type": "type", "text": True, "ts": time.time()}),
        "type text bool→bad_type",
        expect_ok=False,
        expect_reason="bad_type",
    )
    check(
        send({"type": "type", "text": ["a"], "ts": time.time()}),
        "type text array→bad_type",
        expect_ok=False,
        expect_reason="bad_type",
    )

    # --- OPT-10: nav keys tab/home/end (+ alias eol) ---
    print("--- nav keys tab/home/end ---")
    check(
        send({"type": "key", "action": "tab", "count": 1, "ts": time.time()}),
        "tab",
        expect_ok=True,
        expect_reason="tab",
    )
    check(
        send({"type": "key", "action": "home", "count": 1, "ts": time.time()}),
        "home",
        expect_ok=True,
        expect_reason="home",
    )
    check(
        send({"type": "key", "action": "end", "count": 1, "ts": time.time()}),
        "end",
        expect_ok=True,
        expect_reason="end",
    )
    check(
        send({"type": "key", "action": "eol", "count": 1, "ts": time.time()}),
        "alias eol→end",
        expect_ok=True,
        expect_reason="end",
    )
    check(
        send({"type": "key", "action": "unstick", "ts": time.time()}),
        "unstick after nav",
        expect_ok=True,
        expect_reason="unstick",
    )

    # --- OPT-11: key action pure parse (malformed hardening) ---
    print("--- key action parse malformed ---")
    check(
        send({"type": "key", "action": None, "ts": time.time()}),
        "key action null→empty_action",
        expect_ok=False,
        expect_reason="empty_action",
    )
    check(
        send({"type": "key", "action": 123, "ts": time.time()}),
        "key action number→bad_action",
        expect_ok=False,
        expect_reason="bad_action",
    )
    check(
        send({"type": "key", "action": True, "ts": time.time()}),
        "key action bool→bad_action",
        expect_ok=False,
        expect_reason="bad_action",
    )
    check(
        send({"type": "key", "action": ["backspace"], "ts": time.time()}),
        "key action array→bad_action",
        expect_ok=False,
        expect_reason="bad_action",
    )
    check(
        send({"type": "key", "action": {"k": "v"}, "ts": time.time()}),
        "key action dict→bad_action",
        expect_ok=False,
        expect_reason="bad_action",
    )

    # --- OPT-12: pageUp/pageDown (+ aliases pgup/pgdn) ---
    print("--- nav keys pageUp/pageDown ---")
    check(
        send({"type": "key", "action": "pageUp", "count": 1, "ts": time.time()}),
        "pageUp",
        expect_ok=True,
        expect_reason="pageUp",
    )
    check(
        send({"type": "key", "action": "pageDown", "count": 1, "ts": time.time()}),
        "pageDown",
        expect_ok=True,
        expect_reason="pageDown",
    )
    check(
        send({"type": "key", "action": "pgup", "count": 1, "ts": time.time()}),
        "alias pgup→pageUp",
        expect_ok=True,
        expect_reason="pageUp",
    )
    check(
        send({"type": "key", "action": "pgdn", "count": 1, "ts": time.time()}),
        "alias pgdn→pageDown",
        expect_ok=True,
        expect_reason="pageDown",
    )
    check(
        send({"type": "key", "action": "PageUp", "count": 1, "ts": time.time()}),
        "casefold PageUp→pageUp",
        expect_ok=True,
        expect_reason="pageUp",
    )
    check(
        send({"type": "key", "action": "unstick", "ts": time.time()}),
        "unstick after pageUp/pageDown",
        expect_ok=True,
        expect_reason="unstick",
    )

    # --- OPT-13: wordLeft/wordRight (+ aliases) ---
    print("--- wordLeft/wordRight battery ---")
    check(
        send({"type": "key", "action": "wordLeft", "count": 2, "ts": time.time()}),
        "wordLeft×2",
        expect_ok=True,
        expect_reason="wordLeft",
    )
    check(
        send({"type": "key", "action": "wordRight", "count": 1, "ts": time.time()}),
        "wordRight",
        expect_ok=True,
        expect_reason="wordRight",
    )
    check(
        send({"type": "key", "action": "wleft", "count": 1, "ts": time.time()}),
        "alias wleft→wordLeft",
        expect_ok=True,
        expect_reason="wordLeft",
    )
    check(
        send({"type": "key", "action": "wright", "count": 1, "ts": time.time()}),
        "alias wright→wordRight",
        expect_ok=True,
        expect_reason="wordRight",
    )
    check(
        send({"type": "key", "action": "altleft", "count": 1, "ts": time.time()}),
        "alias altleft→wordLeft",
        expect_ok=True,
        expect_reason="wordLeft",
    )
    check(
        send({"type": "key", "action": "optright", "count": 1, "ts": time.time()}),
        "alias optright→wordRight",
        expect_ok=True,
        expect_reason="wordRight",
    )
    check(
        send({"type": "key", "action": "backspace", "count": 1, "ts": time.time()}),
        "plain ⌫ after wordLeft/Right (hot path)",
        expect_ok=True,
        expect_reason="backspace",
    )
    check(
        send({"type": "key", "action": "unstick", "ts": time.time()}),
        "unstick after wordLeft/wordRight",
        expect_ok=True,
        expect_reason="unstick",
    )

    # --- OPT-15: selectLeft/selectRight (+ aliases) ---
    print("--- selectLeft/selectRight battery ---")
    check(
        send({"type": "key", "action": "selectLeft", "count": 2, "ts": time.time()}),
        "selectLeft×2",
        expect_ok=True,
        expect_reason="selectLeft",
    )
    check(
        send({"type": "key", "action": "selectRight", "count": 1, "ts": time.time()}),
        "selectRight",
        expect_ok=True,
        expect_reason="selectRight",
    )
    check(
        send({"type": "key", "action": "sleft", "count": 1, "ts": time.time()}),
        "alias sleft→selectLeft",
        expect_ok=True,
        expect_reason="selectLeft",
    )
    check(
        send({"type": "key", "action": "sright", "count": 1, "ts": time.time()}),
        "alias sright→selectRight",
        expect_ok=True,
        expect_reason="selectRight",
    )
    check(
        send({"type": "key", "action": "shiftleft", "count": 1, "ts": time.time()}),
        "alias shiftleft→selectLeft",
        expect_ok=True,
        expect_reason="selectLeft",
    )
    check(
        send({"type": "key", "action": "ser", "count": 1, "ts": time.time()}),
        "alias ser→selectRight",
        expect_ok=True,
        expect_reason="selectRight",
    )
    check(
        send({"type": "key", "action": "backspace", "count": 1, "ts": time.time()}),
        "plain ⌫ after selectLeft/Right (hot path)",
        expect_ok=True,
        expect_reason="backspace",
    )
    check(
        send({"type": "key", "action": "unstick", "ts": time.time()}),
        "unstick after selectLeft/selectRight",
        expect_ok=True,
        expect_reason="unstick",
    )

    # --- OPT-16: selectWordLeft/selectWordRight (+ aliases) ---
    print("--- selectWordLeft/selectWordRight battery ---")
    check(
        send({"type": "key", "action": "selectWordLeft", "count": 2, "ts": time.time()}),
        "selectWordLeft×2",
        expect_ok=True,
        expect_reason="selectWordLeft",
    )
    check(
        send({"type": "key", "action": "selectWordRight", "count": 1, "ts": time.time()}),
        "selectWordRight",
        expect_ok=True,
        expect_reason="selectWordRight",
    )
    check(
        send({"type": "key", "action": "swleft", "count": 1, "ts": time.time()}),
        "alias swleft→selectWordLeft",
        expect_ok=True,
        expect_reason="selectWordLeft",
    )
    check(
        send({"type": "key", "action": "swright", "count": 1, "ts": time.time()}),
        "alias swright→selectWordRight",
        expect_ok=True,
        expect_reason="selectWordRight",
    )
    check(
        send({"type": "key", "action": "shiftoptleft", "count": 1, "ts": time.time()}),
        "alias shiftoptleft→selectWordLeft",
        expect_ok=True,
        expect_reason="selectWordLeft",
    )
    check(
        send({"type": "key", "action": "shiftwordright", "count": 1, "ts": time.time()}),
        "alias shiftwordright→selectWordRight",
        expect_ok=True,
        expect_reason="selectWordRight",
    )
    check(
        send({"type": "key", "action": "left", "count": 1, "ts": time.time()}),
        "plain left after selectWord (hot path)",
        expect_ok=True,
        expect_reason="left",
    )
    check(
        send({"type": "key", "action": "unstick", "ts": time.time()}),
        "unstick after selectWordLeft/selectWordRight",
        expect_ok=True,
        expect_reason="unstick",
    )

    # --- OPT-17: selectUp/selectDown (+ aliases) ---
    print("--- selectUp/selectDown battery ---")
    check(
        send({"type": "key", "action": "selectUp", "count": 2, "ts": time.time()}),
        "selectUp×2",
        expect_ok=True,
        expect_reason="selectUp",
    )
    check(
        send({"type": "key", "action": "selectDown", "count": 1, "ts": time.time()}),
        "selectDown",
        expect_ok=True,
        expect_reason="selectDown",
    )
    check(
        send({"type": "key", "action": "sup", "count": 1, "ts": time.time()}),
        "alias sup→selectUp",
        expect_ok=True,
        expect_reason="selectUp",
    )
    check(
        send({"type": "key", "action": "sdn", "count": 1, "ts": time.time()}),
        "alias sdn→selectDown",
        expect_ok=True,
        expect_reason="selectDown",
    )
    check(
        send({"type": "key", "action": "shiftup", "count": 1, "ts": time.time()}),
        "alias shiftup→selectUp",
        expect_ok=True,
        expect_reason="selectUp",
    )
    check(
        send({"type": "key", "action": "seld", "count": 1, "ts": time.time()}),
        "alias seld→selectDown",
        expect_ok=True,
        expect_reason="selectDown",
    )
    check(
        send({"type": "key", "action": "up", "count": 1, "ts": time.time()}),
        "plain up after selectUp/Down (hot path)",
        expect_ok=True,
        expect_reason="up",
    )
    check(
        send({"type": "key", "action": "down", "count": 1, "ts": time.time()}),
        "plain down after selectUp/Down (hot path)",
        expect_ok=True,
        expect_reason="down",
    )
    check(
        send({"type": "key", "action": "backspace", "count": 1, "ts": time.time()}),
        "plain ⌫ after selectUp/Down (hot path)",
        expect_ok=True,
        expect_reason="backspace",
    )
    check(
        send({"type": "key", "action": "unstick", "ts": time.time()}),
        "unstick after selectUp/selectDown",
        expect_ok=True,
        expect_reason="unstick",
    )

    # --- OPT-18: selectHome/selectEnd (+ aliases) ---
    print("--- selectHome/selectEnd battery ---")
    check(
        send({"type": "key", "action": "selectHome", "count": 1, "ts": time.time()}),
        "selectHome",
        expect_ok=True,
        expect_reason="selectHome",
    )
    check(
        send({"type": "key", "action": "selectEnd", "count": 1, "ts": time.time()}),
        "selectEnd",
        expect_ok=True,
        expect_reason="selectEnd",
    )
    check(
        send({"type": "key", "action": "shome", "count": 1, "ts": time.time()}),
        "alias shome→selectHome",
        expect_ok=True,
        expect_reason="selectHome",
    )
    check(
        send({"type": "key", "action": "send", "count": 1, "ts": time.time()}),
        "alias send→selectEnd",
        expect_ok=True,
        expect_reason="selectEnd",
    )
    check(
        send({"type": "key", "action": "shifthome", "count": 1, "ts": time.time()}),
        "alias shifthome→selectHome",
        expect_ok=True,
        expect_reason="selectHome",
    )
    check(
        send({"type": "key", "action": "selend", "count": 1, "ts": time.time()}),
        "alias selend→selectEnd",
        expect_ok=True,
        expect_reason="selectEnd",
    )
    check(
        send({"type": "key", "action": "home", "count": 1, "ts": time.time()}),
        "plain home after selectHome/End (hot path)",
        expect_ok=True,
        expect_reason="home",
    )
    check(
        send({"type": "key", "action": "end", "count": 1, "ts": time.time()}),
        "plain end after selectHome/End (hot path)",
        expect_ok=True,
        expect_reason="end",
    )
    check(
        send({"type": "key", "action": "backspace", "count": 1, "ts": time.time()}),
        "plain ⌫ after selectHome/End (hot path)",
        expect_ok=True,
        expect_reason="backspace",
    )
    check(
        send({"type": "key", "action": "unstick", "ts": time.time()}),
        "unstick after selectHome/selectEnd",
        expect_ok=True,
        expect_reason="unstick",
    )

    # --- OPT-19: selectPageUp/selectPageDown (+ aliases) ---
    print("--- selectPageUp/selectPageDown battery ---")
    check(
        send({"type": "key", "action": "selectPageUp", "count": 1, "ts": time.time()}),
        "selectPageUp",
        expect_ok=True,
        expect_reason="selectPageUp",
    )
    check(
        send({"type": "key", "action": "selectPageDown", "count": 1, "ts": time.time()}),
        "selectPageDown",
        expect_ok=True,
        expect_reason="selectPageDown",
    )
    check(
        send({"type": "key", "action": "spup", "count": 1, "ts": time.time()}),
        "alias spup→selectPageUp",
        expect_ok=True,
        expect_reason="selectPageUp",
    )
    check(
        send({"type": "key", "action": "spdn", "count": 1, "ts": time.time()}),
        "alias spdn→selectPageDown",
        expect_ok=True,
        expect_reason="selectPageDown",
    )
    check(
        send({"type": "key", "action": "shiftpgup", "count": 1, "ts": time.time()}),
        "alias shiftpgup→selectPageUp",
        expect_ok=True,
        expect_reason="selectPageUp",
    )
    check(
        send({"type": "key", "action": "selpgdn", "count": 1, "ts": time.time()}),
        "alias selpgdn→selectPageDown",
        expect_ok=True,
        expect_reason="selectPageDown",
    )
    check(
        send({"type": "key", "action": "SelectPageUp", "count": 1, "ts": time.time()}),
        "casefold SelectPageUp→selectPageUp",
        expect_ok=True,
        expect_reason="selectPageUp",
    )
    check(
        send({"type": "key", "action": "pageUp", "count": 1, "ts": time.time()}),
        "plain pageUp after selectPageUp/Down (hot path)",
        expect_ok=True,
        expect_reason="pageUp",
    )
    check(
        send({"type": "key", "action": "pageDown", "count": 1, "ts": time.time()}),
        "plain pageDown after selectPageUp/Down (hot path)",
        expect_ok=True,
        expect_reason="pageDown",
    )
    check(
        send({"type": "key", "action": "backspace", "count": 1, "ts": time.time()}),
        "plain ⌫ after selectPageUp/Down (hot path)",
        expect_ok=True,
        expect_reason="backspace",
    )
    check(
        send({"type": "key", "action": "unstick", "ts": time.time()}),
        "unstick after selectPageUp/selectPageDown",
        expect_ok=True,
        expect_reason="unstick",
    )

    # --- OPT-20: redo (+ aliases rdo/shiftundo/cmdshiftz) ---
    print("--- redo battery ---")
    check(
        send({"type": "key", "action": "redo", "count": 1, "ts": time.time()}),
        "redo",
        expect_ok=True,
        expect_reason="redo",
    )
    check(
        send({"type": "key", "action": "rdo", "count": 1, "ts": time.time()}),
        "alias rdo→redo",
        expect_ok=True,
        expect_reason="redo",
    )
    check(
        send({"type": "key", "action": "shiftundo", "count": 1, "ts": time.time()}),
        "alias shiftundo→redo",
        expect_ok=True,
        expect_reason="redo",
    )
    check(
        send({"type": "key", "action": "cmdshiftz", "count": 1, "ts": time.time()}),
        "alias cmdshiftz→redo",
        expect_ok=True,
        expect_reason="redo",
    )
    check(
        send({"type": "key", "action": "REDO", "count": 1, "ts": time.time()}),
        "casefold REDO→redo",
        expect_ok=True,
        expect_reason="redo",
    )
    check(
        send({"type": "key", "action": "undo", "count": 1, "ts": time.time()}),
        "undo path still ok after redo",
        expect_ok=True,
        expect_reason="undo",
    )
    check(
        send({"type": "key", "action": "backspace", "count": 1, "ts": time.time()}),
        "plain ⌫ after redo (hot path)",
        expect_ok=True,
        expect_reason="backspace",
    )
    check(
        send({"type": "key", "action": "unstick", "ts": time.time()}),
        "unstick after redo",
        expect_ok=True,
        expect_reason="unstick",
    )

    # --- OPT-21: lineStart/lineEnd (+ aliases; eol still → end) ---
    print("--- lineStart/lineEnd battery ---")
    check(
        send({"type": "key", "action": "lineStart", "count": 1, "ts": time.time()}),
        "lineStart",
        expect_ok=True,
        expect_reason="lineStart",
    )
    check(
        send({"type": "key", "action": "lineEnd", "count": 1, "ts": time.time()}),
        "lineEnd",
        expect_ok=True,
        expect_reason="lineEnd",
    )
    check(
        send({"type": "key", "action": "lstart", "count": 1, "ts": time.time()}),
        "alias lstart→lineStart",
        expect_ok=True,
        expect_reason="lineStart",
    )
    check(
        send({"type": "key", "action": "lend", "count": 1, "ts": time.time()}),
        "alias lend→lineEnd",
        expect_ok=True,
        expect_reason="lineEnd",
    )
    check(
        send({"type": "key", "action": "cmdleft", "count": 1, "ts": time.time()}),
        "alias cmdleft→lineStart",
        expect_ok=True,
        expect_reason="lineStart",
    )
    check(
        send({"type": "key", "action": "cmdright", "count": 1, "ts": time.time()}),
        "alias cmdright→lineEnd",
        expect_ok=True,
        expect_reason="lineEnd",
    )
    check(
        send({"type": "key", "action": "bol", "count": 1, "ts": time.time()}),
        "alias bol→lineStart",
        expect_ok=True,
        expect_reason="lineStart",
    )
    check(
        send({"type": "key", "action": "sol", "count": 1, "ts": time.time()}),
        "alias sol→lineStart",
        expect_ok=True,
        expect_reason="lineStart",
    )
    check(
        send({"type": "key", "action": "softend", "count": 1, "ts": time.time()}),
        "alias softend→lineEnd",
        expect_ok=True,
        expect_reason="lineEnd",
    )
    check(
        send({"type": "key", "action": "LineStart", "count": 1, "ts": time.time()}),
        "casefold LineStart→lineStart",
        expect_ok=True,
        expect_reason="lineStart",
    )
    check(
        send({"type": "key", "action": "eol", "count": 1, "ts": time.time()}),
        "alias eol still→end (not lineEnd)",
        expect_ok=True,
        expect_reason="end",
    )
    check(
        send({"type": "key", "action": "left", "count": 1, "ts": time.time()}),
        "plain left after lineStart/End (hot path)",
        expect_ok=True,
        expect_reason="left",
    )
    check(
        send({"type": "key", "action": "right", "count": 1, "ts": time.time()}),
        "plain right after lineStart/End (hot path)",
        expect_ok=True,
        expect_reason="right",
    )
    check(
        send({"type": "key", "action": "backspace", "count": 1, "ts": time.time()}),
        "plain ⌫ after lineStart/End (hot path)",
        expect_ok=True,
        expect_reason="backspace",
    )
    check(
        send({"type": "key", "action": "unstick", "ts": time.time()}),
        "unstick after lineStart/lineEnd",
        expect_ok=True,
        expect_reason="unstick",
    )

    # --- OPT-22: lineBackspace/lineForwardDelete (+ aliases) ---
    print("--- lineBackspace/lineForwardDelete battery ---")
    check(
        send({"type": "key", "action": "lineBackspace", "count": 1, "ts": time.time()}),
        "lineBackspace",
        expect_ok=True,
        expect_reason="lineBackspace",
    )
    check(
        send({"type": "key", "action": "lineForwardDelete", "count": 1, "ts": time.time()}),
        "lineForwardDelete",
        expect_ok=True,
        expect_reason="lineForwardDelete",
    )
    check(
        send({"type": "key", "action": "lbs", "count": 1, "ts": time.time()}),
        "alias lbs→lineBackspace",
        expect_ok=True,
        expect_reason="lineBackspace",
    )
    check(
        send({"type": "key", "action": "lfd", "count": 1, "ts": time.time()}),
        "alias lfd→lineForwardDelete",
        expect_ok=True,
        expect_reason="lineForwardDelete",
    )
    check(
        send({"type": "key", "action": "cmdbs", "count": 1, "ts": time.time()}),
        "alias cmdbs→lineBackspace",
        expect_ok=True,
        expect_reason="lineBackspace",
    )
    check(
        send({"type": "key", "action": "cmdfwd", "count": 1, "ts": time.time()}),
        "alias cmdfwd→lineForwardDelete",
        expect_ok=True,
        expect_reason="lineForwardDelete",
    )
    check(
        send({"type": "key", "action": "deletelinestart", "count": 1, "ts": time.time()}),
        "alias deletelinestart→lineBackspace",
        expect_ok=True,
        expect_reason="lineBackspace",
    )
    check(
        send({"type": "key", "action": "dellineend", "count": 1, "ts": time.time()}),
        "alias dellineend→lineForwardDelete",
        expect_ok=True,
        expect_reason="lineForwardDelete",
    )
    check(
        send({"type": "key", "action": "LineBackspace", "count": 1, "ts": time.time()}),
        "casefold LineBackspace→lineBackspace",
        expect_ok=True,
        expect_reason="lineBackspace",
    )
    check(
        send({"type": "key", "action": "backspace", "count": 1, "ts": time.time()}),
        "plain ⌫ after lineBackspace/lineForwardDelete (hot path)",
        expect_ok=True,
        expect_reason="backspace",
    )
    check(
        send({"type": "key", "action": "delete", "count": 1, "ts": time.time()}),
        "plain delete after line deletes (hot path)",
        expect_ok=True,
        expect_reason="delete",
    )
    check(
        send({"type": "key", "action": "forwardDelete", "count": 1, "ts": time.time()}),
        "plain forwardDelete after line deletes (hot path)",
        expect_ok=True,
        expect_reason="forwardDelete",
    )
    check(
        send({"type": "key", "action": "unstick", "ts": time.time()}),
        "unstick after lineBackspace/lineForwardDelete",
        expect_ok=True,
        expect_reason="unstick",
    )


    # --- OPT-23: selectLineStart/selectLineEnd (+ aliases) ---
    print("--- selectLineStart/selectLineEnd battery ---")
    check(
        send({"type": "key", "action": "selectLineStart", "count": 1, "ts": time.time()}),
        "selectLineStart",
        expect_ok=True,
        expect_reason="selectLineStart",
    )
    check(
        send({"type": "key", "action": "selectLineEnd", "count": 1, "ts": time.time()}),
        "selectLineEnd",
        expect_ok=True,
        expect_reason="selectLineEnd",
    )
    check(
        send({"type": "key", "action": "slstart", "count": 1, "ts": time.time()}),
        "alias slstart→selectLineStart",
        expect_ok=True,
        expect_reason="selectLineStart",
    )
    check(
        send({"type": "key", "action": "cmdshiftright", "count": 1, "ts": time.time()}),
        "alias cmdshiftright→selectLineEnd",
        expect_ok=True,
        expect_reason="selectLineEnd",
    )
    check(
        send({"type": "key", "action": "left", "count": 1, "ts": time.time()}),
        "plain left after selectLine (hot path)",
        expect_ok=True,
        expect_reason="left",
    )
    check(
        send({"type": "key", "action": "backspace", "count": 1, "ts": time.time()}),
        "plain ⌫ after selectLine (hot path)",
        expect_ok=True,
        expect_reason="backspace",
    )
    check(
        send({"type": "key", "action": "unstick", "count": 1, "ts": time.time()}),
        "unstick after selectLineStart/End",
        expect_ok=True,
        expect_reason="unstick",
    )


    # --- H1-6: wordForwardDelete (+ aliases) ---
    print("--- wordForwardDelete battery ---")
    check(
        send({"type": "key", "action": "wordForwardDelete", "count": 1, "ts": time.time()}),
        "wordForwardDelete",
        expect_ok=True,
        expect_reason="wordForwardDelete",
    )
    check(
        send({"type": "key", "action": "wfd", "count": 1, "ts": time.time()}),
        "alias wfd→wordForwardDelete",
        expect_ok=True,
        expect_reason="wordForwardDelete",
    )
    check(
        send({"type": "key", "action": "altfwd", "count": 1, "ts": time.time()}),
        "alias altfwd→wordForwardDelete",
        expect_ok=True,
        expect_reason="wordForwardDelete",
    )
    check(
        send({"type": "key", "action": "backspace", "count": 1, "ts": time.time()}),
        "plain ⌫ after wordForwardDelete (hot path)",
        expect_ok=True,
        expect_reason="backspace",
    )
    check(
        send({"type": "key", "action": "unstick", "count": 1, "ts": time.time()}),
        "unstick after wordForwardDelete",
        expect_ok=True,
        expect_reason="unstick",
    )

    # --- OPT-14: bad_count (malformed count → ok=false, no inject) ---
    print("--- bad_count ---")
    check(
        send({"type": "key", "action": "backspace", "count": True, "ts": time.time()}),
        "count bool→bad_count",
        expect_ok=False,
        expect_reason="bad_count",
    )
    check(
        send({"type": "key", "action": "left", "count": [3], "ts": time.time()}),
        "count array→bad_count",
        expect_ok=False,
        expect_reason="bad_count",
    )
    check(
        send({"type": "key", "action": "wordLeft", "count": {"n": 1}, "ts": time.time()}),
        "count dict→bad_count",
        expect_ok=False,
        expect_reason="bad_count",
    )
    check(
        send({"type": "key", "action": "right", "count": "nope", "ts": time.time()}),
        "count non-int string→bad_count",
        expect_ok=False,
        expect_reason="bad_count",
    )
    # valid string-int still works
    check(
        send({"type": "key", "action": "backspace", "count": "2", "ts": time.time()}),
        "count string-int still ok",
        expect_ok=True,
        expect_reason="backspace",
    )
    check(
        send({"type": "key", "action": "unstick", "ts": time.time()}),
        "unstick after bad_count (lastKey unstick-capable)",
        expect_ok=True,
        expect_reason="unstick",
    )

    ws.close()

    note = "(type/key + burst + clamp + alias + casefold + edit battery + empty_action + type-parse + nav + bad_action + pageUp/pageDown + wordLeft/Right + selectLeft/Right + selectWordLeft/Right + selectUp/Down + selectHome/End + selectPageUp/Down + redo + lineStart/End + lineBackspace/lineForwardDelete + selectLineStart/End + wordForwardDelete + bad_count)"
    if ax_denied:
        note += " [ax_denied — re-check Accessibility for real inject]"
    print("OVERALL:", "PASS" if ok else "FAIL", note)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
