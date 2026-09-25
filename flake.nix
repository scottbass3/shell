{
  description = "Material You desktop shell for Hyprland, built on Quickshell";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # nixpkgs-style unstable version from the commit date: 0-unstable-YYYY-MM-DD
      date = self.lastModifiedDate or "19700101";
      version = "0-unstable-${builtins.substring 0 4 date}-${builtins.substring 4 2 date}-${builtins.substring 6 2 date}";

      mkPackage =
        pkgs:
        pkgs.callPackage ./nix/package.nix {
          src = self;
          inherit version;
        };
    in
    {
      packages = forAllSystems (pkgs: rec {
        scottbass3-shell = mkPackage pkgs;
        default = scottbass3-shell;
      });

      overlays.default = final: _prev: { scottbass3-shell = mkPackage final; };

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
