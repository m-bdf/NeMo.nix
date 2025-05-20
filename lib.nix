{
  cacert,
  go,
  lib,
  nemo,
  nix2container,
  python3Packages,
  requireFile,
  runCommand,
  skopeo-nix2container,
  undocker,
}:

let
  skopeo = lib.getExe skopeo-nix2container +
    " --insecure-policy --tmpdir=/tmp --debug";
in

{
  pullImageFromDigest = digest: args:
  let
    ref = "${args.registryUrl or "docker.io"}/" +
      "${args.imageName}:${args.imageTag or "latest"}";

    manifest =
      runCommand "${ref}-manifest.json" {
        outputHash = digest;
      } ''
        ${lib.getExe nixImage.getManifest} > $out
      '';

    nixImage = nix2container.pullImageFromManifest
      (args // { imageManifest = manifest; });
  in
    runCommand "docker-image-${ref}.tar" {
      nixImage = nemo.lib.decompressNixImage nixImage;
      passthru = args // { inherit manifest; };
    } ''
      ${skopeo} copy nix:$nixImage docker-archive:$out:${ref}
    '';


  decompressNixImage = image:
  let
    getRawDigest = lib.removePrefix "sha256:";

    decompressLayer = layer: digest:
      runCommand (getRawDigest digest) {
        compressed = requireFile {
          url = getRawDigest layer;
          hash = layer;
        };
        outputHash = digest;
      } ''
        zcat $compressed > $out
      '';

    decompressedLayers = with builtins;
      map (layer: decompressLayer layer.digest layer.diff_ids)
        (fromJSON (unsafeDiscardStringContext (readFile image))).layers;
  in
    runCommand "decompressed-nix-image" {
      compressedNixImage = image;
    } ''
      sed '${lib.concatMapStrings (layer: ''
        s|${layer.compressed}|${layer}|
        s|${layer.compressed.name}|${layer.name}|
      '') decompressedLayers}' $compressedNixImage > $out
    '';


  buildImageStore = image:
    runCommand "image-store" {
      inherit image;
      requiredSystemFeatures = [ "uid-range" ];
      outputs = [ "out" "imageId" ];
    } ''
      id=($(tar -xf $image manifest.json -O | sha256sum | tee $imageId))
      ${skopeo} copy docker-archive:$image containers-storage:[$out+/tmp]@$id
      find $out -type c -delete -printf 'Deleted overlay whiteout %p\n'
    '';

  extractRootfs = image:
    runCommand "rootfs" {
      inherit image;
    } ''
      mkdir -p $out${builtins.storeDir}
      ${lib.getExe undocker} $image - | tar -xvC $out || true
    '';


  pullNeMoImage = image:
  let
    variant = lib.findFirst
      (v: v.architecture == go.GOARCH)
      (throw "Architecture not supported")
      image.architectureVariants;
  in
    nemo.lib.pullImageFromDigest variant.digest {
      registryUrl = "nvcr.io";
      imageName = "nvidia/nemo";
      imageTag = image.tag;
    };

  pullNeMoModel = name: hash:
    runCommand "${name}.nemo" {
      nativeBuildInputs = [ cacert python3Packages.hf-xet ];
      HF_XET_HIGH_PERFORMANCE = true;
      outputHash = hash;
    } ''
      mv $(readlink -e $(HF_HOME=/tmp ${
        lib.getExe python3Packages.huggingface-hub
      } download nvidia/${name} ${name}.nemo)) $out
    '';
}
