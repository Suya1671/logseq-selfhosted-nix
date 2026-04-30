{
  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    nvfetcher = {
      url = "github:berberman/nvfetcher";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    clj-nix = {
      url = "github:jlesquembre/clj-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ flake-parts, nixpkgs, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } ({
      ...
    }: {
      imports = [
        ./nix/packages
        ./nix/modules
        ./nix/checks.nix
      ];
      systems = nixpkgs.lib.systems.flakeExposed;

      perSystem = { pkgs, ... }: {
        devShells.default = pkgs.mkShell {
          packages = [ pkgs.nixd ];
        };
      };
    });
}
