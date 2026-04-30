{ withSystem, ... }:
{
  flake.nixosModules.sync-worker = { pkgs, ... }: {
    imports = [ ./nixos.nix ];

    _module.args.package = withSystem pkgs.stdenv.hostPlatform.system (
      { config, ... }: config.packages.logseq-sync-worker
    );
  };
}
