{
  dockerTools,
  logseq-sync-worker
}:
dockerTools.buildLayeredImage {
  name = "logseq-nix/sync-worker";
  tag = logseq-sync-worker.version + "-git";
  maxLayers = 32;
  config = {
    Cmd = [ "${logseq-sync-worker}/bin/logseq-sync-worker" ];
    ExposedPorts = {
      "8787/tcp" = {};
    };
    Env = [
      "DB_SYNC_PORT=8787"
      "DB_SYNC_DATA_DIR=/app/data"
      "DB_SYNC_STORAGE_DRIVER=sqlite"
      "DB_SYNC_ASSETS_DRIVER=filesystem"
      "DB_SYNC_LOG_LEVEL=info"
    ];
    Volumes = {
      "/app/data" = {};
    };
  };
}
