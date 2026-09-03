{
  lib,
  stdenv,
  stdenvNoCC,
  requireFile,
  autoPatchelfHook,
  makeWrapper,
  zstd,
  gtk3,
  pulseaudio,
  libxkbcommon,
  libXtst,
  libXfixes,
  libxcb,
  gst_all_1,
  dbus,
  systemd,
  xdg-utils,
  gsettings-desktop-schemas,
  variant,
  releaseMetadata ? builtins.fromJSON (builtins.readFile ./release/metadata.json),
}:

let
  asset = releaseMetadata.assets.${variant};
  src = requireFile {
    name = asset.name;
    sha256 = asset.nixHash;
    message = ''
      RustDesk ${variant} is a private release asset and cannot be fetched by a
      derivation. Run ./scripts/fetch-release with gh authenticated for
      Fadouse/rustdesk-build, then retry the build.
    '';
  };
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "rustdesk-${variant}";
  version = releaseMetadata.version;
  inherit src;

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    zstd
  ];

  buildInputs = [
    gtk3
    pulseaudio
    libxkbcommon
    libXtst
    libXfixes
    libxcb
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    dbus
    stdenv.cc.cc.lib
  ];

  strictDeps = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/libexec/rustdesk" \
      "$out/share/applications" "$out/share/icons/hicolor/scalable/apps" \
      "$out/share/licenses/rustdesk"
    cp -a . "$out/libexec/rustdesk"
    chmod 0755 "$out/libexec/rustdesk/rustdesk"

    install -m0644 LICENCE "$out/share/licenses/rustdesk/LICENCE"
    install -m0644 data/flutter_assets/assets/icon.svg \
      "$out/share/icons/hicolor/scalable/apps/rustdesk.svg"

    cat > "$out/share/applications/rustdesk.desktop" <<EOF
    [Desktop Entry]
    Type=Application
    Name=RustDesk (${variant})
    Comment=Remote desktop client
    Exec=rustdesk %u
    Icon=rustdesk
    Terminal=false
    Categories=Network;RemoteAccess;
    StartupNotify=true
    StartupWMClass=rustdesk
    MimeType=x-scheme-handler/rustdesk;
    EOF

    makeWrapper "$out/libexec/rustdesk/rustdesk" "$out/bin/rustdesk" \
      --prefix PATH : "/run/wrappers/bin:${
        lib.makeBinPath [
          systemd
          xdg-utils
        ]
      }" \
      --prefix XDG_DATA_DIRS : "${gsettings-desktop-schemas}/share:${gtk3}/share:$out/share"

    runHook postInstall
  '';

  # Upstream archives contain build-machine RUNPATH entries. Remove them before
  # autoPatchelfHook resolves the runtime closure from buildInputs.
  preFixup = ''
    while IFS= read -r -d $'\0' file; do
      if patchelf --print-rpath "$file" >/dev/null 2>&1; then
        patchelf --remove-rpath "$file"
      fi
    done < <(find "$out/libexec/rustdesk" -type f -print0)
  '';

  postFixup = ''
    while IFS= read -r -d $'\0' file; do
      if rpath=$(patchelf --print-rpath "$file" 2>/dev/null); then
        case "$rpath" in
          *"/mnt/data/Code/Systems/rustdesk-build"*)
            echo "build-machine RUNPATH remained in $file" >&2
            exit 1
            ;;
        esac
      fi
    done < <(find "$out/libexec/rustdesk" -type f -print0)
  '';

  passthru = {
    inherit variant releaseMetadata;
  };

  meta = {
    description = "RustDesk private prebuilt binary (${variant})";
    homepage = "https://github.com/Fadouse/rustdesk-build";
    license = lib.licenses.agpl3Only;
    mainProgram = "rustdesk";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
