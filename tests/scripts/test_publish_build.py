import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))

import publish_build  # noqa: E402


class SignatureTest(unittest.TestCase):
    def test_matches_the_website_implementation(self):
        # Computed with the website's CiRequestSignature::sign (PHP hash_hmac).
        self.assertEqual(
            publish_build.signature("s3cret", "1760000000", "abcdef0123456789abcd", "post", "api/ci/v1/builds", b'{"a":1}'),
            "e3e1166b13ea0c801f7e8e686bafd5a86e3e0f88668b904246578ad23890afbb",
        )


class BuildNumberTest(unittest.TestCase):
    def test_counts_release_tags_in_creation_order(self):
        tags = ["v0.1.0-nightly.20261011", "experiment", "v0.1.0-nightly.20261012", "v0.1.0-beta.1"]
        self.assertEqual(publish_build.build_number("v0.1.0-nightly.20261011", tags), 1)
        self.assertEqual(publish_build.build_number("v0.1.0-beta.1", tags), 3)
        with self.assertRaises(publish_build.PublishError):
            publish_build.build_number("v9.9.9", tags)


class FakeClient:
    site = "https://example.test"

    def __init__(self, answers):
        self.answers = list(answers)
        self.calls = []
        self.uploads = []

    def call(self, method, url, payload=None):
        self.calls.append((method, url))
        return self.answers.pop(0)

    def upload(self, target, path):
        self.uploads.append((target["url"], path.name))


class PublishTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.dist = Path(self.temp.name)
        (self.dist / "foundation-0.1.0.zip").write_bytes(b"zip")
        (self.dist / "SHA256SUMS").write_text("x")
        self.build = {"build_number": 1}

    def tearDown(self):
        self.temp.cleanup()

    def test_uploads_every_file_then_completes(self):
        client = FakeClient([
            (201, {"uploads": [{"filename": "foundation-0.1.0.zip", "url": "u1"}, {"filename": "SHA256SUMS", "url": "u2"}],
                   "complete_url": "https://example.test/api/ci/v1/builds/7/complete"}),
            (202, {"id": 7, "status": "verifying"}),
        ])
        self.assertEqual(publish_build.publish(client, self.build, self.dist), "build 7 is verifying")
        self.assertEqual(client.uploads, [("u1", "foundation-0.1.0.zip"), ("u2", "SHA256SUMS")])
        self.assertEqual(client.calls[1], ("POST", "https://example.test/api/ci/v1/builds/7/complete"))

    def test_accepts_a_build_the_site_already_has(self):
        client = FakeClient([(409, {"error": "build_exists", "build": {"id": 7, "status": "available"}})])
        self.assertEqual(publish_build.publish(client, self.build, self.dist), "build 7 is already available")
        self.assertEqual(client.uploads, [])

    def test_reports_conflicts_and_refusals(self):
        for answer in [(409, {"error": "build_exists", "build": {"id": 7, "status": "revoked"}}), (422, {"errors": {"version": ["bad"]}})]:
            with self.assertRaises(publish_build.PublishError):
                publish_build.publish(FakeClient([answer]), self.build, self.dist)


if __name__ == "__main__":
    unittest.main()
