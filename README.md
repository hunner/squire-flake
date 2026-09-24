# squire-flake

Personal home-manager environment for squire task envs
(`squire nix set --flake ... --target ...`):

- Go and Rust toolchains.
- A `UserPromptSubmit`-equivalent hook (inject the current local time as
  context) for each harness squire supports:

| Harness    | Mechanism                                                        |
|------------|-------------------------------------------------------------------|
| Claude Code | Merged into `~/.claude/settings.json`'s `hooks.UserPromptSubmit`. |
| Codex      | Written to `/etc/codex/config.toml` (Codex's *System* config layer). |
| oh-my-pi   | Dropped at `~/.omp/agent/hooks/pre/clock.ts` (`before_agent_start`). |

See `home.nix` for why each harness needs a different delivery mechanism —
in short, squire's own agent-config apply rewrites `~/.claude/settings.json`
and `~/.codex/config.toml`/`hooks.json` on every env boot, before this
flake's home-manager activation runs, so a plain declarative file at either
path would collide or eventually get clobbered.

## Usage

From inside a squire task, or before launching one:

```
squire nix set --flake "git+https://github.com/hunner/squire-flake.git" --target homeConfigurations.squire
```

Use `git+https://`, not `github:` — the latter resolves through the GitHub
REST API (`api.github.com/repos/.../commits/HEAD`), which task envs share an
egress IP against and routinely rate-limit or 403 on. `git+https://` is a
plain git-over-HTTPS clone with no API calls involved.

Takes effect on the next environment start.

## Notes

- Targets `aarch64-linux` — squire's task image (`Dockerfile.squire`) is
  built `linux/arm64` only today. If that changes, add a second
  `homeConfigurations` entry for `x86_64-linux`.
- `nixpkgs`/`home-manager` are pinned to `nixos-26.05`/`release-26.05`, not
  to whatever commit squire's own image vendors — `home-manager switch
  --flake` just builds and runs this flake's own
  `homeConfigurations.<target>.activationPackage`.
- Writing `/etc/codex/config.toml` needs root; squire's `squire` user has
  passwordless sudo.
