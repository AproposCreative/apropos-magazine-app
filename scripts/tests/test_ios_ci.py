"""Exercise the actual CI entry point using disposable sources and fake tools."""
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("ios_ci_preflight", ROOT / "scripts/ios-ci-preflight.py")
preflight = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(preflight)
POLICY = json.loads((ROOT / "scripts/ios-ci-policy.json").read_text())
ID = "C78009BF-2E7B-4E23-B977-8AA22B98FB45"


class IOSCITests(unittest.TestCase):
    def test_real_lockfile_is_exactly_the_reviewed_graph(self):
        digest = preflight.verify_lockfile(ROOT / preflight.LOCK_PATH,
            POLICY["packageResolvedSHA256"], POLICY["packagePinCount"])
        self.assertEqual(digest, POLICY["packageResolvedSHA256"])

    def test_pin_changes_invalid_sources_and_duplicate_identities_fail_closed(self):
        value = json.loads((ROOT / preflight.LOCK_PATH).read_text())
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory).resolve() / "Package.resolved"
            for kind in ["rewrite", "duplicate", "unversioned", "credential", "missing", "symlink"]:
                with self.subTest(kind=kind):
                    changed = copy.deepcopy(value)
                    if kind == "duplicate": changed["pins"][1]["identity"] = changed["pins"][0]["identity"]
                    if kind == "unversioned": changed["pins"][0]["state"]["revision"] = "main"
                    if kind == "credential": changed["pins"][0]["location"] = "https://user:password@github.com/example/repo"
                    data = json.dumps(changed).encode(); path.write_bytes(data)
                    digest = hashlib.sha256(data).hexdigest()
                    if kind == "rewrite": digest = POLICY["packageResolvedSHA256"]
                    if kind == "missing": path.unlink()
                    if kind == "symlink":
                        target = path.parent / "target"; target.write_bytes(data); path.unlink(); path.symlink_to(target)
                    with self.assertRaises(ValueError): preflight.verify_lockfile(path, digest, POLICY["packagePinCount"])
                    if path.is_symlink(): path.unlink()

    def test_only_one_existing_available_simulator_on_pinned_runtime_is_allowed(self):
        device = {"name": POLICY["simulatorName"], "udid": ID, "isAvailable": True}
        inventory = {"devices": {POLICY["simulatorRuntime"]: [device]}}
        self.assertEqual(preflight.select_simulator(inventory, POLICY), ID)
        for value in [ {"devices": {}}, {"devices": {POLICY["simulatorRuntime"]: [device, device]}},
            {"devices": {"other-runtime": [device]}},
            {"devices": {POLICY["simulatorRuntime"]: [{**device, "isAvailable": False}]}},
            {"devices": {POLICY["simulatorRuntime"]: [{**device, "udid": "-"*36}]}}, {"devices": None} ]:
            with self.subTest(value=value), self.assertRaises(ValueError): preflight.select_simulator(value, POLICY)
        with self.assertRaises(ValueError): preflight.select_simulator(inventory, POLICY, requested="foreign-id")

    def test_xcode_and_full_unit_summary_are_required(self):
        preflight.verify_xcode("Xcode 27.1\nBuild version 27A9275\n", POLICY)
        with self.assertRaises(ValueError): preflight.verify_xcode("Xcode 27.2\nBuild version newer", POLICY)
        good = {"result": "Passed", "totalTestCount": 3648, "passedTests": 3648,
                "failedTests": 0, "skippedTests": 0, "expectedFailures": 0, "runtimeWarnings": []}
        preflight.verify_summary(good, POLICY)
        for patch in [{"totalTestCount": 0, "passedTests": 0}, {"skippedTests": 1},
                      {"failedTests": 1}, {"runtimeWarnings": ["warning"]}, {"result": "Failed"}]:
            with self.subTest(patch=patch), self.assertRaises(ValueError): preflight.verify_summary({**good, **patch}, POLICY)

    def test_gitignore_exposes_only_the_shared_lockfile(self):
        prefix = "AproposMagazinev2.xcodeproj/project.xcworkspace/"
        protected = [prefix + "xcuserdata/private.xcuserdatad", prefix + "contents.xcworkspacedata",
                     prefix + "xcshareddata/WorkspaceSettings.xcsettings", prefix + "xcshareddata/swiftpm/configuration/private.json",
                     "Other.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
                     "AproposMagazinev2/GoogleService-Info.plist", "AproposMagazinev2/Resources/Secrets.plist"]
        paths = [preflight.LOCK_PATH] + protected
        result = subprocess.run(["git", "check-ignore", "--no-index", "--stdin", "-z"], cwd=ROOT,
            input=("\0".join(paths) + "\0").encode(), capture_output=True, check=False)
        self.assertIn(result.returncode, [0, 1])
        self.assertEqual(set(result.stdout.decode().strip("\0").split("\0")), set(protected))

    def test_actual_workflow_yaml_uses_valid_contexts_and_the_reviewed_entry_point(self):
        # Psych is the installed Ruby standard-library YAML parser; no package
        # installer or downloaded workflow validator is needed for this check.
        parsed = subprocess.check_output(["ruby", "-ryaml", "-rjson", "-e",
            "puts JSON.generate(YAML.safe_load(File.read(ARGV.fetch(0))))",
            str(ROOT / ".github/workflows/verify.yml")], text=True)
        workflow = json.loads(parsed)
        self.assertEqual(workflow["permissions"], {"contents": "read"})
        for job in workflow["jobs"].values():
            for value in job.get("env", {}).values():
                self.assertNotIn("${{ runner.", str(value), "runner context is available at step env, not job env")
        ios = workflow["jobs"]["ios"]
        self.assertEqual(ios["runs-on"], "xcode-27")
        self.assertEqual(ios["needs"], "backend")
        self.assertEqual(ios["env"]["DEVELOPER_DIR"], "/Applications/Xcode_" + POLICY["xcodeVersion"] + ".app/Contents/Developer")
        self.assertLessEqual(ios["timeout-minutes"], 40)
        test_step = next(step for step in ios["steps"] if step.get("run") == "bash scripts/verify-ios-ci.sh")
        result_path = test_step["env"]["APROPOS_XCRESULT_PATH"]
        self.assertEqual(result_path, "${{ runner.temp }}/AproposNative.xcresult")
        upload = next(step for step in ios["steps"] if step.get("uses") == "actions/upload-artifact@v4")
        self.assertEqual(upload["if"], "always()")
        self.assertEqual(upload["with"]["path"].splitlines(), [result_path, result_path + ".summary.json"])
        self.assertEqual(upload["with"]["retention-days"], 7)
        for step in ios["steps"]:
            if step.get("uses") == "actions/checkout@v4": self.assertFalse(step["with"]["persist-credentials"])

    def run_entry(self, **settings):
        temporary = tempfile.TemporaryDirectory(); self.addCleanup(temporary.cleanup)
        root = Path(temporary.name).resolve(); scripts = root / "scripts"; scripts.mkdir()
        for name in ["verify-ios-ci.sh", "ios-ci-preflight.py", "ios-ci-policy.json"]:
            shutil.copy2(ROOT / "scripts" / name, scripts / name)
        lock = root / preflight.LOCK_PATH; lock.parent.mkdir(parents=True)
        shutil.copy2(ROOT / preflight.LOCK_PATH, lock)
        tools = root / "fake-tools"; tools.mkdir(); trace = root / "build-args.json"
        fake = '''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
tool=Path(sys.argv[0]).name; args=sys.argv[1:]; root=Path(os.environ['FIXTURE_ROOT'])
if tool=='node': sys.exit(0)
if tool=='xcodebuild' and args==['-version']:
 print('Xcode '+os.environ.get('FAKE_VERSION','27.1')+'\\nBuild version 27A9275'); sys.exit(0)
if tool=='xcrun' and args[:2]==['simctl','list']:
 print(json.dumps({'devices':{'com.apple.CoreSimulator.SimRuntime.iOS-27-0':[{'name':'iPhone 18 Pro','udid':'C78009BF-2E7B-4E23-B977-8AA22B98FB45','isAvailable':True}]}})); sys.exit(0)
if tool=='xcrun' and args[0]=='xcresulttool':
 count=0 if os.environ.get('FAKE_EMPTY') else 3648
 print(json.dumps({'result':'Passed','totalTestCount':count,'passedTests':count,'failedTests':0,'skippedTests':0,'expectedFailures':0,'runtimeWarnings':[]})); sys.exit(0)
assert tool=='xcodebuild' and args[-1]=='test', (tool,args)
(root/'build-args.json').write_text(json.dumps({'args':args,'upload':os.environ.get('APROPOS_CRASHLYTICS_UPLOAD')}))
if os.environ.get('FAKE_REWRITE'):
 with (root/'AproposMagazinev2.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved').open('ab') as file: file.write(b'\\n')
status=int(os.environ.get('FAKE_STATUS','0'))
if status: sys.exit(status)
app=Path(args[args.index('-derivedDataPath')+1])/'Build/Products/Debug-iphonesimulator/Apropos.app'; app.mkdir(parents=True)
if os.environ.get('FAKE_SECRET'): (app/'Secrets.plist').write_text('fixture only')
Path(args[args.index('-resultBundlePath')+1]).mkdir()
'''
        for name in ["xcodebuild", "xcrun", "node"]:
            path = tools / name; path.write_text(fake); path.chmod(0o755)
        result_path = root / "Test Results.xcresult"
        if settings.pop("existing", False): result_path.mkdir()
        env = {**os.environ, "PATH": str(tools) + os.pathsep + os.environ["PATH"],
               "FIXTURE_ROOT": str(root), "TMPDIR": str(root), "APROPOS_XCRESULT_PATH": str(result_path)}
        env.pop("APROPOS_SIMULATOR_UDID", None)
        env.update(settings)
        result = subprocess.run(["bash", str(scripts / "verify-ios-ci.sh")], env=env, capture_output=True, text=True)
        return root, result, trace

    def test_entry_point_runs_unsigned_full_tests_and_preserves_failure_exit(self):
        root, result, trace = self.run_entry()
        self.assertEqual(result.returncode, 0, result.stderr)
        command = json.loads(trace.read_text()); args = command["args"]
        for flag in ["-disableAutomaticPackageResolution", "-onlyUsePackageVersionsFromResolvedFile", "-skipPackageUpdates",
                     "CODE_SIGNING_ALLOWED=NO", "EXCLUDED_SOURCE_FILE_NAMES=Secrets.plist GoogleService-Info.plist"]:
            self.assertIn(flag, args)
        self.assertEqual(args[args.index("-only-testing:AproposMagazineTests")], "-only-testing:AproposMagazineTests")
        self.assertEqual(args[args.index("-parallel-testing-enabled")+1], "NO")
        self.assertEqual(args[args.index("-collect-test-diagnostics")+1], "never")
        self.assertEqual(command["upload"], "NO")
        self.assertNotIn("-allowProvisioningUpdates", args); self.assertNotIn("-skipPackagePluginValidation", args)
        _, failed, _ = self.run_entry(FAKE_STATUS="65")
        self.assertEqual(failed.returncode, 65)

    def test_wrong_tools_existing_results_rewritten_pins_secrets_and_empty_results_fail(self):
        for settings in [{"FAKE_VERSION": "27.2"}, {"existing": True}, {"FAKE_REWRITE": "1"}, {"FAKE_SECRET": "1"}, {"FAKE_EMPTY": "1"}]:
            with self.subTest(settings=settings):
                _, result, trace = self.run_entry(**settings)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                if settings.get("FAKE_VERSION") or settings.get("existing"): self.assertFalse(trace.exists())


if __name__ == "__main__":
    unittest.main()
