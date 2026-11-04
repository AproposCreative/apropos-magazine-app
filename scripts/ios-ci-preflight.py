#!/usr/bin/env python3
"""Read-only checks for the approved iOS toolchain and existing package lock."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import urlsplit
from uuid import UUID

LOCK_PATH = "AproposMagazinev2.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"


def verify_lockfile(path, expected_hash, expected_count):
    if path.is_symlink() or any(parent.is_symlink() for parent in path.parents) or not path.is_file():
        raise ValueError("The shared Package.resolved must exist as a regular file")
    data = path.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if digest != expected_hash:
        raise ValueError("Package.resolved differs from the reviewed pin policy; no resolution or update attempted")
    value = json.loads(data)
    if not isinstance(value, dict) or type(value.get("version")) is not int or value["version"] != 3:
        raise ValueError("Unsupported Package.resolved schema")
    pins = value.get("pins")
    if not isinstance(pins, list) or len(pins) != expected_count:
        raise ValueError("Package pin count differs from the reviewed graph")
    identities = set()
    for pin in pins:
        if not isinstance(pin, dict):
            raise ValueError("Invalid package pin")
        identity = pin.get("identity")
        if not isinstance(identity, str) or not identity or identity in identities:
            raise ValueError("Invalid or repeated package identity")
        identities.add(identity)
        if not isinstance(pin.get("location"), str):
            raise ValueError("Invalid package location")
        url = urlsplit(pin["location"])
        if pin.get("kind") != "remoteSourceControl" or url.scheme != "https" or url.netloc != "github.com":
            raise ValueError("Unreviewed package source")
        state = pin.get("state", {})
        if not isinstance(state, dict) or not isinstance(state.get("revision"), str) or not re.fullmatch(r"[0-9a-f]{40}", state["revision"]):
            raise ValueError("Package revision must be a concrete commit")
        if not isinstance(state.get("version"), str) or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?", state["version"]):
            raise ValueError("Package version must be concrete")
    return digest


def verify_xcode(output, policy):
    expected = f"Xcode {policy['xcodeVersion']}\nBuild version {policy['xcodeBuild']}"
    if output.strip() != expected:
        raise ValueError("Selected Xcode does not match the reviewed version/build")


def select_simulator(value, policy, requested=None):
    if not isinstance(value, dict) or not isinstance(value.get("devices"), dict):
        raise ValueError("Simulator inventory is unavailable")
    candidates = [device for device in value["devices"].get(policy["simulatorRuntime"], [])
                  if device.get("isAvailable") is True and device.get("name") == policy["simulatorName"]]
    if requested:
        candidates = [device for device in candidates if device.get("udid") == requested]
    if len(candidates) != 1:
        raise ValueError("Expected one existing available iPhone simulator for the pinned runtime; no device created/reset")
    identifier = candidates[0].get("udid", "")
    if not isinstance(identifier, str) or str(UUID(identifier)).lower() != identifier.lower():
        raise ValueError("Invalid simulator identifier")
    return identifier


def verify_summary(value, policy):
    count = value.get("totalTestCount")
    if (value.get("result") != "Passed" or type(count) is not int
            or count < policy["minimumTestCount"] or value.get("passedTests") != count
            or value.get("failedTests") != 0 or value.get("skippedTests") != 0
            or value.get("expectedFailures") != 0 or value.get("runtimeWarnings") != []):
        raise ValueError("Native result did not satisfy the full reviewed unit-test gate")


def main():
    root = Path(__file__).resolve().parents[1]
    policy = json.loads((root / "scripts/ios-ci-policy.json").read_text())
    if len(sys.argv) == 3 and sys.argv[1] == "result":
        verify_summary(json.loads(Path(sys.argv[2]).read_text()), policy)
        return
    digest = verify_lockfile(root / LOCK_PATH, policy["packageResolvedSHA256"], policy["packagePinCount"])
    if sys.argv[1:] == ["lock"]:
        print(digest)
        return
    if sys.argv[1:]:
        raise ValueError("Usage: ios-ci-preflight.py [lock | result SUMMARY_JSON]")
    verify_xcode(subprocess.check_output(["xcodebuild", "-version"], text=True), policy)
    devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"], text=True))
    identifier = select_simulator(devices, policy, os.environ.get("APROPOS_SIMULATOR_UDID"))
    print(f"platform=iOS Simulator,id={identifier}")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"iOS preflight failed: {error}", file=sys.stderr)
        sys.exit(1)
