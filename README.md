# rustdesk-nix

A small Nix flake packaging RustDesk's official stable x86_64 AppImage.

## Use

```bash
nix run .#rustdesk
nix build .#rustdesk
nix flake check --print-build-logs
```

For unattended access on NixOS, import and enable the included module:

```nix
{
  inputs.rustdesk-nix.url = "path:/path/to/rustdesk-nix";

  outputs = { nixpkgs, rustdesk-nix, ... }: {
    nixosConfigurations.example = nixpkgs.lib.nixosSystem {
      modules = [
        rustdesk-nix.nixosModules.default
        { services.rustdesk.enable = true; }
      ];
    };
  };
}
```

The module installs the same package system-wide and runs `rustdesk --service`
as a root system service. Do not also add the package separately through Home
Manager unless you intentionally want duplicate profile entries.

## Updating

```bash
python3 -m unittest discover -s tests -v
python3 scripts/update.py
nix flake check --print-build-logs
```

The scheduled GitHub Actions workflow checks RustDesk's latest stable release daily. It validates the GitHub-provided SHA-256 digest and AppImage header, builds the result, and opens or updates an automation pull request. No release binaries are committed to this repository.

Only `x86_64-linux` is supported.
