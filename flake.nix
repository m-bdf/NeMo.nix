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

  outputs = { self, systems, nixpkgs, nix2container, sources }: {

    packages = with nixpkgs.lib;
      genAttrs (import systems) (system: rec {

        lib = import ./. (
          nixpkgs.legacyPackages.${system} //
          nix2container.packages.${system}
        );

        images = mapAttrs lib.pullNeMoImage (importJSON sources).images;
        models = mapAttrs lib.pullNeMoModel (importJSON sources).models;
      });

    overlays.default = final: prev: {
      nemo = self.packages.${final.stdenv.system};
    };

    nixosModules.default = {
      imports = [ ./options.nix ./config.nix ];
      nixpkgs.overlays = [ self.overlays.default ];
    };
  };
}
