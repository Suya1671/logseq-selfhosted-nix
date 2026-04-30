{ inputs, ... }:
{
  perSystem = { pkgs, ... }: {
    checks.sync-worker-module = pkgs.testers.nixosTest {
      name = "sync-worker-test";

      nodes.machine = { ... }: {
        nixpkgs.overlays = [ inputs.self.overlays.default ];
        imports = [ inputs.self.nixosModules.sync-worker ];
        services.syncWorker = {
          enable = true;
          baseUrl = "http://localhost:8787";
        };
        system.stateVersion = "25.11";
      };

      testScript = ''
        # Adapted from https://github.com/yshalsager/logseq-selfhost/blob/master/images/sync/scripts/smoke-test.sh
        import json

        machine.wait_for_unit("logseq-sync-worker.service")
        machine.wait_for_open_port(8787)

        # 1) Liveness
        health_raw = machine.succeed("curl -fsS http://localhost:8787/health")
        health = json.loads(health_raw)
        assert health.get("ok") == True, f"expected ok=true, got: {health_raw}"

        # 2) Auth gate — /graphs without token should be 401
        graphs_status = machine.succeed(
          "curl -sS -o /dev/null -w '%{http_code}' http://localhost:8787/graphs"
        ).strip()
        assert graphs_status == "401", f"expected /graphs 401, got {graphs_status}"

        # 3) Sync route auth gate — unauthenticated pull should be 401
        sync_status = machine.succeed(
          "curl -sS -o /dev/null -w '%{http_code}' http://localhost:8787/sync/smoke-graph/pull?since=0"
        ).strip()
        assert sync_status == "401", f"expected /sync pull 401, got {sync_status}"
      '';
    };
  };
}
