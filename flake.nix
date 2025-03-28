{
  description = "Zig project flake";

  inputs = {
    zig2nix.url = "github:Cloudef/zig2nix";
    zls.url = "github:zigtools/zls?ref=0.14.0";
    pwndbg-src.url = "github:pwndbg/pwndbg";
  };

  outputs = { zig2nix, zls, pwndbg-src, ... }: let
    flake-utils = zig2nix.inputs.flake-utils;
  in (flake-utils.lib.eachDefaultSystem (system: let
      zlsPkg = zls.packages.${system}.default;
      # Zig flake helper
      # Check the flake.nix in zig2nix project for more options:
      # <https://github.com/Cloudef/zig2nix/blob/master/flake.nix>
      env = zig2nix.outputs.zig-env.${system} {
        zig = zig2nix.outputs.packages.${system}.zig-0_14_0;
      };
      system-triple = env.lib.zigTripleFromString system;
    in with builtins; with env.lib; with env.pkgs.lib; rec {
      # nix build .#target.{zig-target}
      # e.g. nix build .#target.x86_64-linux-gnu
      packages.target = genAttrs allTargetTriples (target: env.packageForTarget target ({
        src = cleanSource ./kernel;

        nativeBuildInputs = with env.pkgs; [];
        buildInputs = with env.pkgsForTarget target; [];

        # Smaller binaries and avoids shipping glibc.
        zigPreferMusl = true;

        # This disables LD_LIBRARY_PATH mangling, binary patching etc...
        # The package won't be usable inside nix.
        zigDisableWrap = true;
      } // optionalAttrs (!pathExists ./build.zig.zon) {
        pname = "zigzagoon-kernel";
        version = "0.0.0";
      }));

      # nix build .
      packages.default = packages.target.${system-triple}.overrideAttrs (final: prev: {
        # Prefer nix friendly settings.
        zigPreferMusl = true;
        zigDisableWrap = false;
        # (Cajun) NOTE: We explicitly remove the "-Doptimize=ReleaseSafe" flag from
        # the build because we do not want large binaries and safety is a secondary
        # priority.
        zigBuildFlags = builtins.tail prev.zigBuildFlags ++ ["-Doptimize=ReleaseSmall"];
      });

      # For bundling with nix bundle for running outside of nix
      # example: https://github.com/ralismark/nix-appimage
      apps.bundle.target = genAttrs allTargetTriples (target: let
        pkg = packages.target.${target};
      in {
        type = "app";
        program = "${pkg}/bin/default";
      });

      # default bundle
      apps.bundle.default = apps.bundle.target.${system-triple};

      # nix run .
      apps.default = env.app [] "zig build run -- \"$@\"";

      # nix run .#build
      apps.build = env.app [] "zig build \"$@\"";

      # nix run .#test
      apps.test = env.app [] "zig build test -- \"$@\"";

      # nix run .#docs
      apps.docs = env.app [] "zig build docs -- \"$@\"";

      # nix run .#deps
      apps.deps = env.showExternalDeps;

      # nix run .#zon2json
      apps.zon2json = env.app [env.zon2json] "zon2json \"$@\"";

      # nix run .#zon2json-lock
      apps.zon2json-lock = env.app [env.zon2json-lock] "zon2json-lock \"$@\"";

      # nix run .#zon2nix
      apps.zon2nix = env.app [env.zon2nix] "zon2nix \"$@\"";

      # nix develop
      devShells.default = env.mkShell {
        nativeBuildInputs = with env.pkgs; [
          zlsPkg
          gdb
          pwndbg-src.packages.${system}.default
          inotify-tools
          pkgsCross.aarch64-multiplatform.gcc
          asm-lsp
          upx
          elfkickers
          (pkgs.python312.withPackages (pp: with pp; [
            pwntools
          ]))
          pyright
          python310Packages.pip
          python310Packages.virtualenv
          python310Packages.pyflakes
        ];
      };
    }));
}
