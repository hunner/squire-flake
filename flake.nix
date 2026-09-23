{
  description = "UserPromptSubmit-equivalent hooks (current local time) for Claude Code, Codex, and oh-my-pi, delivered as a Squire nix-flake personalization.";

  inputs = {
    # `squire`'s preinstalled `home-manager` binary (Dockerfile.base) is just
    # nixpkgs's vendored copy of the CLI — it's a dispatcher: `home-manager
    # switch --flake ref#target` builds and runs *this flake's own*
    # `homeConfigurations.<target>.activationPackage`, evaluated with
    # *this flake's own* home-manager + nixpkgs inputs. So the only
    # constraint here is that home-manager and nixpkgs are from a mutually
    # compatible era — nothing to do with whatever commit squire's image
    # happens to vendor. Tracking home-manager's `master` against a nixpkgs
    # commit from the same rough era failed eval (a `services-modular`
    # module reaching for a `lib/services/lib.nix` nixpkgs added later), so
    # this uses the matched, well-tested stable pair instead.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager }:
    let
      # Squire task envs run Dockerfile.squire, built linux/arm64 only
      # (docker-bake.hcl: "squire-env" target, pinned because the RecordStore
      # runtime publishes arm64 only). If that ever changes, add a second
      # homeConfigurations entry for x86_64-linux and pick it via
      # `squire nix set --flake ... --target`.
      system = "aarch64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      homeConfigurations.agent-hooks = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ ./home.nix ];
      };
    };
}
