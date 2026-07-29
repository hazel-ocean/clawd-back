{
  description = "macOS notifier that returns you to the Zellij pane Claude Code is waiting in";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { self, nixpkgs, flake-utils }:
    # macOS-only (uses UNUserNotificationCenter + AppKit).
    flake-utils.lib.eachSystem [ "aarch64-darwin" "x86_64-darwin" ] (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        app = pkgs.callPackage ./default.nix { };
      in
      {
        packages.default = app;
        packages.claude-zellij-whip = app;
      }
    );
}
