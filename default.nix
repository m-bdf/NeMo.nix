{
  cacert,
  curl,
  go,
  jq,
  lib,
  nemo,
  python3Packages,
  runCommand,
  writers,
  writeShellApplication,
}:

{
  fetchImageDigests =
    writeShellApplication {
      name = "fetch-image-digests";
      text = ''
        ${lib.getExe curl} \
          -G https://catalog.ngc.nvidia.com/api/containers/images \
          -d orgName=nvidia -d name=nemo -d isPublic=true -sSf |

        ${lib.getExe jq} '
          .images | map({
            (.tag): .architectureVariants | map({
              (.architecture): .digest
            }) | add
          }) | add
        '
      '';
    };

  pullNeMoImage = tag: digests:
    nemo.lib.pullImageFromDigest digests.${go.GOARCH} {
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
          author="nvidia", filter="nemo", expand="gated"
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
