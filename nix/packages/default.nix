{ inputs, ... }:
{
  flake.overlays.default = final: prev: {
    logseq-sync-worker = final.callPackage ./sync-worker {
      sources = final.callPackage ../../_sources/generated.nix {};
      mk-deps-cache = inputs.clj-nix.packages.${final.stdenv.hostPlatform.system}.mk-deps-cache;
    };
  };

  perSystem = { pkgs, ... }: {
    packages = let
      mk-deps-cache = inputs.clj-nix.packages.${pkgs.stdenv.hostPlatform.system}.mk-deps-cache;
      sources = pkgs.callPackage ../../_sources/generated.nix {};
    in rec {
      logseq-sync-worker = pkgs.callPackage ./sync-worker { inherit sources mk-deps-cache; };
      logseq-sync-worker-docker = pkgs.callPackage ./sync-worker/docker.nix { inherit logseq-sync-worker; };

      nvfetcher = inputs.nvfetcher.packages.${pkgs.stdenv.hostPlatform.system}.default;

      update-deps = pkgs.writeShellScriptBin "update-deps" ''
        set -euo pipefail

        # TODO: sync pnpm deps hash
        FLAKE_ROOT="$(git rev-parse --show-toplevel)"
        SYNC_WORKER_FILE="$FLAKE_ROOT/nix/packages/sync-worker/default.nix"
        SYNC_LOCK_FILE="$FLAKE_ROOT/nix/packages/sync-worker/deps-lock.json"

        cd $FLAKE_ROOT
        ${inputs.nvfetcher.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/nvfetcher

        WORKDIR=$(mktemp -d -t logseq-lock-XXXX)
        cd $WORKDIR

        cp -r ${sources.logseq.src}/* .
        chmod -R u+w .

        cd deps/db-sync
        ${inputs.clj-nix.packages.${pkgs.stdenv.hostPlatform.system}.deps-lock}/bin/deps-lock --bb
        cp deps-lock.json "$SYNC_LOCK_FILE"

        rm -rf "$WORKDIR"
      '';
    };
  };
}
