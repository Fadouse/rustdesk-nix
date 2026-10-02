{
  lib,
  appimageTools,
  fetchurl,
  patchelf,
  pkgs,
  runCommand,
  runCommandCC,
  stdenv,
}:

let
  pname = "rustdesk";
  version = "1.5.0";

  src = fetchurl {
    url = "https://github.com/rustdesk/rustdesk/releases/download/${version}/rustdesk-${version}-x86_64.AppImage";
    hash = "sha256-Qi67kVtMcJ81Ec+ilBq879yx09YPZz9aIM+IpKssmqU=";
  };

  runtimePackages =
    appimageTools.defaultFhsEnvArgs.targetPkgs pkgs
    ++ appimageTools.defaultFhsEnvArgs.multiPkgs pkgs
    ++ [
      pkgs.libayatana-appindicator
      # PipeWire's SPA video converter loads FFmpeg, which requires a newer
      # libva than the one bundled by the AppImage.  Keep it ahead of AppImage
      # libraries in LD_LIBRARY_PATH to avoid an undefined vaMapBuffer2 symbol.
      pkgs.libva
      stdenv.cc.cc.lib
    ];

  runtimeLibraryPath = lib.makeLibraryPath runtimePackages;

  emptyAppRunHooks = runCommandCC "rustdesk-empty-apprun-hooks" { } ''
    mkdir -p $out/lib
    printf 'void rustdesk_empty_apprun_hooks(void) {}\n' > empty.c
    $CC -shared -fPIC empty.c -o $out/lib/libapprun_hooks.so
  '';

  contents = appimageTools.extractType2 {
    inherit pname version src;

    # RustDesk's AppImage ships an old libapprun_hooks.so which overflows its
    # fixed buffer when gtk_sudo resolves sudo through NixOS's long PATH.  A
    # no-op replacement keeps AppRun happy while the explicit runtime library
    # closure below provides the dependencies without a privilege-blocking
    # bubblewrap sandbox.
    postExtract = ''
      install -m755 ${emptyAppRunHooks}/lib/libapprun_hooks.so \
        $out/lib/x86_64/libapprun_hooks.so

      ${patchelf}/bin/patchelf \
        --set-interpreter ${stdenv.cc.bintools.dynamicLinker} $out/AppRun
      ${patchelf}/bin/patchelf \
        --set-interpreter ${stdenv.cc.bintools.dynamicLinker} \
        --force-rpath \
        --set-rpath \
          "${runtimeLibraryPath}:$out/lib/x86_64-linux-gnu:$out/usr/lib/x86_64-linux-gnu:$out/usr/share/rustdesk/lib" \
        $out/usr/share/rustdesk/rustdesk
      ${patchelf}/bin/patchelf \
        --force-rpath \
        --set-rpath \
          "${runtimeLibraryPath}:$out/lib/x86_64-linux-gnu:$out/usr/lib/x86_64-linux-gnu:$out/usr/share/rustdesk/lib" \
        $out/usr/share/rustdesk/lib/librustdesk.so

      substituteInPlace $out/AppRun.env \
        --replace-fail "APPDIR_LIBRARY_PATH=" \
          "APPDIR_LIBRARY_PATH=${runtimeLibraryPath}:"

      # The AppImage bundles the obsolete PipeWire 0.2 GStreamer plugin.  It
      # crashes against a modern Wayland portal in pw_thread_loop_new.  Keep
      # GStreamer, its scanner, PipeWire and SPA from one Nixpkgs generation.
      substituteInPlace $out/AppRun.env \
        --replace-fail \
          'GST_PLUGIN_PATH=/lib64/gstreamer-1.0:/usr/lib/x86_64-linux-gnu/gstreamer-1.0:$APPDIR/usr/lib/x86_64-linux-gnu/gstreamer-1.0' \
          'GST_PLUGIN_PATH=${pkgs.pipewire}/lib/gstreamer-1.0:${pkgs.gst_all_1.gst-plugins-base}/lib/gstreamer-1.0:${pkgs.gst_all_1.gstreamer.out}/lib/gstreamer-1.0' \
        --replace-fail \
          'GST_PLUGIN_SYSTEM_PATH=/lib64/gstreamer-1.0:/usr/lib/x86_64-linux-gnu/gstreamer-1.0:$APPDIR/usr/lib/x86_64-linux-gnu/gstreamer-1.0' \
          'GST_PLUGIN_SYSTEM_PATH=${pkgs.pipewire}/lib/gstreamer-1.0:${pkgs.gst_all_1.gst-plugins-base}/lib/gstreamer-1.0:${pkgs.gst_all_1.gstreamer.out}/lib/gstreamer-1.0' \
        --replace-fail \
          'GST_PLUGIN_SCANNER=$APPDIR/usr/lib/x86_64-linux-gnu/gstreamer1.0/gstreamer-1.0/gst-plugin-scanner' \
          'GST_PLUGIN_SCANNER=${pkgs.gst_all_1.gstreamer.out}/libexec/gstreamer-1.0/gst-plugin-scanner'
      printf '\nSPA_PLUGIN_DIR=${pkgs.pipewire}/lib/spa-0.2\n' >> $out/AppRun.env

      # Bundled generic-Linux utilities such as loginctl cannot execute on
      # NixOS.  Prefer host commands so the service can resolve the active
      # logind session and the GUI can invoke the host sudo wrapper.
      sed -i 's|^PATH=.*|PATH=/run/wrappers/bin:$PATH|' $out/AppRun.env
    '';
  };
in
runCommand "${pname}-${version}"
  {
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
  ''
    mkdir -p $out/bin $out/share/applications \
      $out/share/icons/hicolor/scalable/apps
    ln -s ${contents}/AppRun $out/bin/rustdesk

    install -m644 ${contents}/rustdesk.desktop \
      $out/share/applications/rustdesk.desktop
    substituteInPlace $out/share/applications/rustdesk.desktop \
      --replace-fail "Exec=usr/share/rustdesk/rustdesk" "Exec=rustdesk"

    install -m644 ${contents}/rustdesk.svg \
      $out/share/icons/hicolor/scalable/apps/rustdesk.svg
  ''
