{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    systems.url = "github:nix-systems/default";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-parts,
      systems,
      treefmt-nix,
      ...
    }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } (
      { inputs, ... }:
      {
        systems = import inputs.systems;

        perSystem =
          {
            lib,
            system,
            pkgs,
            ...
          }:
          let
            treefmtEval = inputs.treefmt-nix.lib.evalModule pkgs ./treefmt.nix;
            version = "0.1.0-git+${self.shortRev or "dirty"}";
            pubspecLock = lib.importJSON ./pubspec.lock.json;

            inherit (pkgs) buildDartApplication;

            buildDartTest =
              args:
              (buildDartApplication (
                args
                // {
                  pname = "${args.pname}-tests";

                  buildPhase = ''
                    runHook preBuild
                    packageRun test $packageRoot --file-reporter json:$out
                    runHook postBuild
                  '';

                  dontInstall = true;
                }
              )).overrideAttrs
                { outputs = [ "out" ]; };
          in
          {
            _module.args.pkgs = import inputs.nixpkgs {
              inherit system;
              overlays = [ ];
            };

            formatter = treefmtEval.config.build.wrapper;

            checks = {
              formatting = treefmtEval.config.build.check self;
            }
            // lib.mapAttrs' (name: lib.nameValuePair "${name}-tests") (
              lib.genAttrs
                [
                  "riscv"
                  "river"
                  "river_adl"
                  "river_emulator"
                  "river_hdl"
                ]
                (
                  pname:
                  buildDartTest {
                    inherit pname;
                    inherit version pubspecLock;

                    src = ./.;
                    packageRoot = "packages/${pname}";
                  }
                )
            );

            packages = {
              default = buildDartApplication {
                pname = "river";
                inherit version pubspecLock;

                src = ./.;

                dartEntryPoints = {
                  "bin/river-emulator" = "packages/river_emulator/bin/river_emulator.dart";
                  # TODO: add HDL
                };

                preBuild = ''
                  mkdir -p bin
                '';
              };
              emulator = buildDartApplication {
                pname = "river-emulator";
                inherit version pubspecLock;

                src = ./.;
                packageRoot = "packages/river_emulator";

                dartEntryPoints."bin/river-emulator" = "packages/river_emulator/bin/river_emulator.dart";

                preBuild = ''
                  mkdir -p bin
                '';
              };
            };

            devShells.default = pkgs.mkShell {
              packages = with pkgs; [
                yq
                dart
                yosys
                icesprog
                icestorm
                openroad
                nextpnr
              ];
            };
          };
      }
    );
}
