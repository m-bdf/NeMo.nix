{
  inputs = {
    systems.url = "github:nix-systems/default";

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nix2container = {
      url = "github:nlewo/nix2container";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nemoImages = {
      type = "file";
      url = "https://catalog.ngc.nvidia.com/api/containers/images?orgName=nvidia&name=nemo&isPublic=true";
      flake = false;
    };
  };

  outputs = { self, systems, nixpkgs, nix2container, nemoImages }: {

    packages = with nixpkgs.lib;
      genAttrs (import systems) (system: rec {

        lib = import ./. (
          nixpkgs.legacyPackages.${system} //
          nix2container.packages.${system}
        );

        images = listToAttrs (map (image:
          nameValuePair image.tag (lib.pullNeMoImage image)
        ) (importJSON nemoImages).images);

        models = mapAttrs lib.pullNeMoModel {
          canary-1b = "sha256-sChBg6mh4Dmi//OUJ+KZH6TfC5YSo0R/wz/4KyD9+1o=";
          canary-1b-flash = "sha256-OIfM4a/dQlQpz8UQlXWo8s/+sHwCxQOp+v92Er104yQ=";
          canary-180m-flash = "sha256-e5feGLcY7wG/M5hxXOjRhIbE2Dlh4jAjCyb1cS4RJnU=";
        };
      });

    overlays.default = final: prev: {
      nemo = self.packages.${final.stdenv.system};
    };

    nixosModules = {
      default = {
        imports = [ ./options.nix ./config.nix ];
        nixpkgs.overlays = [ self.overlays.default ];
      };

      asr = { lib, pkgs, ... }: {
        imports = [ self.nixosModules.default ];

        services.nemo = lib.mkDefault {
          enable = true;
          image = pkgs.nemo.images."25.04";
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
