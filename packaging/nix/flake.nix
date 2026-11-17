# The Libre Computer UCM profiles as a Nix flake (infra multi-distro plan, NixOS row of the UCM): the overlay
# (build-overlay.sh's file set: our profiles, nothing upstream ships) as the package alsa-ucm-conf-libre-computer,
# and a NixOS module that points ALSA at nixpkgs' alsa-ucm-conf with our profiles added. Cut per release by
# `build-overlay.sh --format nix`, which puts the staged files at ./root and the version in ./version.nix; this
# directory alone is not a flake. nixpkgs is the newest NixOS stable channel, pinned by flake.lock (the same pin as
# the kernel, Mesa and gaema-desktop flakes), so a host following it takes the outputs from packages.libre.computer's
# Nix cache.
{
  description = "ALSA Use Case Manager profiles for Libre Computer boards";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      version = import ./version.nix;
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      ucm = pkgs: pkgs.callPackage ./package.nix { src = ./root; inherit version; };
    in
    {
      packages = forAll (pkgs: rec {
        alsa-ucm-conf-libre-computer = ucm pkgs;
        # nixpkgs' alsa-ucm-conf with our profiles copied over it: what the module points ALSA at
        alsa-ucm-conf-with-libre-computer = alsa-ucm-conf-libre-computer.tree;
        default = alsa-ucm-conf-libre-computer;
      });
      overlays.default = final: _prev: { alsa-ucm-conf-libre-computer = ucm final; };
      nixosModules.default = import ./module.nix self;
    };
}
