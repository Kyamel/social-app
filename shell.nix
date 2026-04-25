{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    #nodejs_20
    yarn
    watchman
    #git
  ];

  shellHook = ''
    export NODE_ENV=development
    echo "Ambiente Expo pronto 🚀"
  '';
}