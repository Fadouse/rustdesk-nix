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
      default = self.packages.${system}.rustdesk;
      defaultText = lib.literalExpression "rustdesk-nix.packages.\${pkgs.system}.rustdesk";
      description = "RustDesk package used by the GUI and system service.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    # The privileged service keeps system-wide configuration and input access,
    # but RustDesk's Wayland capture server must run inside the logged-in
    # graphical user's session.  Without the user server, the device remains
    # registered as online while connections stall after the GUI is closed.
    systemd.services.rustdesk = {
      description = "RustDesk remote desktop service";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network.target"
        "systemd-user-sessions.service"
      ];
      wants = [ "network.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/rustdesk --service";
        Restart = "on-failure";
        RestartSec = 3;
        KillMode = "mixed";
        TimeoutStopSec = 30;
        LimitNOFILE = 100000;
      };

      environment = {
        PULSE_LATENCY_MSEC = "60";
        PIPEWIRE_LATENCY = "1024/48000";
      };
    };

    systemd.user.services.rustdesk-server = {
      description = "RustDesk remote desktop server";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/rustdesk --server";
        Restart = "on-failure";
        RestartSec = 3;
        KillMode = "mixed";
        TimeoutStopSec = 30;
        LimitNOFILE = 100000;
      };

      environment = {
        PULSE_LATENCY_MSEC = "60";
        PIPEWIRE_LATENCY = "1024/48000";
      };
    };
  };
}
