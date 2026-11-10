"""Exercise simulator execution and local recipe behavior."""

import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

SCRIPTS = Path(__file__).parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


runner = load("ios_runner", "test-ios.py")
selector = load("ios_selector", "select-ios-tests.py")


class RecipeTests(unittest.TestCase):
    def test_actual_recipe_preserves_local_coverage_and_adhoc_ci_failure(self):
        recipe = SCRIPTS.parents[1] / "justfile"
        for ci, exit_code, verbose in [(False, 0, "true"), (True, 65, "true"), (True, 65, "false")]:
            with self.subTest(ci=ci, exit_code=exit_code, verbose=verbose), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                (root / "justfile").write_text(recipe.read_text())
                cargo = root / "cargo"
                cargo.write_text(f"#!{sys.executable}\n" + """import json, os, sys
with open(os.environ["CARGO_CAPTURE"], "a") as log:
    log.write(json.dumps(sys.argv[1:]) + "\\n")
if "exec" in sys.argv:
    command = sys.argv[sys.argv.index("xcodebuild"):]
    os.execvp(command[0], command)
""")
                xcode = root / "xcodebuild"
                xcode.write_text(f"#!{sys.executable}\n" + """import json, os, sys
with open(os.environ["XCODE_CAPTURE"], "w") as log:
    json.dump(sys.argv[1:], log)
sys.exit(int(os.environ["XCODE_EXIT"]))
""")
                cargo.chmod(0o755)
                xcode.chmod(0o755)
                env = {key: value for key, value in os.environ.items() if not key.startswith("IOS_TEST_")}
                env.update(PATH=f"{root}:{env['PATH']}", CARGO_CAPTURE=str(root / "cargo.jsonl"),
                           XCODE_CAPTURE=str(root / "xcode.json"), XCODE_EXIT=str(exit_code))
                if ci:
                    env.update(IOS_TEST_DESTINATION="platform=iOS Simulator,id=ci-device",
                               IOS_TEST_RESULT_BUNDLE=str(root / "results with spaces.xcresult"),
                               IOS_TEST_AD_HOC_SIGNING="true", IOS_TEST_PACKAGES=str(root / "packages"),
                               IOS_TEST_DERIVED_DATA=str(root / "build data"))
                result = subprocess.run(["just", "test", "ios", "--verbose"] if verbose == "true"
                                        else ["just", "test", "ios"], cwd=root, env=env,
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, exit_code, result.stderr)
                args = json.loads((root / "xcode.json").read_text())
                self.assertEqual(args[args.index("-scheme") + 1], "EiginDev")
                self.assertIn("-skip-testing:EiginTests/ProviderIntegrationTests", args)
                self.assertEqual(args[-1], "test")
                calls = [json.loads(line) for line in (root / "cargo.jsonl").read_text().splitlines()]
                self.assertTrue(any(call[-3:] == ["config", "export", "ios"] for call in calls))
                self.assertTrue(any(call[-2:] == ["generate", "ios"] for call in calls))
                if ci:
                    self.assertEqual(args[args.index("-destination") + 1], env["IOS_TEST_DESTINATION"])
                    self.assertEqual(args[args.index("-resultBundlePath") + 1], env["IOS_TEST_RESULT_BUNDLE"])
                    self.assertEqual(args[args.index("-clonedSourcePackagesDirPath") + 1], env["IOS_TEST_PACKAGES"])
                    self.assertEqual(args[args.index("-derivedDataPath") + 1], env["IOS_TEST_DERIVED_DATA"])
                    for setting in ["CODE_SIGNING_ALLOWED=YES", "CODE_SIGNING_REQUIRED=YES",
                                    "CODE_SIGN_IDENTITY=-", "CODE_SIGN_STYLE=Manual", "DEVELOPMENT_TEAM="]:
                        self.assertIn(setting, args)
                else:
                    self.assertEqual(args[args.index("-destination") + 1],
                                     "platform=iOS Simulator,name=iPhone 17 Pro")
                    self.assertNotIn("-clonedSourcePackagesDirPath", args)
                    self.assertEqual(args[args.index("-derivedDataPath") + 1], "src/eigin_ios/DerivedData")
                    self.assertNotIn("-resultBundlePath", args)
                    self.assertFalse(any(arg.startswith("CODE_SIGNING_") for arg in args))


class RunnerTests(unittest.TestCase):
    def test_runtime_selection_rejects_other_versions_and_unavailable(self):
        data = {"runtimes": [{"identifier": name, "isAvailable": True} for name in
                            (runner.RUNTIME, "com.apple.CoreSimulator.SimRuntime.watchOS-26-2")]}
        runner.validate_runtimes(data)
        data["runtimes"][0]["isAvailable"] = False
        with self.assertRaises(RuntimeError):
            runner.validate_runtimes(data)

    def test_xcode_skips_broken_and_rc_installations(self):
        versions = [subprocess.CalledProcessError(1, "xcodebuild"),
                    "Xcode 26.2\nBuild version 17C48", "Xcode 26.2\nBuild version 17C52"]
        apps = [Path(f"/Applications/Xcode-{n}.app") for n in range(3)]
        with patch.object(Path, "glob", return_value=apps), \
                patch.object(subprocess, "check_output", side_effect=versions), \
                patch.dict(os.environ, {}, clear=False), contextlib.redirect_stdout(io.StringIO()):
            runner.select_xcode()
            self.assertEqual(os.environ["DEVELOPER_DIR"], str(apps[2] / "Contents/Developer"))

    def test_suite_exit_status_reports_and_cleanup(self):
        for exit_code in (0, 65):
            with self.subTest(exit_code=exit_code), tempfile.TemporaryDirectory() as temp:
                previous = Path.cwd()
                os.chdir(temp)
                try:
                    process = Mock(stdout=iter(["test output\n"]))
                    process.wait.return_value = exit_code
                    runtimes = {"runtimes": [{"identifier": name, "isAvailable": True} for name in
                                            (runner.RUNTIME, "com.apple.CoreSimulator.SimRuntime.watchOS-26-2")]}
                    with patch.dict(os.environ, {"IOS_CACHE_DIR": str(Path(temp) / "cache")}), \
                            patch.object(runner, "select_xcode"), patch.object(runner, "install_tools"), \
                            patch.object(runner, "prepare", return_value=Path(temp)), \
                            patch.object(runner, "output", side_effect=[json.dumps(runtimes), "Xcode", "rustc", "device-id"]), \
                            patch.object(subprocess, "Popen", return_value=process) as command, \
                            patch.object(subprocess, "run") as cleanup, \
                            patch.object(runner, "reports") as reports, \
                            contextlib.redirect_stdout(io.StringIO()):
                        self.assertEqual(runner.main(), exit_code)
                        command.assert_called_once()
                        self.assertEqual(command.call_args.args[0], ["just", "test", "ios", "--verbose"])
                        self.assertEqual(os.environ["IOS_TEST_AD_HOC_SIGNING"], "true")
                        self.assertIn("id=device-id", os.environ["IOS_TEST_DESTINATION"])
                        reports.assert_called_once()
                        cleanup.assert_called_once_with(["xcrun", "simctl", "delete", "device-id"], check=False)
                        self.assertEqual(Path("logs/ios-ci/test.log").read_text(), "test output\n")
                finally:
                    os.chdir(previous)

    def test_raw_result_retained_if_summary_fails(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            bundle = directory / "input.xcresult"
            bundle.mkdir()
            (bundle / "data").write_text("raw result")
            with patch.object(runner, "output", side_effect=RuntimeError("summary failed")):
                with self.assertRaises(RuntimeError):
                    runner.reports(bundle, directory)
            self.assertTrue((directory / "tests.xcresult.tar.gz").exists())

    def test_main_and_mr_cache_isolation(self):
        main = selector.pipeline("main")["steps"][0]
        mr = selector.pipeline("feature/tests")["steps"][0]
        self.assertNotEqual(main["cache"]["name"], mr["cache"]["name"])
        for job in (main, mr):
            self.assertEqual(job["agents"], {"queue": "macos-medium"})
            self.assertNotIn("secrets", job)
            self.assertEqual(job["concurrency"], 1)
            self.assertEqual(job["timeout_in_minutes"], 60)


if __name__ == "__main__":
    unittest.main()
