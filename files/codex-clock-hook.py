#!/usr/bin/env python3

"""Codex UserPromptSubmit hook: injects the current time in Pacific
(America/Los_Angeles) as additionalContext, regardless of the container's
system timezone."""

import json
from datetime import datetime
from zoneinfo import ZoneInfo


def main() -> int:
    now = datetime.now(ZoneInfo("America/Los_Angeles")).strftime("%A %Y-%m-%d %H:%M:%S %Z")
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
