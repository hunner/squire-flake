{ config, lib, pkgs, ... }:

let
  # Bare `date` — Claude Code accepts plain stdout as additionalContext for
  # UserPromptSubmit, no JSON wrapping needed. TZ forces Pacific regardless
  # of the container's system timezone.
  clockCmd = "TZ='America/Los_Angeles' date '+Current local time: %A %Y-%m-%d %H:%M:%S %Z'";

  # writeText, not a heredoc: an indented heredoc body inside a Nix ''...''
  # string inherits the block's indentation, which breaks whitespace-sensitive
  # Python.
  codexHookScript = pkgs.writeText "codex-clock-hook.py" (builtins.readFile ./files/codex-clock-hook.py);

  codexConfigToml = pkgs.writeText "codex-system-config.toml" ''
    [[hooks.UserPromptSubmit]]
    [[hooks.UserPromptSubmit.hooks]]
    type = "command"
    command = "python3 /etc/codex/hooks/clock.py"
    timeout = 5
  '';

  # Laptop parity: deny Agent calls with no explicit model. Store path, so the
  # hook does not depend on jq being on the harness's PATH.
  requireAgentModel = pkgs.writeShellScript "require-agent-model"
    ("PATH=${pkgs.jq}/bin:$PATH\n" + builtins.readFile ./files/require-agent-model.sh);
in
{
  home.username = "squire";
  home.homeDirectory = "/home/squire";
  home.stateVersion = "26.05";

  home.packages = with pkgs; [
    go
    rustc
    cargo
  ];

  # oh-my-pi auto-discovers *.ts hooks under ~/.omp/agent/hooks/pre/; squire
  # only manages ~/.omp/agent/config.yml, so this path is safe to own
  # declaratively.
  home.file.".omp/agent/hooks/pre/clock.ts".source = ./files/omp-clock-hook.ts;

  # squire doesn't manage ~/.claude/hooks, so the script can live there
  # declaratively; only its settings.json wiring is merged imperatively below.
  home.file.".claude/hooks/require-agent-model.sh".source = requireAgentModel;

  # Claude Code (~/.claude/settings.json) and Codex (~/.codex/config.toml,
  # hooks.json) are both rewritten by squire's own agent-config apply, which
  # runs before this activation on every env start — so a declarative
  # home.file for either would collide. Handled imperatively instead:
  #
  # - Claude: squire's writer round-trips `hooks` and only strips its own
  #   known command signatures, so merging our entry in is safe long-term.
  # - Codex: squire's writer rewrites config.toml/hooks.json from scratch
  #   every apply (no round-trip), so anything added at the user layer would
  #   eventually get clobbered. Codex's *System* layer (/etc/codex/config.toml)
  #   is never touched by squire and is auto-trusted (System -> is_managed ->
  #   HookTrustStatus::Managed), skipping the trusted_hash dance entirely.
  home.activation.agentPromptSubmitHooks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    claude_settings="$HOME/.claude/settings.json"
    mkdir -p "$(dirname "$claude_settings")"
    [ -f "$claude_settings" ] || echo '{}' > "$claude_settings"

    # Marker-based strip-then-add (not exact-string match): a past version of
    # this flake could have written a different clockCmd (e.g. before the TZ
    # fix), and exact matching would leave that stale entry behind as a
    # duplicate instead of replacing it.
    claude_tmp="$(mktemp)"
    ${pkgs.jq}/bin/jq \
      --arg cmd ${lib.escapeShellArg clockCmd} \
      --arg marker "Current local time" \
      --arg agentHook "$HOME/.claude/hooks/require-agent-model.sh" \
      '.hooks = (.hooks // {})
       | .hooks.UserPromptSubmit = (
           ((.hooks.UserPromptSubmit // [])
             | map(select(([.hooks[]?.command // ""] | any(contains($marker))) | not)))
           + [{"hooks": [{"type": "command", "command": $cmd, "timeout": 5}]}]
         )
       | .hooks.PreToolUse = (
           ((.hooks.PreToolUse // [])
             | map(select(([.hooks[]?.command // ""] | any(contains("require-agent-model"))) | not)))
           + [{"matcher": "Agent", "hooks": [{"type": "command", "command": $agentHook, "timeout": 10}]}]
         )' \
      "$claude_settings" > "$claude_tmp"
    mv "$claude_tmp" "$claude_settings"

    # Absolute path: home-manager activation runs with a nix-store-only PATH,
    # so plain `sudo` isn't found even though it exists on the system.
    /usr/bin/sudo mkdir -p /etc/codex/hooks
    /usr/bin/sudo install -m 0755 ${codexHookScript} /etc/codex/hooks/clock.py
    /usr/bin/sudo install -m 0644 ${codexConfigToml} /etc/codex/config.toml
  '';

  # Hunter's user-level CLAUDE.md, for orchestrator envs only (display name
  # `orc` or `orc-*`). It tells the session to delegate everything, which is
  # wrong for worker envs, so every other env gets it removed.
  #
  # squire rewrites ~/.claude/CLAUDE.md on every config apply, so this goes in
  # ~/.claude/rules/, which Claude Code also loads at user scope and squire
  # leaves alone. The env name comes from the gateway API; the token and env
  # id live in squire-agent.env (envmgr's own environment lacks them). If the
  # lookup fails, the file is left as it was.
  home.activation.orcInstructions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    orc_rules="$HOME/.claude/rules/orc-CLAUDE.md"
    agent_env="$HOME/.config/squire/squire-agent.env"
    env_name="$(
      . "$agent_env" >/dev/null 2>&1
      ${pkgs.curl}/bin/curl -fsS -m 10 \
        -H "Authorization: Bearer ''${SQUIRE_SESSION_TOKEN:-}" \
        "''${SQUIRE_BASE_URL:-}/api/v1/environments/''${SQUIRE_ENV_ID:-}" \
        | ${pkgs.jq}/bin/jq -r '.name // empty'
    )" || env_name=""
    case "$env_name" in
      orc|orc-*) install -D -m 0644 ${./files/orc-CLAUDE.md} "$orc_rules" ;;
      "") echo "orcInstructions: env name unknown, leaving $orc_rules as is" ;;
      *) rm -f "$orc_rules" ;;
    esac
  '';
}
