# squire-flake

A nix flake for squire's `nix-flake` personalization mode
(`squire nix set --flake ... --target ...`). It installs a
`UserPromptSubmit`-equivalent hook — inject the current local time as context
on every prompt — for each harness squire supports:

| Harness    | Mechanism                                                        |
|------------|-------------------------------------------------------------------|
| Claude Code | Merged into `~/.claude/settings.json`'s `hooks.UserPromptSubmit`. |
| Codex      | Written to `/etc/codex/config.toml` (Codex's *System* config layer). |
| oh-my-pi   | Dropped at `~/.omp/agent/hooks/pre/clock.ts` (`before_agent_start`). |

See the comments in `home.nix` for why each harness needs a different
delivery mechanism — in short, squire's own agent-config apply rewrites
`~/.claude/settings.json` and `~/.codex/config.toml`/`hooks.json` on every env
boot (before this flake's home-manager activation runs), so anything home-manager
puts directly at those paths either collides (Claude, if done declaratively)
or gets clobbered on the next apply (Codex, if done at the user layer).
Claude's settings.json write preserves unrecognized `hooks` entries, so an
idempotent merge there is safe; Codex's isn't, so its hook lives in the
System config layer instead (`/etc/codex/config.toml`), which squire never
touches and which Codex auto-trusts without the usual hash-pinning dance.

## Usage

From inside a squire task, or before launching one:

```
squire nix set --flake github:hunner/squire-flake --target homeConfigurations.agent-hooks
```

Takes effect on the next environment start.

## Notes

- Targets `aarch64-linux` — squire's task image (`Dockerfile.squire`) is
  built `linux/arm64` only today. If that changes, add a second
  `homeConfigurations` entry for `x86_64-linux` in `flake.nix`.
- `nixpkgs`/`home-manager` are pinned to the current `nixos-26.05`/
  `release-26.05` pair, not to whatever commit squire's own image vendors —
  `home-manager switch --flake` just builds and runs this flake's own
  `homeConfigurations.<target>.activationPackage`, so only this flake's own
  inputs need to be mutually compatible.
- Writing `/etc/codex/config.toml` needs root; squire's `squire` user has
  passwordless sudo, so the home-manager activation script uses it directly.
