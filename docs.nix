{
  lib,
  mdbook,
  nixos,
  nixosOptionsDoc,
  runCommand,
  writers,
}:

let
  repoUrl = "https://github.com/m-bdf/NeMo.nix";

  inherit (nixosOptionsDoc {
    options = (nixos ./options.nix).options.services.nemo;

    transformOptions = o: o // {
      declarations = [{
        name = "options.nix";
        url = "${repoUrl}/blob/main/options.nix";
      }];
    };
  }) optionsCommonMark;

  mdbookConfig = writers.writeTOML "book.toml" {
    book.title = "NeMo.nix";
    output.html = {
      git-repository-url = repoUrl;
      site-url = (import ./flake.nix).inputs.sources.url;
    };
  };
in

runCommand "nemo-mdbook" {} ''
  mkdir -p src
  ln -sf ${./README.md} src/README.md
  ln -sf ${optionsCommonMark} src/options.md

  echo '
    [Introduction](README.md)
    [Options](options.md)
  ' > src/SUMMARY.md

  ln -sf ${mdbookConfig} book.toml
  ${lib.getExe mdbook} build --dest-dir $out
''
