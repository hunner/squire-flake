# orc: a Fable orchestrator env

An env whose display name is `orc` or starts with `orc-` gets, on top of
the usual flake setup:

- `~/.claude/rules/orc-CLAUDE.md`: a copy of the laptop's
  `~/.claude/CLAUDE.md` (`files/orc-CLAUDE.md`). It goes in `rules/`
  because squire rewrites `~/.claude/CLAUDE.md` on every config apply.
  Claude Code loads user-level rules the same way. Other envs have the file
  removed, because "delegate everything" is wrong for a worker.

Every env (not only orc) also gets the PreToolUse hook that denies `Agent`
calls without a `model` (`files/require-agent-model.sh`, wired into
`~/.claude/settings.json`). This matches the laptop.

## One-time setup (Hunter)

1. Point squire at the flake over HTTPS. The current setting is
   `git+ssh://...`, which only works after squire writes the
   `insteadOf` rewrite in `~/.gitconfig`. The boot-time `home-manager switch`
   runs before that, so it fails (see `/data/squire/logs/envmgr.log`). The
   existing `orc` env never got the flake.

       squire nix set --flake "git+https://github.com/hunner/squire-flake.git" \
         --target homeConfigurations.squire

   To try a branch before merging it, add `?ref=orc-env` to the URL.

2. Authenticate `c1internal` in the Squire web UI (user settings, MCP
   servers). It points at the same URL as the claude.ai connector
   "C1 Internal - New" (`https://c1internal-mcp.conductor.one/v1`). Squire
   holds the token and delivers it to every env. Envs show "Needs
   authentication" until you do this. Through code mode it reaches Gmail,
   Calendar, Drive/Docs/Sheets/Slides, Linear, Notion, Datadog, Buildkite,
   and more.

3. Optional, and these apply to every env you own: add other remote
   servers through squire, then authenticate each one in the web UI:

       squire mcp add c1docs https://www.c1.ai/docs/mcp          # no auth
       squire mcp add clickhouse-cloud https://mcp.clickhouse.cloud/mcp
       squire mcp add c1-skill-catalog https://skill-search-mcp.prod.secsvcs.c1rew.com/mcp

   I haven't checked whether the OAuth servers accept squire's dynamic
   client registration.

## What the env cannot have

The env's Claude Code signs in with squire's setup token
(`CLAUDE_CODE_OAUTH_TOKEN`, `claude auth status` -> `oauth_token`). A setup
token doesn't load claude.ai account connectors: Slack, Claude Docs,
Claude Data, Meetings, claude_security, and the claude.ai-hosted Google
connectors. Running `claude auth login` inside the env doesn't help, because
squire sets the token variable in the harness environment, and the variable
wins. Use `c1internal` for Google, Linear, Notion, and the rest. Slack has no
path today.

## Managing other envs from inside orc

Envs have no `squire` CLI. A Claude task in the env gets the `squire` MCP
server, which provides `create_env`, `list_envs`, `get_env`,
`squire.task.create`, `squire.task.resume`, `prompt_task`, `wait_events`,
`squire.message.*`, and `squire.fs.*`. From a shell, use the same tools
through `squire-tool list` or `squire-tool call <tool> '<json>'`. Pass
`--task-id` to reach the task-scoped tools.

## Launch

    squire new orc --no-attach --image default -f medium \
      --harness claude -m anthropic/claude-fable-5-2 -p "$(cat brief.md)"

Or, in an existing `orc` env:

    squire task create --env orc --harness claude \
      --model anthropic/claude-fable-5-2 --title orchestrator --prompt-file brief.md

The flake applies at boot, before the first task starts. An env that was
already running needs `squire env stop` and `start` (or a manual
`home-manager switch`) to pick up flake changes.
