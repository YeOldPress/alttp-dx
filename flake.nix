{
  description = "alttp-zig flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem ( system:
      let
        pkgs = import nixpkgs { inherit system; };
        runtimeLibs = with pkgs; [
          sdl3
        ];
      in
      {
        devShells.default = 
          with pkgs;
          mkShell {
            nativeBuildInputs = [ pkgs.zig_0_17 pkg-config ];
            buildInputs = [ sdl3 ];
            LD_LIBRARY_PATH = lib.makeLibraryPath runtimeLibs;
          };
        

        packages.default = 
          with pkgs; 
          stdenv.mkDerivation {
            name = "zelda3";
            src = ./.;

            nativeBuildInputs = [ pkgs.zig_0_17 pkg-config makeWrapper ];
            buildInputs = [ sdl3 ];

            zigBuildFlags = [
              "--search-prefix" "${lib.getDev sdl3}"
              "--search-prefix" "${lib.getLib sdl3}"
            ];

            postFixup = ''
              wrapProgram $out/bin/zelda3 \
                --run 'dataDir="''${XDG_DATA_HOME:-$HOME/.local/share}/alttp-zig"' \
                --run 'mkdir -p "$dataDir"' \
                --run 'cd "$dataDir"' \
                --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath runtimeLibs }
            '';
        };
      }
    );
}
