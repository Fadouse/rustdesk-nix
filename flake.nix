{
  description = "Nix package for the latest official stable RustDesk AppImage";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      rustdesk = pkgs.callPackage ./package.nix { };
    in
    {
      packages.${system} = {
        inherit rustdesk;
        default = rustdesk;
      };

      nixosModules.default = import ./nixos-module.nix { inherit self; };

      checks.${system} = {
        package = rustdesk;
        updater-tests =
          pkgs.runCommand "rustdesk-updater-tests" { nativeBuildInputs = [ pkgs.python3 ]; }
            ''
              cp -r ${self} source
              chmod -R u+w source
              cd source
              python3 -m unittest discover -s tests -v
              touch "$out"
            '';
      };

      formatter.${system} = pkgs.nixfmt;
    };
}
