{ pkgs ? import <nixpkgs> {} }:
pkgs.mkShell {
  nativeBuildInputs = with pkgs.buildPackages; [
    xorg.libX11
  ];

  LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [
    pkgs.buildPackages.xorg.libX11
  ];
}

