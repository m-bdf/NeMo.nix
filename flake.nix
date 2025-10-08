{
  inputs = {
    systems.url = "github:nix-systems/default";

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nix2container = {
      url = "github:nlewo/nix2container";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sources = {
      url = "https://m-bdf.github.io/NeMo.nix";
      flake = false;
    };
  };

  outputs = { self, systems, nixpkgs, nix2container, sources }:

  let
    pkgsWith = pkgs: with pkgs.lib; {
      nemo = pkgs.callPackage ./. {} // {
        lib = pkgs.callPackage ./lib.nix {};

        images = mapAttrs pkgs.nemo.pullNeMoImage (importJSON sources).images;
        models = mapAttrs pkgs.nemo.pullNeMoModel (importJSON sources).models;
      };
    };
  in

  {
    overlays.default = final: prev:
      import nix2container {
        pkgs = final;
      } // pkgsWith final;

    packages = nixpkgs.lib.genAttrs (import systems) (system:
      (import nixpkgs {
        inherit system;
        overlays = [ self.overlays.default ];
      }).nemo
    );

    nixosModules.default = {
      imports = [ ./options.nix ./config.nix ];
      nixpkgs.overlays = [ self.overlays.default ];
    };
  };
}
