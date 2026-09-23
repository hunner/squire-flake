#!/usr/bin/env python3

"""Codex UserPromptSubmit hook: injects the current local time as
additionalContext. Direct python3 command (no shell hop) matches squire's own
SessionStart hook convention (see pkg/agent/codex/hooks/session_start_map.py
in the squire repo)."""

import json
from datetime import datetime


def main() -> int:
    now = datetime.now().astimezone().strftime("%A %Y-%m-%d %H:%M:%S %Z")
    output = {
        "hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": f"Current local time: {now}",
        }
    }
    print(json.dumps(output))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
