# rustdesk-nix

Nix packaging for the private prebuilt RustDesk Linux archives in
`Fadouse/rustdesk-build`. The application is not compiled here. Two independent
packages are exposed for `x86_64-linux`:

- `packages.x86_64-linux.x86_64-v3`
- `packages.x86_64-linux.znver5`
- `packages.x86_64-linux.default` (the `x86_64-v3` package)

## Secure private-release prefetch

A Nix derivation must never receive a GitHub credential. Authenticate `gh` with
read access to `Fadouse/rustdesk-build`, then run:

```bash
./scripts/fetch-release
```

The script downloads only the three asset IDs recorded in
`release/metadata.json`, validates file sizes and metadata hashes, executes
`sha256sum -c` against the release's `SHA256SUMS`, removes GitHub token variables
before invoking Nix, and adds both archives with `nix-store --add-fixed sha256`.
`package.nix` consumes them through `requireFile`; no token or private URL is
placed in a derivation or the Nix store.

Build either package without installing it:

```bash
nix build .#x86_64-v3
nix build .#znver5
```

## NixOS modules

`nixosModules.default` installs the selected package and optionally starts the
hardened RustDesk service:

```nix
{
  imports = [ rustdesk-nix.nixosModules.default ];
  services.rustdesk.enable = true;
  # services.rustdesk.package = rustdesk-nix.packages.x86_64-linux.znver5;
}
```

`nixosModules.security` includes the default module and adds separate GUI and
service AppArmor profiles plus the ordered LSM stack
`landlock,lockdown,yama,integrity,apparmor,bpf`:

```nix
{
  imports = [ rustdesk-nix.nixosModules.security ];
  services.rustdesk = {
    enable = true;
    security.enable = true;
  };
}
```

The service keeps Wayland/X11, PipeWire, network and required input-device
access while applying systemd hardening. The profiles deny SSH private keys,
other users' homes and kernel debug interfaces by default. The wrapper contains
no GPU-vendor detection, driver selection, codec patch, or machine-specific
hardware setting; those remain the host configuration's responsibility.

## Automation and checks

`Synchronize private RustDesk release` uses only the repository secret
`PRIVATE_RELEASE_TOKEN` to read the latest private release. It verifies all
assets, refuses a rollback, updates metadata, validates the Nix builds/checks,
and commits to `dev` only. It never merges `main`.

CI performs only the approved non-runtime checks: release SHA verification,
both package builds, file layout, NixOS module evaluation and AppArmor parsing
with kernel loading disabled. It does not start the RustDesk GUI/service or
perform remote desktop, capture, or input tests.

After an accepted merge to `main`, the release workflow tags
`<binary-version>-nix.1`, exports each actual Nix store closure as `tar.zst`, and
publishes the two closure archives plus `SHA256SUMS`.
