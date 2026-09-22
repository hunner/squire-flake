---
name: squire-task
description: Run one unit of work in a squire environment from an orchestrating Claude Code session. Use when a task needs its own machine, a fresh repo clone, or a long unattended run. Covers launch, liveness, reading output, waiting, cleanup, and the brief. Never hand these steps to a subagent.
---

# squire-task

Two audiences. Sections 1 to 5 are for the orchestrating session. Section 6 is the brief for the agent inside the task. Paste section 6 into every prompt.

## 0. Rules for the orchestrating session

- Do every step here yourself. Do not delegate launch or watching to a subagent. Seven subagents tried. Six ended their turn when they handed off the wait. One spent 90 minutes on a side question. The work in squire survived every time. Only the watcher died.
- Launch is a script. It needs no judgment. Run it. Record the ids. Move on.
- Watching is a background bash loop in this session. Never a foreground `sleep`. Never a subagent.
- If a tool is missing, run `nix-shell -p <tool>`. Never report a step as impossible for want of a tool.

## 1. Launch

New env and first task in one call. It returns at once:

    squire new <name> --image <img> --harness <h> -m <model> --no-attach -p "$(cat brief.md)"

Add a task to a running env:

    squire task create --env <env> --harness <h> --model <m> --title <t> --prompt-file brief.md

- The harness follows the model provider. Anthropic: `claude`. OpenAI: `codex`. All others: `opencode`.
- Never use `xai` models. The fleet has no credentials for them.
- Repo work: `--image default --clone <repo-url>`. Use `--image c1` only when the task needs the full c1 stack. It is slow.
- Expect several minutes before the first token. This is normal.

Write `<env>` and `<task>` to your notes before you do anything else.

## 2. Confirm the agent is alive

Task status cannot tell you this. `status: running` with `activity: idle` looks the same for a thinking agent and a dead one. Check cheapest first, no ssh:

    squire api /api/v1/environments/<env>/tasks/<task>/stream | jq '[.[]|select(.info.role=="assistant" and (.parts|length>0))] | length'

Alive if nonzero and growing. (Its `info` object is only `{id, role, taskID, time}` — no `tokens` field.) Zero past the startup grace period, or a definitive dead-or-done answer needed: ask the in-env opencode session instead.

    port=$(squire ssh <env> --no-select -- -T 'ps -eo cmd | grep -oE "opencode serve --port [0-9]+" | grep -oE "[0-9]+$"')
    session=$(squire task get --env <env> --task <task> | jq -r '.active_session' | sed 's/^[a-z]*:session://')
    squire ssh <env> --no-select -- -T "curl -s --max-time 20 http://127.0.0.1:$port/session/$session/message" \
      | jq '[.[]|select(.info.role=="assistant")] | .[-1].info | {out: .tokens.output, err: .error.name, done: (.time|has("completed"))}'

- Alive: `out` climbs between reads. Dead: `err` non-empty, or `out` flat 10 min past startup. Done: `done` is true. The `active_session` prefix (`opencode:session:`/`claude:session:`) is what the sed above strips.
- This API can hang for minutes during opencode's MCP bootstrap (observed today) — curl it with a timeout. A hung API is not proof of a dead agent.

## 3. Read output

Primary: the stream endpoint above. `squire task output` wraps the same endpoint. It has two known defects:
1. Any single entry over 8 KiB is cut mid-sentence. The HTTP status is still 200.
2. Some tasks never send assistant content to the gateway. You see only the user prompt.

Fallback for either defect. Ask the harness directly over ssh. The port is dynamic, so find it first:

    squire ssh <env> --no-select -- -T 'ps -eo cmd | grep "opencode serve"'
    squire ssh <env> --no-select -- -T 'curl -s http://127.0.0.1:<port>/session/<id>/message'

Extract the text parts from the JSON.

Most reliable: the agent writes its deliverable to the arena filesystem. It outlives the env and has neither defect:

    squire fs read --arena arena_2be018dd-ec7 /shared/<slug>/result.md

Require this for any output longer than one screen. Section 6 asks for it.

## 4. Wait

Run a background loop in this session with `run_in_background`. Poll every 20 to 30 seconds. Print only on state change. Exit on a terminal state or the cap. The session is re-invoked when the loop exits.

    last=; for i in $(seq 1 120); do
      st=$(squire task get --env <env> --task <task> | jq -r '.status')
      parts=$(squire api /api/v1/environments/<env>/tasks/<task>/stream | jq '[.[]|select(.info.role=="assistant" and (.parts|length>0))] | length')
      s="$st parts=$parts"
      [ "$s" != "$last" ] && echo "$(date +%T) $s" && last=$s
      case "$st" in completed|failed|error|stopped) break;; esac
      sleep 30
    done

If `parts` stays 0 past the startup grace period, or the cap is close, run the section 2 in-env-session check by hand before deciding. `squire wait` is right for a one-shot "tell me when this ends", but it fires on lifecycle events only — a dead agent emits none — so pair it with the liveness check, or use this loop.

## 5. Cleanup

- `squire env stop <env>` frees the concurrent-env quota. `squire env delete <env> --yes` removes it.
- Envs idle out on their own and can lose scratch data. Pull out anything you want first, or confirm it landed in `/shared/`.
- Commits from envs are unsigned. This is accepted. The target repos squash-merge.

## 6. The brief (for the agent inside the task)

One goal per brief. An agent with two goals does the interesting one and skips the required one. Define done as the completion of the one goal. Template:

    Goal: <one sentence. One verb.>
    Done means: <one observable artifact. A pushed branch. A file at /shared/<slug>/result.md. A green test run.>
    Write your final report to /shared/<slug>/result.md before you stop. Keep it under 6 KiB.
    Do not investigate side questions. If you find one, note it in the report and continue with the goal.
    If a tool is missing, run `nix-shell -p <tool>`. Do not stop for want of a tool.
    Stop when done is true. Make "DONE" your last line.
