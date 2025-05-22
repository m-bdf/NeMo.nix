{
  lib,
  nix2container,
  requireFile,
  runCommand,
  skopeo-nix2container,
  undocker,
  writeShellApplication,
  jq,
  go,
  writers,
  python3Packages,
  cacert,
  ...
}:

let
  skopeo = lib.getExe skopeo-nix2container +
    " --insecure-policy --tmpdir=/tmp --debug";
in

rec {

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
      nixImage = decompressNixImage nixImage;
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
      ${skopeo} copy docker-archive:$image containers-storage:[$out]@$id
      find $out -type c -delete -printf 'Deleted overlay whiteout %p\n'
    '';

  extractRootfs = image:
    runCommand "rootfs" {
      inherit image;
    } ''
      mkdir -p $out${builtins.storeDir}
      ${lib.getExe undocker} $image - | tar -xvC $out
    '';


  fetchImageDigests =
    writeShellApplication {
      name = "fetch-image-digests";
      text = ''
        curl -G https://catalog.ngc.nvidia.com/api/containers/images \
          -d orgName=nvidia -d name=nemo -d isPublic=true -sSf |

        ${lib.getExe jq} '.images | map({
          (.tag): .architectureVariants | map({
            (.architecture): .digest
          }) | add
        }) | add'
      '';
    };

  pullNeMoImage = tag: digests:
    pullImageFromDigest digests.${go.GOARCH} {
      registryUrl = "nvcr.io";
      imageName = "nvidia/nemo";
      imageTag = tag;
    };


  fetchModelHashes =
    writers.writePython3Bin "fetch-model-hashes" {
      libraries = with python3Packages; [ huggingface-hub ];
      flakeIgnore = [ "E111" "E121" "E302" "E305" ];
    } ''
      import huggingface_hub as hf
      from multiprocessing.dummy import Pool
      import json

      repos = (
        model.id for model in hf.list_models(
          author="nvidia", library="nemo", expand="gated"
        ) if not model.gated
      )

      def get_name_hash(repo):
        if hf.file_exists(repo, f"{repo[7:]}.nemo"):
          url = hf.hf_hub_url(repo, f"{repo[7:]}.nemo")
          return repo[7:], hf.get_hf_file_metadata(url).etag

      with Pool() as pool:
        name_hash_pairs = filter(None, pool.map(get_name_hash, repos))
      print(json.dumps(dict(name_hash_pairs), sort_keys=True, indent=2))
    '';

  pullNeMoModel = name: hash:
    runCommand "${name}.nemo" {
      nativeBuildInputs = [ cacert python3Packages.hf-xet ];
      HF_XET_HIGH_PERFORMANCE = true;
      outputHashAlgo = "sha256";
      outputHash = hash;
    } ''
      mv $(readlink -e $(HF_HOME=/tmp ${
        lib.getExe python3Packages.huggingface-hub
      } download nvidia/${name} ${name}.nemo)) $out
    '';
}
