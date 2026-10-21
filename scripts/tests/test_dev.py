"""Contract tests with fake tools in disposable checkouts; not Xcode validation."""
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
STUB = r'''
import json, os, pathlib, sys
tool = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
mode = os.environ.get("STUB_MODE", "")
if tool == "xcodebuild":
    if args == ["-version"]:
        if mode == "missing-xcode":
            print("Xcode unavailable", file=sys.stderr)
            sys.exit(72)
        print("Xcode 27.1\nBuild version " + ("wrong" if mode == "wrong-xcode" else "27A9275"))
    else:
        print("build/test stdout")
        print("build/test stderr", file=sys.stderr)
        if "test" in args:
            pathlib.Path(args[args.index("-resultBundlePath") + 1]).mkdir()
            if mode == "test-failure": sys.exit(65)
        elif mode == "build-failure": sys.exit(66)
elif tool == "xcode-select":
    print("/fake/Xcode/Contents/Developer")
elif args[:2] == ["swift", "--version"]:
    print("Apple Swift version 6.4")
elif args[:1] == ["--find"]:
    if mode == "missing-formatter" and args[1] == "swift-format": sys.exit(72)
    print("/fake/" + args[1])
elif "--show-sdk-version" in args:
    print("25.0" if mode == "old-sdk" else "27.1")
elif args[:3] == ["simctl", "list", "runtimes"]:
    print(json.dumps({"runtimes": [{"identifier": "ios27", "version": "27.0", "platform": "iOS", "isAvailable": True}]}))
elif args[:3] == ["simctl", "list", "devices"]:
    devices = [] if mode == "missing-simulator" else [
        {"name": "iPhone B", "udid": "B", "isAvailable": True, "state": "Booted"},
        {"name": "iPhone A", "udid": "A", "isAvailable": True, "state": "Shutdown"}]
    print(json.dumps({"devices": {"ios27": devices}}))
elif args[:2] == ["swift-format", "--version"]:
    print("main")
elif args[:1] == ["swift-format"]:
    if mode == "format-failure":
        print("bad.swift:1:1: error: indentation", file=sys.stderr)
        sys.exit(1)
elif args[:1] == ["xcresulttool"]:
    print(json.dumps({"result": "Passed", "passedTests": 0 if mode == "zero-tests" else 22,
                      "failedTests": 1 if mode == "hidden-failure" else 0,
                      "skippedTests": 1 if mode == "skipped-tests" else 0}))
else:
    print("Unexpected fake command", args, file=sys.stderr)
    sys.exit(99)
'''


class DevTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="dev-contract-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "checkout with spaces"
        (self.root / "scripts" / "tests").mkdir(parents=True)
        (self.root / "scripts" / "tests" / "test_fixture.py").write_text(
            "import unittest\nclass Fixture(unittest.TestCase):\n    def test_fixture(self): self.assertTrue(True)\n")
        shutil.copy2(ROOT / "scripts" / "dev", self.root / "scripts" / "dev")
        shutil.copy2(ROOT / ".dev-tools.json", self.root)
        (self.root / "iOSEngineerCodeCheck.xcodeproj").mkdir()
        (self.root / "iOSEngineerCodeCheck.xcodeproj" / "project.pbxproj").write_text(
            "IPHONEOS_DEPLOYMENT_TARGET = 26.6; SWIFT_VERSION = 6.0;")
        self.source = self.root / "source.swift"
        self.source.write_text("sentinel: preserve source\n")
        self.bin = Path(self.temp.name) / "bin"
        self.bin.mkdir()
        for name in ("xcodebuild", "xcode-select", "xcrun"):
            path = self.bin / name
            path.write_text("#!" + sys.executable + "\n" + STUB)
            path.chmod(0o755)

    def invoke(self, *args, mode="", extra_env=None):
        env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"], STUB_MODE=mode)
        for name in ("DEV_SIMULATOR_UDID", "DEV_RUNTIME", "DEVELOPER_DIR", "TOOLCHAINS"):
            env.pop(name, None)
        env.update(extra_env or {})
        result = subprocess.run([sys.executable, "-B", str(self.root / "scripts" / "dev"), *args],
                                cwd=self.temp.name, env=env, capture_output=True, text=True)
        return result

    def reports(self):
        return sorted((self.root / ".dev" / "runs").glob("*/summary.json"))

    def report(self):
        paths = self.reports()
        self.assertEqual(len(paths), 1)
        return paths[0].parent, json.loads(paths[0].read_text())

    def test_invalid_arguments_exit_two_before_output(self):
        for args in (("unknown",), ("check-all", "--only", "Suite"), ("test-unit", "--only", "-x"),
                     ("format", "--fresh"), ("test-ui", "--only", "Suite;bad"), ("test-unit", "--only", "")):
            with self.subTest(args=args):
                self.assertEqual(self.invoke(*args).returncode, 2)
        self.assertFalse((self.root / ".dev").exists())

    def test_missing_environment_preserves_error_and_marks_unrun(self):
        result = self.invoke("check-all", mode="missing-xcode")
        self.assertEqual(result.returncode, 72)
        path, report = self.report()
        self.assertEqual(report["status"], "failed")
        self.assertEqual(report["steps"][0]["status"], "failed")
        self.assertTrue(all(step["status"] == "not-run" for step in report["steps"][1:]))
        self.assertIn("Xcode unavailable", (path / "doctor.log").read_text())
        self.assertIn("Install/select full Xcode", result.stderr)

    def test_missing_formatter_sdk_runtime_and_wrong_xcode(self):
        for mode in ("missing-formatter", "old-sdk", "missing-simulator", "wrong-xcode"):
            with self.subTest(mode=mode):
                self.assertNotEqual(self.invoke("doctor", mode=mode).returncode, 0)

    def test_build_failure_propagates_both_output_streams(self):
        result = self.invoke("build", mode="build-failure")
        self.assertEqual(result.returncode, 66)
        path, report = self.report()
        log = (path / "build.log").read_text()
        self.assertIn("build/test stdout", log)
        self.assertIn("build/test stderr", log)
        self.assertIn("CODE_SIGNING_ALLOWED=NO", log)
        self.assertIn("SWIFT_TREAT_WARNINGS_AS_ERRORS=YES", log)
        self.assertEqual(report["steps"][-1]["exit_code"], 66)

    def test_test_failure_preserves_xcresult(self):
        self.assertEqual(self.invoke("test-unit", mode="test-failure").returncode, 65)
        path, report = self.report()
        self.assertTrue((path / "test-unit.xcresult").is_dir())
        self.assertEqual(report["status"], "failed")

    def test_format_failure_stops_aggregate_without_modifying_source(self):
        self.assertEqual(self.invoke("check-fast", mode="format-failure").returncode, 1)
        path, report = self.report()
        self.assertEqual([step["status"] for step in report["steps"]],
                         ["passed", "failed", "not-run", "not-run", "not-run"])
        self.assertIn("indentation", (path / "format-check.log").read_text())
        self.assertEqual(self.source.read_text(), "sentinel: preserve source\n")

    def test_zero_skipped_and_failed_results_are_not_success(self):
        for mode in ("zero-tests", "skipped-tests", "hidden-failure"):
            with self.subTest(mode=mode):
                self.assertEqual(self.invoke("test-unit", "--only", "Suite/method()", mode=mode).returncode, 1)

    def test_full_plan_and_selected_simulator(self):
        self.assertEqual(self.invoke("check-all").returncode, 0)
        path, report = self.report()
        self.assertEqual(report["status"], "passed")
        self.assertEqual([step["name"] for step in report["steps"]],
                         ["doctor", "format-check", "script-test", "static-check", "test-unit", "test-ui", "build-release"])
        self.assertTrue(all(step["status"] == "passed" for step in report["steps"]))
        self.assertEqual(report["environment"]["simulator"]["udid"], "A")
        self.assertIn("-configuration Release", (path / "build-release.log").read_text())
        self.assertIn("-only-testing:iOSEngineerCodeCheckUITests", (path / "test-ui.log").read_text())

    def test_explicit_simulator_and_selector(self):
        self.assertEqual(self.invoke("test-unit", "--only", "Suite/method()",
                                     extra_env={"DEV_SIMULATOR_UDID": "B"}).returncode, 0)
        path, report = self.report()
        self.assertEqual(report["environment"]["simulator"]["udid"], "B")
        self.assertIn("-only-testing:iOSEngineerCodeCheckTests/Suite/method()", (path / "test-unit.log").read_text())
        self.assertNotEqual(self.invoke("doctor", extra_env={"DEV_SIMULATOR_UDID": "absent"}).returncode, 0)

    def test_runs_are_unique_and_fresh_does_not_delete_cache(self):
        cache = self.root / ".dev" / "DerivedData"
        cache.mkdir(parents=True)
        (cache / "sentinel").write_text("keep")
        for args in (("build",), ("build",), ("build", "--fresh")):
            self.assertEqual(self.invoke(*args).returncode, 0)
        paths = self.reports()
        self.assertEqual(len(paths), 3)
        reports = [json.loads(path.read_text()) for path in paths]
        cached = [r["environment"]["derived_data"] for r in reports if not r["fresh"]]
        fresh = [r["environment"]["derived_data"] for r in reports if r["fresh"]]
        self.assertEqual(cached[0], cached[1])
        self.assertNotEqual(cached[0], fresh[0])
        self.assertTrue(str(self.root / ".dev" / "runs") in fresh[0])
        self.assertEqual(self.source.read_text(), "sentinel: preserve source\n")
        self.assertEqual((cache / "sentinel").read_text(), "keep")

    def test_concurrent_run_fails_without_unlocking_owner(self):
        (self.root / ".dev").mkdir()
        with (self.root / ".dev" / "lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.assertEqual(self.invoke("build").returncode, 1)
            _, report = self.report()
            self.assertIn("Another", report["error"])
            self.assertTrue(all(step["status"] == "not-run" for step in report["steps"]))

    def test_symlink_output_is_rejected(self):
        outside = Path(self.temp.name) / "outside"
        outside.mkdir()
        (self.root / ".dev").symlink_to(outside)
        self.assertEqual(self.invoke("build").returncode, 1)
        self.assertEqual(list(outside.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
