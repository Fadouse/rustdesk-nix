#!/usr/bin/env python3
"""Update package.nix to the latest official stable RustDesk AppImage."""

from __future__ import annotations

import base64
import hashlib
import json
import os
import re
import tempfile
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "package.nix"
RELEASE_API = "https://api.github.com/repos/rustdesk/rustdesk/releases/latest"
USER_AGENT = "rustdesk-nix-updater/1"
MAX_DOWNLOAD_BYTES = 256 * 1024 * 1024
VERSION_RE = re.compile(r"\d+\.\d+\.\d+")


@dataclass(frozen=True)
class Release:
    version: str
    url: str
    sha256_hex: str


def request(url: str) -> urllib.request.Request:
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": USER_AGENT,
        "X-GitHub-Api-Version": "2022-11-28",
    }
    if token := os.environ.get("GITHUB_TOKEN"):
        headers["Authorization"] = f"Bearer {token}"
    return urllib.request.Request(url, headers=headers)


def fetch_release_payload() -> dict[str, Any]:
    with urllib.request.urlopen(request(RELEASE_API), timeout=30) as response:
        payload = json.load(response)
    if not isinstance(payload, dict):
        raise ValueError("GitHub returned a non-object release payload")
    return payload


def parse_release(payload: dict[str, Any]) -> Release:
    if payload.get("draft") is not False or payload.get("prerelease") is not False:
        raise ValueError("Latest GitHub release is not a stable published release")

    version = payload.get("tag_name")
    if not isinstance(version, str) or VERSION_RE.fullmatch(version) is None:
        raise ValueError(f"Unsupported release version: {version!r}")

    name = f"rustdesk-{version}-x86_64.AppImage"
    expected_url = f"https://github.com/rustdesk/rustdesk/releases/download/{version}/{name}"
    assets = payload.get("assets")
    if not isinstance(assets, list):
        raise ValueError("Release does not contain an asset list")
    matches = [asset for asset in assets if isinstance(asset, dict) and asset.get("name") == name]
    if len(matches) != 1:
        raise ValueError(f"Expected exactly one {name} asset")

    asset = matches[0]
    if asset.get("browser_download_url") != expected_url:
        raise ValueError("Release asset has an unexpected download URL")
    digest = asset.get("digest")
    if not isinstance(digest, str) or re.fullmatch(r"sha256:[0-9a-f]{64}", digest) is None:
        raise ValueError("Release asset is missing a valid GitHub SHA-256 digest")
    return Release(version, expected_url, digest.removeprefix("sha256:"))


def hex_to_sri(digest_hex: str) -> str:
    raw = bytes.fromhex(digest_hex)
    if len(raw) != hashlib.sha256().digest_size:
        raise ValueError("Invalid SHA-256 digest length")
    return "sha256-" + base64.b64encode(raw).decode("ascii")


def sri_to_hex(sri: str) -> str:
    if not sri.startswith("sha256-"):
        raise ValueError("Only SHA-256 SRI hashes are supported")
    try:
        raw = base64.b64decode(sri.removeprefix("sha256-"), validate=True)
    except (ValueError, base64.binascii.Error) as error:
        raise ValueError("Invalid SRI hash") from error
    if len(raw) != hashlib.sha256().digest_size:
        raise ValueError("Invalid SHA-256 digest length")
    return raw.hex()


def download_and_validate(release: Release, destination: Path) -> None:
    digest = hashlib.sha256()
    total = 0
    with urllib.request.urlopen(request(release.url), timeout=120) as response:
        length = response.headers.get("Content-Length")
        if length is not None and int(length) > MAX_DOWNLOAD_BYTES:
            raise ValueError("Release asset is larger than the configured limit")
        with destination.open("wb") as output:
            while chunk := response.read(1024 * 1024):
                total += len(chunk)
                if total > MAX_DOWNLOAD_BYTES:
                    raise ValueError("Release asset exceeded the configured limit")
                digest.update(chunk)
                output.write(chunk)
    if total < 16:
        raise ValueError("Downloaded release asset is too small")
    if digest.hexdigest() != release.sha256_hex:
        raise ValueError("Downloaded asset does not match GitHub's SHA-256 digest")

    header = destination.read_bytes()[:16]
    if header[:4] != b"\x7fELF" or header[4:7] != bytes((2, 1, 1)):
        raise ValueError("Release asset is not a little-endian ELF64 file")
    if header[8:11] != b"AI\x02":
        raise ValueError("Release asset is not an AppImage type 2 file")


def read_metadata(path: Path = PACKAGE) -> tuple[str, str, str]:
    text = path.read_text(encoding="utf-8")
    versions = re.findall(r'^  version = "([^"]+)";$', text, flags=re.MULTILINE)
    hashes = re.findall(r'^    hash = "(sha256-[^"]+)";$', text, flags=re.MULTILINE)
    if len(versions) != 1 or len(hashes) != 1:
        raise ValueError("package.nix must contain exactly one version and source hash")
    return text, versions[0], hashes[0]


def version_tuple(version: str) -> tuple[int, int, int]:
    if VERSION_RE.fullmatch(version) is None:
        raise ValueError(f"Unsupported version: {version!r}")
    return tuple(int(part) for part in version.split("."))  # type: ignore[return-value]


def update_package(path: Path, version: str, sri_hash: str) -> bool:
    original = path.read_text(encoding="utf-8")
    updated, version_count = re.subn(
        r'^  version = "[^"]+";$', f'  version = "{version}";', original, count=1, flags=re.MULTILINE
    )
    updated, hash_count = re.subn(
        r'^    hash = "sha256-[^"]+";$', f'    hash = "{sri_hash}";', updated, count=1, flags=re.MULTILINE
    )
    if version_count != 1 or hash_count != 1:
        raise ValueError("Could not update package.nix unambiguously")
    if updated == original:
        return False
    temporary = path.with_suffix(".nix.tmp")
    temporary.write_text(updated, encoding="utf-8")
    temporary.replace(path)
    return True


def main() -> int:
    release = parse_release(fetch_release_payload())
    _, current_version, current_sri = read_metadata()
    if release.version == current_version:
        if release.sha256_hex != sri_to_hex(current_sri):
            raise ValueError("Official asset changed without a version bump; refusing to update")
        print(f"RustDesk {current_version} is already current")
        return 0
    if version_tuple(release.version) < version_tuple(current_version):
        raise ValueError(f"GitHub returned older release {release.version} than packaged {current_version}")

    with tempfile.TemporaryDirectory(prefix="rustdesk-nix-update-") as directory:
        download_and_validate(release, Path(directory) / f"rustdesk-{release.version}-x86_64.AppImage")

    update_package(PACKAGE, release.version, hex_to_sri(release.sha256_hex))
    print(f"Updated RustDesk {current_version} -> {release.version}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, json.JSONDecodeError) as error:
        raise SystemExit(f"rustdesk-nix updater: {error}") from error
