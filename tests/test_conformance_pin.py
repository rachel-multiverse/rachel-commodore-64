"""The offline codec gate must reject missing or modified fixture pins."""

import hashlib
import importlib.util
import tempfile
import unittest
from pathlib import Path


class FixturePinTests(unittest.TestCase):
    def setUp(self) -> None:
        spec = importlib.util.spec_from_file_location(
            "conformance_runner",
            Path(__file__).resolve().parents[1] / "conformance/run.py",
        )
        assert spec is not None and spec.loader is not None
        self.runner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.runner)
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        root = Path(self.directory.name)
        self.fixture = root / "fixture.json"
        self.pin = root / "fixture.sha256"
        self.fixture.write_bytes(b'{"messages": []}\n')
        self.runner.FIXTURES = str(self.fixture)
        self.runner.FIXTURES_SHA = str(self.pin)

    def write_valid_pin(self) -> None:
        digest = hashlib.sha256(self.fixture.read_bytes()).hexdigest()
        self.pin.write_text(f"{digest}  fixture.json\n")

    def test_valid_pin_passes(self) -> None:
        self.write_valid_pin()
        self.runner.check_fixtures_pinned()

    def test_missing_pin_fails(self) -> None:
        with self.assertRaises(SystemExit) as failure:
            self.runner.check_fixtures_pinned()
        self.assertEqual(2, failure.exception.code)

    def test_changed_fixture_fails(self) -> None:
        self.write_valid_pin()
        self.fixture.write_bytes(b'{"messages": ["changed"]}\n')
        with self.assertRaises(SystemExit) as failure:
            self.runner.check_fixtures_pinned()
        self.assertEqual(2, failure.exception.code)


if __name__ == "__main__":
    unittest.main()
