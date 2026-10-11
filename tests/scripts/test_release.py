import hashlib
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))

import release  # noqa: E402

CHANGELOG = """\
# Changelog

## [Unreleased]

### Added

- Storage.

## [0.1.0] - 2026-10-01

### Added

- First version.
"""


class VersionTest(unittest.TestCase):
    def test_reads_channels(self):
        cases = {
            "0.1.0": ("0.1.0", "stable"),
            "1.2.3-rc.1": ("1.2.3", "rc"),
            "1.2.3-beta.12": ("1.2.3", "beta"),
            "0.1.0-nightly.20261011": ("0.1.0", "nightly"),
            "0.1.0-nightly.20261011.2": ("0.1.0", "nightly"),
        }
        for text, (base, channel) in cases.items():
            version = release.parse_version(text)
            self.assertEqual((version.base, version.channel), (base, channel), text)
            self.assertEqual(version.prerelease, channel != "stable")

    def test_refuses_other_versions(self):
        for text in ["v0.1.0", "0.1", "01.0.0", "0.1.0-alpha.1", "0.1.0-rc.0", "0.1.0-rc", "0.1.0-nightly.20261399",
                     "0.1.0-nightly.2026101", "0.1.0-nightly.20261011.1", "0.1.0+build"]:
            with self.assertRaises(release.ReleaseError, msg=text):
                release.parse_version(text)

    def test_numbers_nightlies_of_the_same_day(self):
        self.assertEqual(release.nightly_version("0.1.0", "20261011", set()), "0.1.0-nightly.20261011")
        tags = {"v0.1.0-nightly.20261011", "v0.1.0-nightly.20261011.2"}
        self.assertEqual(release.nightly_version("0.1.0", "20261011", tags), "0.1.0-nightly.20261011.3")


class ChangelogTest(unittest.TestCase):
    def test_uses_the_version_section_or_unreleased_for_prereleases(self):
        self.assertEqual(release.release_changes(CHANGELOG, release.parse_version("0.1.0")), "### Added\n\n- First version.")
        self.assertEqual(release.release_changes(CHANGELOG, release.parse_version("0.1.0-rc.1")), "### Added\n\n- First version.")
        self.assertEqual(
            release.release_changes(CHANGELOG, release.parse_version("0.2.0-nightly.20261011")), "### Added\n\n- Storage."
        )

    def test_a_stable_release_needs_its_own_section(self):
        with self.assertRaisesRegex(release.ReleaseError, r"no \[0\.2\.0\] section"):
            release.release_changes(CHANGELOG, release.parse_version("0.2.0"))


class StampTest(unittest.TestCase):
    def test_writes_the_version_into_the_manifest_and_the_version_module(self):
        manifest = b'[meta]\n    title = "Foundation"\n    version =               "0.1.0"\n'
        module = b'return {\n\tPRODUCT = "0.1.0",\n\tAPI = "0.1",\n}\n'
        self.assertIn(b'version =               "0.1.0-beta.1"', release.stamp("Package.toml", manifest, "0.1.0-beta.1"))
        self.assertIn(b'PRODUCT = "0.1.0-beta.1"', release.stamp("Shared/foundation/version.lua", module, "0.1.0-beta.1"))
        self.assertEqual(release.stamp("Server/Index.lua", b"x", "0.1.0-beta.1"), b"x")
        with self.assertRaises(release.ReleaseError):
            release.stamp("Package.toml", b"[meta]\n", "0.1.0")


class BuildTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.out = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def test_builds_a_reproducible_archive_of_the_committed_package(self):
        base = release.manifest_field((release.REPO_ROOT / "package" / "Package.toml").read_text(), "version")
        text = f"{base}-nightly.20261011"
        archive, checksums, notes = release.build(text, "HEAD", self.out / "a")
        again, _, _ = release.build(text, "HEAD", self.out / "b")
        self.assertEqual(archive.name, f"foundation-{text}.zip")
        self.assertEqual(archive.read_bytes(), again.read_bytes())
        self.assertEqual(checksums.read_text(), f"{hashlib.sha256(archive.read_bytes()).hexdigest()}  {archive.name}\n")
        with zipfile.ZipFile(archive) as content:
            names = content.namelist()
            self.assertEqual(names, sorted(names))
            self.assertTrue(all(name.startswith("foundation/") for name in names))
            self.assertIn(f'PRODUCT = "{text}"', content.read("foundation/Shared/foundation/version.lua").decode())
        self.assertIn("**Nightly** build", notes.read_text(encoding="utf-8"))
        self.assertIn(f"gh attestation verify {archive.name}", notes.read_text(encoding="utf-8"))

    def test_refuses_a_version_that_does_not_match_the_manifest(self):
        with self.assertRaisesRegex(release.ReleaseError, "does not match"):
            release.build("99.0.0-beta.1", "HEAD", self.out)


if __name__ == "__main__":
    unittest.main()
