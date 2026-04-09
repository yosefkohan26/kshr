#!/usr/bin/env python3

from __future__ import annotations

import os
from pathlib import Path


def resolve_kshr_cli() -> str:
    explicit = os.environ.get("KSHR_CLI_BIN") or os.environ.get("KSHR_CLI")
    if explicit and os.path.exists(explicit) and os.access(explicit, os.X_OK):
        return explicit

    recorded_path = Path("/tmp/kshr-last-cli-path")
    if recorded_path.exists():
        candidate = recorded_path.read_text(encoding="utf-8").strip()
        if candidate and os.path.exists(candidate) and os.access(candidate, os.X_OK):
            return candidate

    raise RuntimeError(
        "Unable to find kshr CLI binary. Set KSHR_CLI_BIN or run ./scripts/reload.sh --tag <tag> first."
    )
