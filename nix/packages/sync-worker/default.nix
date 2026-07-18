{ lib
, stdenv
, nodejs-slim
, pnpm_10
, pnpmConfigHook
, fetchPnpmDeps
, fetchurl
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

  # mldoc is required at runtime by logseq.graph-parser.mldoc (pulled in
  # transitively via logseq/outliner → logseq/graph-parser) but is only
  # declared in the graph-parser package.json, not in db-sync's. In the
  # monorepo pnpm workspace hoists it; in our isolated build it's missing.
  # We fetch it separately and inject it into node_modules after pnpm setup.
  mldocSrc = fetchurl {
    url = "https://registry.npmjs.org/mldoc/-/mldoc-1.5.9.tgz";
    hash = "sha256-DDOG1LGdmXAKcdYFnOriSr2bQOfCVmR/TDGFx5Vce24=";
  };

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
  pnpmRoot = "deps/db-sync";

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version pnpmInstallFlags;
    src = src + "/deps/db-sync";
    fetcherVersion = 4;
    pnpm = pnpm_10;

    hash = "sha256-A1EkwC6E7ZNmDYUzq+Iet0CEIwQVdxGn5nd/HJQKB3w=";
  };

  clojureDeps = mk-deps-cache {
    lockfile = ./deps-lock.json;
  };


  postPatch = ''
    pushd deps/db-sync
        # Remove exact pnpm version to prevent version mismatch
        substituteInPlace package.json \
        --replace-fail '"packageManager": "pnpm@10.33.0"' '"packageManager": "pnpm"'

        # Shadow the root pnpm-workspace.yaml so pnpm doesn't traverse up
        # and try to install the entire monorepo
        cat > pnpm-workspace.yaml << 'EOF'
packages:
  - "."
allowBuilds:
  better-sqlite3: true
EOF
    popd
  '';

  preBuild = ''
    cd deps/db-sync

    export PNPM_HOME=$(mktemp -d)
    export HOME="${clojureDeps}"
    export JAVA_TOOL_OPTIONS="-Duser.home=${clojureDeps}"

    # Inject mldoc into node_modules — it's not in db-sync's package.json
    # but the compiled node-adapter.js require()s it at runtime
    mkdir -p node_modules/mldoc
    tar -xzf ${finalAttrs.mldocSrc} -C node_modules/mldoc --strip-components=1

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
