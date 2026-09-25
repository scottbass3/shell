{
  lib,
  stdenv,
  cmake,
  qt6,
  makeWrapper,
  quickshell,
  # Runtime tools the shell shells out to. Optional features light up when
  # present; these are appended to PATH, so the user's own versions win.
  hyprpaper,
  matugen,
  imagemagick,
  cava,
  brightnessctl,
  curl,
  libsecret,
  coreutils,
  gnused,
  gawk,
  procps,
  src,
  version,
}:

stdenv.mkDerivation {
  pname = "scottbass3-shell";
  inherit src version;

  # Only the bundled Caelestia.Blobs QML plugin is compiled; the rest is QML.
  cmakeDir = "../blobs-plugin";
  cmakeFlags = [
    # launch.sh looks for the plugin next to itself.
    (lib.cmakeFeature "INSTALL_QMLDIR" "${placeholder "out"}/share/scottbass3-shell")
  ];

  nativeBuildInputs = [
    cmake
    makeWrapper
    qt6.qtshadertools
  ];

  buildInputs = [
    qt6.qtbase
    qt6.qtdeclarative
  ];

  dontWrapQtApps = true;

  postInstall = ''
    dest=$out/share/scottbass3-shell
    cp -r \
      ../assets ../bar ../hypr ../panels ../scripts ../services ../theme ../widgets \
      ../shell.qml ../LockScreen.qml ../MainWindow.qml ../cava.conf ../launch.sh \
      $dest/

    # quickshell is prepended so it matches the Qt the plugin was built against.
    wrapProgram $dest/launch.sh \
      --prefix PATH : ${lib.makeBinPath [ quickshell ]} \
      --suffix PATH : ${
        lib.makeBinPath [
          hyprpaper
          matugen
          imagemagick
          cava
          brightnessctl
          curl
          libsecret
          coreutils
          gnused
          gawk
          procps
        ]
      } \
      --prefix NIXPKGS_QT6_QML_IMPORT_PATH : ${qt6.qtwebsockets}/${qt6.qtbase.qtQmlPrefix}

    mkdir -p $out/bin
    ln -s $dest/launch.sh $out/bin/scottbass3-shell
  '';

  meta = {
    description = "Material You desktop shell for Hyprland, built on Quickshell";
    homepage = "https://github.com/scottbass3/shell";
    license = lib.licenses.gpl3Only;
    mainProgram = "scottbass3-shell";
    platforms = lib.platforms.linux;
  };
}
