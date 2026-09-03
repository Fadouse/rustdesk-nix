{
  description = "Nix packaging for private prebuilt RustDesk x86_64 variants";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      releaseMetadata = builtins.fromJSON (builtins.readFile ./release/metadata.json);
      mkPackage = variant: pkgs.callPackage ./package.nix { inherit variant releaseMetadata; };
      x86_64-v3 = mkPackage "x86_64-v3";
      znver5 = mkPackage "znver5";

      defaultEvaluation = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          self.nixosModules.default
          { services.rustdesk.enable = true; }
        ];
      };
      securityEvaluation = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          self.nixosModules.security
          {
            services.rustdesk = {
              enable = true;
              security.enable = true;
            };
          }
        ];
      };
      expectedLsm = [
        "landlock"
        "lockdown"
        "yama"
        "integrity"
        "apparmor"
        "bpf"
      ];
    in
    {
      packages.${system} = {
        inherit x86_64-v3 znver5;
        default = x86_64-v3;
      };

      nixosModules = {
        default = import ./nixos-module.nix { inherit self; };
        security = import ./security-module.nix { inherit self; };
      };

      checks.${system} = {
        inherit x86_64-v3 znver5;

        package-layout = pkgs.runCommand "rustdesk-package-layout" { } ''
          for package in ${x86_64-v3} ${znver5}; do
            test -x "$package/bin/rustdesk"
            test -x "$package/libexec/rustdesk/rustdesk"
            test -s "$package/share/applications/rustdesk.desktop"
            test -s "$package/share/icons/hicolor/scalable/apps/rustdesk.svg"
            test -s "$package/share/licenses/rustdesk/LICENCE"
            grep -q '^Exec=rustdesk %u$' "$package/share/applications/rustdesk.desktop"
          done
          touch "$out"
        '';

        module-evaluation =
          assert defaultEvaluation.config.services.rustdesk.package == x86_64-v3;
          assert securityEvaluation.config.security.lsm == expectedLsm;
          assert securityEvaluation.config.security.apparmor.enable;
          assert securityEvaluation.config.security.apparmor.policies.rustdesk-gui.state == "enforce";
          assert securityEvaluation.config.security.apparmor.policies.rustdesk-service.state == "enforce";
          assert securityEvaluation.config.systemd.services.rustdesk.serviceConfig.ProtectSystem == "strict";
          assert securityEvaluation.config.systemd.services.rustdesk.serviceConfig.ProtectHome;
          assert securityEvaluation.config.systemd.services.rustdesk.serviceConfig.PrivateTmp;
          assert securityEvaluation.config.systemd.services.rustdesk.serviceConfig.NoNewPrivileges;
          assert securityEvaluation.config.systemd.services.rustdesk.serviceConfig.RestrictSUIDSGID;
          pkgs.runCommand "rustdesk-module-evaluation" { } ''
            touch "$out"
          '';

        apparmor-syntax =
          pkgs.runCommand "rustdesk-apparmor-syntax"
            {
              nativeBuildInputs = [ pkgs.apparmor-parser ];
            }
            ''
              apparmor_parser --skip-kernel-load --skip-read-cache ${./apparmor/rustdesk-gui}
              apparmor_parser --skip-kernel-load --skip-read-cache ${./apparmor/rustdesk-service}
              touch "$out"
            '';
      };

      formatter.${system} = pkgs.nixfmt;
    };
}
