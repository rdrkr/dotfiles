{
  description = "GCC 12.3.0 development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/a9858885e197f984d92d7fe64e9fff6b2e488d40";

  outputs = { self, nixpkgs }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };
  in {
    devShells.${system}.default = pkgs.mkShell {
      packages = [
        pkgs.gcc12
        pkgs.cmake
        pkgs.ninja
      ];

      shellHook = ''
        echo "GCC 12.3.0 dev environment activated"
        gcc --version | head -1
      '';
    };
  };
}
