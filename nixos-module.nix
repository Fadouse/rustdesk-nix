{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.rustdesk;
  system = pkgs.stdenv.hostPlatform.system;
in
{
  options.services.rustdesk = {
    enable = lib.mkEnableOption "the RustDesk remote desktop system service";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${system}.default;
      defaultText = lib.literalExpression "rustdesk-nix.packages.\${pkgs.system}.default";
      description = "RustDesk package used by the GUI and system service.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    systemd.services.rustdesk = {
      description = "RustDesk remote desktop service";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network.target"
        "systemd-user-sessions.service"
      ];
      wants = [ "network.target" ];

      environment = {
        HOME = "/var/lib/rustdesk";
        PATH = "/run/wrappers/bin:${
          lib.makeBinPath [
            pkgs.systemd
            pkgs.xdg-utils
          ]
        }";
        XDG_CACHE_HOME = "/var/cache/rustdesk";
        XDG_CONFIG_HOME = "/var/lib/rustdesk/config";
        XDG_DATA_HOME = "/var/lib/rustdesk/data";
        XDG_DATA_DIRS = "${pkgs.gsettings-desktop-schemas}/share:${pkgs.gtk3}/share";
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/libexec/rustdesk/rustdesk --service";
        Restart = "on-failure";
        RestartSec = 3;
        KillMode = "mixed";
        TimeoutStopSec = 30;
        LimitNOFILE = 100000;
        UMask = "0077";

        StateDirectory = "rustdesk";
        StateDirectoryMode = "0700";
        CacheDirectory = "rustdesk";
        CacheDirectoryMode = "0700";
        RuntimeDirectory = "rustdesk";
        RuntimeDirectoryMode = "0700";

        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        BindReadOnlyPaths = [ "-/tmp/.X11-unix" ];
        NoNewPrivileges = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        ProtectHostname = true;
        ProtectClock = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        RestrictRealtime = true;
        SystemCallArchitectures = "native";
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
          "AF_NETLINK"
        ];

        # Keep host display/PipeWire sockets and input injection available.
        PrivateDevices = false;
        DevicePolicy = "closed";
        DeviceAllow = [
          "/dev/uinput rw"
          "char-input rw"
        ];

        CapabilityBoundingSet = [
          "CAP_CHOWN"
          "CAP_DAC_OVERRIDE"
          "CAP_FOWNER"
          "CAP_KILL"
          "CAP_SETGID"
          "CAP_SETUID"
        ];
      };
    };
  };
}
