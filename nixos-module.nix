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
  };
}
