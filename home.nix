{ config, lib, pkgs, ... }:

let
  # The command Claude Code / Codex run on every UserPromptSubmit. Bare
  # `date` invocation — Claude Code accepts plain stdout as additionalContext
  # for this event, no JSON wrapping required.
  clockCmd = "date '+Current local time: %A %Y-%m-%d %H:%M:%S %Z'";

  # store-path derivations rather than heredocs: a heredoc body written
  # inline in an indented `''...''` Nix string picks up whatever leading
  # whitespace the surrounding block needs for readability, which corrupts
  # both the TOML and (fatally, since it's whitespace-sensitive) the Python.
  codexHookScript = pkgs.writeText "codex-clock-hook.py" (builtins.readFile ./files/codex-clock-hook.py);

  codexConfigToml = pkgs.writeText "codex-system-config.toml" ''
    # Managed by squire-flake (home-manager). See home.nix for why this
    # lives in Codex's System config layer instead of ~/.codex/config.toml.
    [[hooks.UserPromptSubmit]]
    [[hooks.UserPromptSubmit.hooks]]
    type = "command"
    command = "python3 /etc/codex/hooks/clock.py"
    timeout = 5
  '';
in
{
  home.username = "squire";
  home.homeDirectory = "/home/squire";
  home.stateVersion = "26.05";

  # --- oh-my-pi -----------------------------------------------------------
  # oh-my-pi auto-discovers *.ts hook factories under
  # ~/.omp/agent/hooks/pre/. Squire only manages ~/.omp/agent/config.yml
  # (see docs/env-personalization-surface.md in squire), never this path, so
  # it's safe to own declaratively.
  home.file.".omp/agent/hooks/pre/clock.ts".source = ./files/omp-clock-hook.ts;

  # --- Claude Code + Codex --------------------------------------------------
  # Both ~/.claude/settings.json and ~/.codex/config.toml / hooks.json are
  # (re)written wholesale by squire's own agent-config apply, which runs
  # *before* this home-manager activation on every env start (see squire's
  # pkg/envmgr/nixsetup package doc comment: nixsetup runs "after agent
  # config is applied"). A declarative home.file for either path would
  # collide with squire's own file and fail activation, so both are handled
  # imperatively below instead.
  #
  # Claude Code: squire's writeClaudeSettings round-trips the `hooks` map and
  # only strips command signatures it recognizes as its own (its SessionStart
  # hook, icm's hooks — see stripSquireManagedSessionStart /
  # stripICMHookEntries in pkg/envmgr/agentconfig/claudecode_config.go).
  # A UserPromptSubmit entry with our own command is left untouched, so a
  # plain idempotent merge is safe and durable across squire's re-applies.
  #
  # Codex: squire's Configure() (pkg/agent/codex/harness.go) and
  # installHooks() (pkg/agent/codex/hooks.go) both rewrite
  # ~/.codex/config.toml and ~/.codex/hooks.json from scratch every apply —
  # no round-trip, so anything we add there would eventually get clobbered.
  # Instead we use Codex's *System* config layer at /etc/codex/config.toml,
  # a layer squire never touches. It's also auto-trusted: codex maps
  # `ConfigLayerSource::System` to `is_managed = true`, which maps straight
  # to `HookTrustStatus::Managed` (see codex-rs/hooks/src/engine/
  # discovery.rs: hook_metadata_for_config_layer_source /
  # hook_trust_status), skipping the trusted_hash dance squire uses for its
  # own SessionStart hook entirely. Writing to /etc requires root; squire
  # grants the `squire` user passwordless sudo (Dockerfile.base).
  home.activation.agentPromptSubmitHooks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    claude_settings="$HOME/.claude/settings.json"
    mkdir -p "$(dirname "$claude_settings")"
    [ -f "$claude_settings" ] || echo '{}' > "$claude_settings"

    claude_tmp="$(mktemp)"
    ${pkgs.jq}/bin/jq \
      --arg cmd ${lib.escapeShellArg clockCmd} \
      '.hooks = (.hooks // {})
       | .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) as $groups
           | if ($groups | any(.hooks[]?.command == $cmd)) then $groups
             else $groups + [{"hooks": [{"type": "command", "command": $cmd, "timeout": 5}]}]
             end)' \
      "$claude_settings" > "$claude_tmp"
    mv "$claude_tmp" "$claude_settings"

    sudo mkdir -p /etc/codex/hooks
    sudo install -m 0755 ${codexHookScript} /etc/codex/hooks/clock.py
    sudo install -m 0644 ${codexConfigToml} /etc/codex/config.toml
  '';
}
