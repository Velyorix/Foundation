import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))

import integration  # noqa: E402

# Lines in the format written by nanos world server 1.156 (.logs/NanosWorldCore.log).
SAMPLE_LOG = """\
2026-10-04 21:01:50    INFO  Loading Package 'foundation' (0.1.0)...
2026-10-04 21:01:51  SCRIPT  [foundation-test-harness] [FOUNDATION-TEST] demo PASS first test
2026-10-04 21:01:51  SCRIPT  [foundation-test-harness] [FOUNDATION-TEST] demo FAIL second test :: expected 2, got 1
2026-10-04 21:01:51  SCRIPT  [foundation-test-harness] [FOUNDATION-TEST] other PASS not ours
2026-10-04 21:01:52   ERROR  Lua Error on User Defined Event: 'zz':
2026-10-04 21:01:52   ERROR  Known noisy engine message
2026-10-04 21:01:53  SCRIPT  [foundation-test-harness] [FOUNDATION-TEST] demo DONE passed=1 failed=1
"""


class ParseLogTest(unittest.TestCase):
    def setUp(self):
        self._dir = tempfile.TemporaryDirectory()
        self.addCleanup(self._dir.cleanup)
        self.log = Path(self._dir.name) / "NanosWorldCore.log"
        self.log.write_text(SAMPLE_LOG, encoding="utf-8")

    def parse(self, allowed=None):
        result = integration.SuiteResult(name="demo")
        integration.parse_log(result, self.log, allowed or [])
        return result

    def test_collects_results_for_the_suite_only(self):
        result = self.parse()
        self.assertEqual(result.passed, ["first test"])
        self.assertEqual(result.failed, [("second test", "expected 2, got 1")])
        self.assertTrue(result.done)

    def test_engine_errors_fail_the_suite_unless_allowed(self):
        result = self.parse()
        self.assertEqual(len(result.engine_errors), 2)
        self.assertFalse(result.ok)
        allowed = self.parse(allowed=["Known noisy engine message", "User Defined Event: 'zz'"])
        self.assertEqual(allowed.engine_errors, [])

    def test_missing_log_is_an_error(self):
        result = integration.SuiteResult(name="demo")
        integration.parse_log(result, self.log.with_name("absent.log"), [])
        self.assertFalse(result.ok)
        self.assertIn("server log not found", result.engine_errors[0])

    def test_suite_without_done_or_passes_is_not_ok(self):
        self.assertFalse(integration.SuiteResult(name="x", passed=["a"]).ok)
        self.assertFalse(integration.SuiteResult(name="x", done=True).ok)
        self.assertTrue(integration.SuiteResult(name="x", passed=["a"], done=True).ok)


class SuitesFileTest(unittest.TestCase):
    def test_every_suite_package_exists(self):
        for name, suite in integration.load_suites().items():
            for package in suite["packages"]:
                if package == "foundation":
                    path = integration.PACKAGE_DIR
                else:
                    path = integration.TEST_PACKAGES_DIR / package
                self.assertTrue((path / "Package.toml").is_file(), f"suite {name}: package {package} missing")


if __name__ == "__main__":
    unittest.main()
