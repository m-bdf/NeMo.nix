# NeMo.nix

This is a Nix flake easing the use of NVIDIA's NeMo framework on NixOS.

Run a custom Python script as a background service,
using any NeMo model, on any NeMo version (in theory),
with the optional container runtime of your choice (Podman or systemd-nspawn).

It also exposes all official NeMo images and models currently available,
[whose hashes](https://m-bdf.github.io/NeMo.nix/sources.json)
are updated every day by a GitHub action.

## Usage

Import the provided module in your NixOS configuration:

``` nix
# flake.nix

{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nemo = {
      url = "github:m-bdf/NeMo.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nemo }: {
    nixosConfigurations.default =
      nixpkgs.lib.nixosSystem {
        modules = [
          nemo.nixosModules.default
          ./configuration.nix
          # other modules
        ];
      };
  };
}
```

Then set the `services.nemo.enable` option to `true`,
and specify a NeMo image, an optional NeMo model,
and a Python script to run as a background service.

## Example

Here is an example for automatic speech recognition:

``` nix
# configuration.nix

{ pkgs, ... }:

let
  script = ''
    from watchfiles import watch, Change
    print("Watching for changes in /usr/share/asr...")

    for changes in watch("asr", recursive=False):
      for (change, path) in changes:
        if change is Change.added and path.endswith(".wav"):
          transcript = model.transcribe(path)[0]
          print(transcript.text)
  '';
in

{
  services.nemo = {
    enable = true;
    image = pkgs.nemo.images.dev;
    model = pkgs.nemo.models.canary-1b-flash;

    mounts.asr = "/usr/share/asr";
    libs = ps: with ps; [ watchfiles ];
    inherit script;
  };
}
```

Activate this configuration (`nixos-rebuild switch`),
add a .wav file to the /usr/share/asr directory,
and you should see its transcription appear automagically
in the output of the `nemo` systemd service (`journalctl -fu nemo.service`).
