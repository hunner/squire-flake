{
  description = "Personal home-manager environment for squire task envs: go/rust toolchains, and UserPromptSubmit-equivalent hooks (current local time) for Claude Code, Codex, and oh-my-pi.";

  inputs = {
    # home-manager's `master` against a same-era nixpkgs failed eval (a
    # `services-modular` module reached for a nixpkgs lib file that didn't
    # exist yet), so this pins the matched, well-tested release pair instead.
    # squire's own preinstalled `home-manager` binary is irrelevant here — it's
    # just a dispatcher that builds and runs *this flake's own*
    # `homeConfigurations.<target>.activationPackage`.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager }:
    let
      # Squire task envs (Dockerfile.squire) build linux/arm64 only.
      system = "aarch64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      homeConfigurations.squire = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ ./home.nix ];
      };
    };
}
