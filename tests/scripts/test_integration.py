import socket
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
2026-10-04 21:01:52   S_ERR  [some-package] script called Console.Error
2026-10-04 21:01:52  S_WARN  [some-package] script called Console.Warn
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
        self.assertEqual(len(result.engine_errors), 3)
        self.assertFalse(result.ok)
        allowed = self.parse(allowed=["Known noisy engine message", "User Defined Event: 'zz'", "Console.Error"])
        self.assertEqual(allowed.engine_errors, [])

    def test_expected_lines_must_all_appear(self):
        result = integration.SuiteResult(name="demo")
        integration.parse_log(
            result,
            self.log,
            ["Lua Error", "Known noisy", "Console.Error"],
            [r"Loading Package 'foundation'", r"never written"],
        )
        self.assertEqual(result.missing_log_lines, ["never written"])
        self.assertFalse(result.ok)

    def test_sequence_must_appear_in_order(self):
        allowed = ["Lua Error", "Known noisy", "Console.Error"]
        in_order = integration.SuiteResult(name="demo")
        integration.parse_log(in_order, self.log, allowed, [], [r"demo PASS first", r"demo FAIL second", r"demo DONE"])
        self.assertIsNone(in_order.broken_sequence)
        reversed_order = integration.SuiteResult(name="demo")
        integration.parse_log(reversed_order, self.log, allowed, [], [r"demo DONE", r"demo PASS first"])
        self.assertEqual(reversed_order.broken_sequence, "demo PASS first")
        self.assertFalse(reversed_order.ok)

    def test_missing_log_is_an_error(self):
        result = integration.SuiteResult(name="demo")
        integration.parse_log(result, self.log.with_name("absent.log"), [])
        self.assertFalse(result.ok)
        self.assertIn("server log not found", result.engine_errors[0])

    def test_suite_without_done_or_passes_is_not_ok(self):
        self.assertFalse(integration.SuiteResult(name="x", passed=["a"]).ok)
        self.assertFalse(integration.SuiteResult(name="x", done=True).ok)
        self.assertTrue(integration.SuiteResult(name="x", passed=["a"], done=True).ok)


class PortSelectionTest(unittest.TestCase):
    def test_bound_port_is_not_free(self):
        port = integration.free_port_pair()
        self.assertTrue(integration.PORT_RANGE[0] <= port <= integration.PORT_RANGE[1])
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as holder:
            holder.bind(("127.0.0.1", port))
            self.assertFalse(integration.port_is_free(port))


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
