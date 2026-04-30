{ lib
, stdenv
, nodejs-slim
, pnpm_10
, pnpmConfigHook
, fetchPnpmDeps
, clojure
, git
, sources
, mk-deps-cache
, python3
, gnumake
, gcc
, pkg-config
, removeReferencesTo
, makeBinaryWrapper
}: stdenv.mkDerivation (finalAttrs: rec {
  pname = "logseq-sync-worker";
  inherit (sources.logseq) version src;

  nativeBuildInputs = [
    nodejs-slim
    pnpm_10
    pnpmConfigHook
    clojure
    git
    makeBinaryWrapper

    # better-sqlite3 my beloathed
    removeReferencesTo
    python3
    gnumake
    gcc
    pkg-config
  ];

  # only devdep is sentry CLI, which isn't needed for building
  pnpmInstallFlags = [ "--prod" ];

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version pnpmInstallFlags;
    src = src + "/deps/db-sync";
    fetcherVersion = 3;
    pnpm = pnpm_10;

    hash = "sha256-kiZTmYyWPbmoV8Ru80EhMaVKqr7hZoBfvukEw0o8uhk=";
  };

  clojureDeps = mk-deps-cache {
    lockfile = ./deps-lock.json;
  };

  pnpmRoot = "deps/db-sync";

  postPatch = ''
    pushd deps/db-sync
        # Remove exact pnpm version to prevent version mismatch
        substituteInPlace package.json \
        --replace-fail '"packageManager": "pnpm@10.33.0"' '"packageManager": "pnpm"'
    popd
  '';

  preBuild = ''
    cd deps/db-sync

    export PNPM_HOME=$(mktemp -d)
    export HOME="${clojureDeps}"
    export JAVA_TOOL_OPTIONS="-Duser.home=${clojureDeps}"

    pushd node_modules/.pnpm/better-sqlite3*/node_modules/better-sqlite3
        pnpm run build-release --offline --nodedir="${nodejs-slim}"
        rm -rf build/Release/{obj.target,sqlite3.a,.deps} deps
        rm -f build/Makefile build/config.gypi build/binding.Makefile
    popd
  '';

  buildPhase = ''
    runHook preBuild

    pnpm run build:node-adapter

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/app
    cp -r worker node_modules package.json $out/app

    # Remove build artifacts that bloat the closure
    # Sanity check in case the preBuild step didn't remove everything
    find "$out/app/node_modules" \( \
      -name config.gypi \
      -o -name .deps \
      -o -name '*Makefile' \
      -o -name '*.target.mk' \
    \) -exec rm -r {} +

    makeWrapper "${lib.getExe nodejs-slim}" "$out/bin/logseq-sync-worker" \
      --add-flags --enable-source-maps \
      --add-flags "$out/app/worker/dist/node-adapter.js" \
      --set-default NODE_ENV production

    runHook postInstall
  '';

  disallowedReferences = [
    python3
    gcc
    clojure
    git
  ];

  meta = with lib; {
    description = "Logseq db-sync worker";
    homepage = "https://logseq.com";
    license = licenses.agpl3Plus;

    # TODO: check compat with other platforms
    platforms = platforms.linux;

    mainProgram = "logseq-sync-worker";
    sourceProvenance = with sourceTypes; [ fromSource ];
  };
})
