{ config, lib, pkgs, ... }:

let
  cfg = config.services.nemo;

  imageStore = pkgs.nemo.lib.buildImageStore cfg.image;
  imageRootfs = pkgs.nemo.lib.extractRootfs cfg.image;

  binds = lib.mapAttrsToList (n: p: "${p}:/root/${n}") cfg.mounts;

  script = pkgs.writeScript "nemo.py" ''
    #!/bin/python3 -u

    ${lib.optionalString (cfg.model != null) ''
      print("Loading model ${cfg.model}...")
      from nemo.core import ModelPT
      model = ModelPT.${
        if cfg.model.isRef then "from_pretrained" else "restore_from"
      }("${cfg.model}")
    ''}

    ${cfg.script}
  '';

  wrapper = pkgs.writeShellScript "nemo.sh" ''
    PYTHONPATH=${
      with pkgs.python312Packages; makePythonPath
        ([ hf-xet numpy_1 torch torchvision ] ++ cfg.libs python.pkgs)
    } exec ${script}
  '';
in

lib.mkIf cfg.enable (lib.mkMerge [

  (lib.mkIf (cfg.runtime == null) {
    systemd.services.nemo = {
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      confinement = {
        enable = true;
        binSh = null;
      };

      serviceConfig = {
        RootDirectory = lib.mkForce imageRootfs;
        BindReadOnlyPaths = "/etc/resolv.conf";

        TemporaryFileSystem = [ builtins.storeDir "/root" ];
        BindPaths = binds;

        WorkingDirectory = "/root";
        ExecStart = wrapper;
        KillSignal = "INT";
      };
    };
  })

  (lib.mkIf (cfg.runtime == "nspawn") {
    systemd = {
      services."systemd-nspawn@nemo" = {
        overrideStrategy = "asDropin";
        wantedBy = [ "machines.target" ];

        serviceConfig = {
          BindPaths = "${imageRootfs}:/var/lib/machines/%i";
          Environment = "SYSTEMD_NSPAWN_TMPFS_TMP=0";
        };
      };

      nspawn.nemo = {
        networkConfig.Private = false;

        filesConfig = {
          Bind = [ builtins.storeDir ] ++ binds;
          TemporaryFileSystem = "/root";
        };

        execConfig = {
          WorkingDirectory = "/root";
          ProcessTwo = true;
          Parameters = wrapper;
          KillSignal = "INT";
        };
      };
    };
  })

  (lib.mkIf (cfg.runtime == "podman") {
    virtualisation = {
      containers.storage.settings.storage.options.additionalimagestores =
        lib.mkIf (cfg.preload == "store") [ imageStore ];

      oci-containers.containers.nemo = {
        pull = if cfg.image.isRef then "newer" else "never";
        image = if cfg.image.isRef then "${cfg.image}" else {
          none = "docker-archive:${cfg.image}";
          store = "$(<${imageStore.imageId})";
          rootfs = "--rootfs ${imageRootfs}:O";
        }.${lib.defaultTo "none" cfg.preload};

        volumes = [
          "${builtins.storeDir}:${builtins.storeDir}"
        ] ++ binds;

        workdir = "/root";
        entrypoint = "${wrapper}";
        extraOptions = [ "--stop-signal=INT" ];
      };
    };

    systemd.services.podman-nemo.serviceConfig.Restart = lib.mkForce "no";
  })
])
