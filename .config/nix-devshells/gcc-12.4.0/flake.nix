{
  description = "GCC 12.4.0 development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/e6f23dc08d3624daab7094b701aa3954923c6bbb";

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
        echo "GCC 12.4.0 dev environment activated"
        gcc --version | head -1
      '';
    };
  };
}
