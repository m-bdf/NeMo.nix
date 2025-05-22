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

    nixosModules = {
      default = {
        imports = [ ./options.nix ./config.nix ];
        nixpkgs.overlays = [ self.overlays.default ];
      };

      asr = { lib, pkgs, ... }: {
        imports = [ self.nixosModules.default ];

        services.nemo = lib.mkDefault {
          enable = true;
          image = pkgs.nemo.images."25.07";
          model = pkgs.nemo.models.canary-1b-flash;

          mounts.asr = "/usr/share/asr";
          libs = ps: with ps; [ watchfiles ];
          script = ''
            print("Watching for changes in /usr/share/asr...")
            from watchfiles import watch, Change
            for changes in watch("asr", recursive=False):
              for (change, path) in changes:
                if change is Change.added and path.endswith(".wav"):
                  transcript = model.transcribe(path)[0]
                  print(transcript.text)
          '';
        };
      };
    };
  };
}
