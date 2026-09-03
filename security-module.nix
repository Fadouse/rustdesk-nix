{ self }:
{
  config,
  lib,
  ...
}:
let
  cfg = config.services.rustdesk;
in
{
  imports = [ (import ./nixos-module.nix { inherit self; }) ];

  options.services.rustdesk.security.enable =
    lib.mkEnableOption "the RustDesk AppArmor profiles and ordered LSM stack";

  config = lib.mkIf (cfg.enable && cfg.security.enable) {
    security.lsm = lib.mkForce [
      "landlock"
      "lockdown"
      "yama"
      "integrity"
      "apparmor"
      "bpf"
    ];

    security.apparmor = {
      enable = true;
      policies = {
        rustdesk-gui = {
          state = "enforce";
          path = ./apparmor/rustdesk-gui;
        };
        rustdesk-service = {
          state = "enforce";
          path = ./apparmor/rustdesk-service;
        };
      };
    };

    systemd.services.rustdesk = {
      after = [ "apparmor.service" ];
      requires = [ "apparmor.service" ];
      serviceConfig.AppArmorProfile = "rustdesk-service";
    };
  };
}
