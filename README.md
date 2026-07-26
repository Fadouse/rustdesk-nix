# rustdesk-nix

A small Nix flake packaging RustDesk's official stable x86_64 AppImage.

## Use

```bash
nix run .#rustdesk
nix build .#rustdesk
nix flake check --print-build-logs
```

## Updating

```bash
python3 -m unittest discover -s tests -v
python3 scripts/update.py
nix flake check --print-build-logs
```

The scheduled GitHub Actions workflow checks RustDesk's latest stable release daily. It validates the GitHub-provided SHA-256 digest and AppImage header, builds the result, and opens or updates an automation pull request. No release binaries are committed to this repository.

Only `x86_64-linux` is supported.
