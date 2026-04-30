{ lib, config, pkgs, ... }:
let
  cfg = config.services.syncWorker;
in
{
  options.services.syncWorker = {
    enable = lib.mkEnableOption "Logseq sync worker service";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.logseq-sync-worker;
      defaultText = lib.literalExpression "pkgs.logseq-sync-worker";
      description = "The logseq-sync-worker package to use";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8787;
      description = "Port for the sync worker to listen on";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/logseq-sync";
      description = ''
        Directory for sync worker data storage.
        If changed from the default, the directory must be created manually
        and owned by the service user.
      '';
    };

    storageDriver = lib.mkOption {
      type = lib.types.enum [ "sqlite" ];
      default = "sqlite";
      description = "Storage driver type";
    };

    assetsDriver = lib.mkOption {
      type = lib.types.enum [ "filesystem" ];
      default = "filesystem";
      description = "Assets driver type";
    };

    logLevel = lib.mkOption {
      type = lib.types.enum [ "debug" "info" "warn" "error" ];
      default = "info";
      description = "Log level";
    };

    baseUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://localhost:8787";
      example = "https://sync.example.com";
      description = "Base URL for the sync service";
    };

    cognito = {
      issuer = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "https://cognito-idp.us-east-1.amazonaws.com/us-east-1_dtagLnju8";
        description = "Cognito issuer URL for JWT validation";
      };

      clientId = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "69cs1lgme7p8kbgld8n5kseii6";
        description = "Cognito client ID for JWT validation";
      };

      jwksUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "https://cognito-idp.us-east-1.amazonaws.com/us-east-1_dtagLnju8/.well-known/jwks.json";
        description = "Cognito JWKS URL for JWT validation";
      };
    };

    adminTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/logseq-admin-token";
      description = "Path to a file containing the admin token, used for maintenance endpoints";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "logseq-sync-worker";
      description = "User to run the service as";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "logseq-sync-worker";
      description = "Group to run the service as";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = lib.mkIf (cfg.user == "logseq-sync-worker") {
      isSystemUser = true;
      group = cfg.group;
      description = "Logseq sync worker service";
    };

    users.groups.${cfg.group} = lib.mkIf (cfg.group == "logseq-sync-worker") {};

    systemd.services.logseq-sync-worker = {
      description = "Logseq db-sync worker";

      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;

        ExecStart = if cfg.adminTokenFile != null
          then pkgs.writeShellScript "start-sync-worker" ''
            export DB_SYNC_ADMIN_TOKEN=$(< "$CREDENTIALS_DIRECTORY/admin-token")
            exec ${lib.getExe cfg.package}
          ''
          else lib.getExe cfg.package;

        LoadCredential = lib.mkIf (cfg.adminTokenFile != null)
          "admin-token:${cfg.adminTokenFile}";

        Environment = [
          "DB_SYNC_PORT=${toString cfg.port}"
          "DB_SYNC_DATA_DIR=${cfg.dataDir}"
          "DB_SYNC_STORAGE_DRIVER=${cfg.storageDriver}"
          "DB_SYNC_ASSETS_DRIVER=${cfg.assetsDriver}"
          "DB_SYNC_LOG_LEVEL=${cfg.logLevel}"
          "DB_SYNC_BASE_URL=${cfg.baseUrl}"
        ] ++ lib.optionals (cfg.cognito.issuer != "") [
          "COGNITO_ISSUER=${cfg.cognito.issuer}"
        ] ++ lib.optionals (cfg.cognito.clientId != "") [
          "COGNITO_CLIENT_ID=${cfg.cognito.clientId}"
        ] ++ lib.optionals (cfg.cognito.jwksUrl != "") [
          "COGNITO_JWKS_URL=${cfg.cognito.jwksUrl}"
        ];

        Restart = "on-failure";
        RestartSec = "5s";

        ReadWritePaths = [ cfg.dataDir ];

        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
      };

      environment = {
        NODE_ENV = "production";
      };
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} - -"
    ];
  };
}
