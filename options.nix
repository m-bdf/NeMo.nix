{ config, lib, ... }:

with lib;
with types;

let
  refOrPath =
    either (strMatching "[[:graph:]]+")
      pathInStore // {
        merge = loc: defs: rec {
          outPath = mergeEqualOption log defs;
          isRef = !pathInStore.check outPath;
        };
      };

  cfg = config.services.nemo;
in

{
  options.services.nemo = {
    enable = mkEnableOption
      "running an Nvidia NeMo container as a background service";

    image = mkOption {
      type = refOrPath;
      description = ''
        Image to run the container from. This can be a string
        (full Docker reference to the image to be pulled at run-time)
        or a path in the Nix store (the image archive file itself).
      '';
    };

    preload = mkOption {
      type = nullOr (enum [ "store" "rootfs" ]);
      default = if cfg.image.isRef then null else "rootfs";
      description = ''
        Strategy for loading the image at build time:
        - `null`: do not pre-load the image, only load it at runtime
          (only with Podman, mandatory if the image is a string ref)
        - "store": build and register an additional image store
          (only with Podman, requires the "uid-range" system feature)
        - "rootfs": extract the full root directory of the image
      '';
    };

    runtime = mkOption {
      type = nullOr (enum [ "nspawn" "podman" ]);
      default = if cfg.preload != "rootfs" then "podman" else null;
      description = ''
        Container runtime to use:
        - `null`: directly run the script in a systemd service isolated
          from the the host machine using the `confinement` NixOS module
        - "nspawn": run the script in a systemd-nspawn container
        - "podman": run the script in a Podman container (only runtime
          supporting image pre-loading strategies different than "rootfs")
      '';
    };

    model = mkOption {
      type = nullOr refOrPath;
      default = null;
      description = ''
        NeMo model to load as the `model` variable in the script.
        This can be a string (full name of the model to be downloaded
        at run-time) or a path in the Nix store (.nemo checkpoint file).
      '';
    };

    mounts = mkOption {
      type = attrsOf path;
      default = {};
      description = ''
        Target-source pairs of host paths to bind-mount into the container.
        The target is given relative to the runtime directory of the script.
      '';
    };

    libs = mkOption {
      type = functionTo (listOf package);
      default = ps: [];
      description = ''
        Function which given a Python 3 package set returns extra libraries
        needed by the script that will be added to its PYTHONPATH.
      '';
    };

    script = mkOption {
      type = lines;
      default = "";
      description = ''
        Python 3 code to run in the container. If not `null`, the selected
        NeMo model is pre-loaded and made accessible as the `model` variable.
      '';
    };
  };

  config.assertions = [
    {
      assertion = cfg.image.isRef -> cfg.preload == null;
      message = ''
        Pre-loading Docker images is only supported from archive files,
        not Docker references.
      '';
    }
    {
      assertion = cfg.preload != "rootfs" -> cfg.runtime == "podman";
      message = ''
        Only the Podman runtime supports image pre-loading strategies
        different than "rootfs".
      '';
    }
  ];
}
