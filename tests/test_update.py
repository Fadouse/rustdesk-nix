import base64
import hashlib
import tempfile
import unittest
from pathlib import Path

from scripts.update import hex_to_sri, parse_release, sri_to_hex, update_package, version_tuple


class UpdateTests(unittest.TestCase):
    def release(self, **overrides):
        version = overrides.pop("version", "1.4.9")
        name = f"rustdesk-{version}-x86_64.AppImage"
        payload = {
            "draft": False,
            "prerelease": False,
            "tag_name": version,
            "assets": [{
                "name": name,
                "browser_download_url": f"https://github.com/rustdesk/rustdesk/releases/download/{version}/{name}",
                "digest": "sha256:" + "12" * 32,
            }],
        }
        payload.update(overrides)
        return payload

    def test_parse_stable_release(self):
        release = parse_release(self.release())
        self.assertEqual(release.version, "1.4.9")
        self.assertEqual(release.sha256_hex, "12" * 32)

    def test_rejects_prerelease(self):
        with self.assertRaises(ValueError):
            parse_release(self.release(prerelease=True))

    def test_rejects_wrong_asset_url(self):
        payload = self.release()
        payload["assets"][0]["browser_download_url"] = "https://example.invalid/file"
        with self.assertRaises(ValueError):
            parse_release(payload)

    def test_rejects_missing_digest(self):
        payload = self.release()
        payload["assets"][0]["digest"] = None
        with self.assertRaises(ValueError):
            parse_release(payload)

    def test_hash_conversion_round_trip(self):
        digest = hashlib.sha256(b"rustdesk").hexdigest()
        self.assertEqual(sri_to_hex(hex_to_sri(digest)), digest)

    def test_version_comparison_key(self):
        self.assertLess(version_tuple("1.4.9"), version_tuple("1.5.0"))

    def test_updates_exact_metadata(self):
        old_hash = "sha256-" + base64.b64encode(bytes(32)).decode()
        new_hash = "sha256-" + base64.b64encode(bytes([1]) * 32).decode()
        text = f'''{{ fetchurl }}:\nlet\n  version = "1.4.8";\n  src = fetchurl {{\n    hash = "{old_hash}";\n  }};\nin src\n'''
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "package.nix"
            path.write_text(text)
            self.assertTrue(update_package(path, "1.4.9", new_hash))
            updated = path.read_text()
            self.assertIn('version = "1.4.9";', updated)
            self.assertIn(f'hash = "{new_hash}";', updated)


if __name__ == "__main__":
    unittest.main()
