{
  lib,
  appimageTools,
  fetchurl,
}:

let
  pname = "rustdesk";
  version = "1.4.9";

  src = fetchurl {
    url = "https://github.com/rustdesk/rustdesk/releases/download/${version}/rustdesk-${version}-x86_64.AppImage";
    hash = "sha256-eQLNYKTymBfuviZooVyaGVKsaQ6Pewe/52IP7dTighc=";
  };

  contents = appimageTools.extractType2 { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    install -Dm644 ${contents}/rustdesk.desktop $out/share/applications/rustdesk.desktop
    substituteInPlace $out/share/applications/rustdesk.desktop \
      --replace-fail "Exec=usr/share/rustdesk/rustdesk" "Exec=rustdesk"

    install -Dm644 ${contents}/rustdesk.svg $out/share/icons/hicolor/scalable/apps/rustdesk.svg
  '';

  extraPkgs = pkgs: [ pkgs.libayatana-appindicator ];

  meta = {
    description = "Open-source remote desktop application";
    homepage = "https://rustdesk.com";
    changelog = "https://github.com/rustdesk/rustdesk/releases/tag/${version}";
    license = lib.licenses.agpl3Only;
    mainProgram = "rustdesk";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
