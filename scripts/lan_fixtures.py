"""Shared LAN IPv4 fixtures (Cycle 31).

Canonical rows live in scripts/fixtures/lan-vectors.json (same table
test-protocol.py and LANAddressTests.swift already consume).
This module does not parse IPv4 — generate_qr.is_private / is_private_ipv4 do.
"""

from __future__ import annotations

import json
from pathlib import Path

_VECTORS = Path(__file__).resolve().parent / "fixtures" / "lan-vectors.json"


def _load() -> list[tuple[str, bool, str]]:
    data = json.loads(_VECTORS.read_text(encoding="utf-8"))
    rows: list[tuple[str, bool, str]] = []
    for row in data["vectors"]:
        ip = str(row["ip"])
        expected = bool(row["private"])
        note = str(row.get("note") or row.get("id") or "")
        rows.append((ip, expected, note))
    return rows


LAN_FIXTURES: list[tuple[str, bool, str]] = _load()


def fixture_ips() -> list[str]:
    return [ip for ip, _, _ in LAN_FIXTURES]
