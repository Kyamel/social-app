# NOTE:
# This setup relies on an external Android SDK instead of nix-managed androidenv.
# This is intentional to avoid emulator and Gradle issues commonly seen on NixOS.
# This setup is recommended for use with AndroidStudio.
#
# Requirements:
# - Android SDK installed at ~/Android/sdk
# - Node.js installed on the system, for example via nvm, fnm, mise, or system packages
#
# References:
# https://nixos.wiki/wiki/Android
#
# For a more pure Nix approach, you can explore androidenv,
# but it tends to be more fragile for React Native/Expo workflows.
{ pkgs ? import <nixpkgs> {} }:

let
  androidSdk = "${builtins.getEnv "HOME"}/Android/sdk";
  nodejs = pkgs.nodejs_22;
  yarn = pkgs.yarn.override {
    inherit nodejs;
  };

  nixLdLibraryPath = pkgs.lib.makeLibraryPath [
    pkgs.stdenv.cc.cc
    pkgs.zlib
    pkgs.ncurses5
    pkgs.libxml2
    pkgs.libuuid
  ];

  emulatorLibs = pkgs.lib.makeLibraryPath [
    pkgs.pulseaudio
    pkgs.alsa-lib
    pkgs.libGL
    pkgs.libpng
    pkgs.libdrm
    pkgs.libbsd
    pkgs.zlib
    pkgs.stdenv.cc.cc.lib

    pkgs.fontconfig
    pkgs.freetype
    pkgs.libxkbcommon

    pkgs.llvmPackages.libcxx
    pkgs.xorg.libSM
    pkgs.xorg.libICE

    pkgs.xorg.xcbutilcursor
    pkgs.xorg.xcbutilimage
    pkgs.xorg.xcbutilkeysyms
    pkgs.xorg.xcbutilrenderutil
    pkgs.xorg.xcbutilwm

    pkgs.xorg.libX11
    pkgs.xorg.libxcb
    pkgs.xorg.libXcomposite
    pkgs.xorg.libXcursor
    pkgs.xorg.libXi
    pkgs.xorg.libXrandr
    pkgs.xorg.libXrender
    pkgs.xorg.libXtst
    pkgs.xorg.libxkbfile
  ];

  emulatorRun = pkgs.writeShellScriptBin "emulator-run" ''
    export ANDROID_EMULATOR=${androidSdk}/emulator

    export QT_PLUGIN_PATH=$ANDROID_EMULATOR/lib64/qt/plugins
    export QT_QPA_PLATFORM=xcb

    export LD_LIBRARY_PATH=$ANDROID_EMULATOR/lib64/qt/lib:$ANDROID_EMULATOR/lib64:$ANDROID_EMULATOR/lib64/gles_swiftshader:${emulatorLibs}:$LD_LIBRARY_PATH

    exec "$ANDROID_EMULATOR/emulator" "$@"
  '';
in

pkgs.mkShell {
  buildInputs = with pkgs; [
    nodejs
    yarn
    watchman
    android-tools
    jdk17
    ninja
    cmake

    emulatorRun
  ];

  shellHook = ''
    export NODE_ENV=development

    export JAVA_HOME=${pkgs.jdk17}
    export PATH=$JAVA_HOME/bin:$PATH

    export ANDROID_HOME=${androidSdk}
    export ANDROID_SDK_ROOT=$ANDROID_HOME
    export ANDROID_NDK_HOME=$ANDROID_HOME/ndk/27.1.12297006
    export ANDROID_NDK_ROOT=$ANDROID_NDK_HOME

    # Android Studio's SDK/NDK binaries are generic Linux binaries. On NixOS,
    # nix-ld tells the stub loader which dynamic linker and libraries to use.
    export NIX_LD=${pkgs.stdenv.cc.bintools.dynamicLinker}
    export NIX_LD_LIBRARY_PATH=${nixLdLibraryPath}

    export PATH=$ANDROID_HOME/emulator:$PATH
    export PATH=$ANDROID_HOME/platform-tools:$PATH
    export PATH=$ANDROID_HOME/cmdline-tools/latest/bin:$PATH
    export PATH=$ANDROID_HOME/build-tools/35.0.0:$PATH
    export ADB=$ANDROID_HOME/platform-tools/adb

    echo "Expo env ready"
  '';
}