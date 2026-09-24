{ config, lib, pkgs, ... }:

let
  # Bare `date` — Claude Code accepts plain stdout as additionalContext for
  # UserPromptSubmit, no JSON wrapping needed.
  clockCmd = "date '+Current local time: %A %Y-%m-%d %H:%M:%S %Z'";

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

    # Absolute path: home-manager activation runs with a nix-store-only PATH,
    # so plain `sudo` isn't found even though it exists on the system.
    /usr/bin/sudo mkdir -p /etc/codex/hooks
    /usr/bin/sudo install -m 0755 ${codexHookScript} /etc/codex/hooks/clock.py
    /usr/bin/sudo install -m 0644 ${codexConfigToml} /etc/codex/config.toml
  '';
}
