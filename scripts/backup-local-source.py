#!/usr/bin/env python3
"""Create and verify a versioned source snapshot, without running project code."""

import argparse
from datetime import datetime
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tarfile


BLOCKED_DIRECTORIES = {
    ".git", ".build", "build", "DerivedData", "node_modules", "Pods",
    "SourcePackages", "xcuserdata", "quarantine", "podcast-audio",
}
BLOCKED_SUFFIXES = {
    ".p8", ".p12", ".pfx", ".pem", ".key", ".cer", ".mobileprovision",
    ".certSigningRequest", ".ipa", ".o", ".a", ".dylib", ".so", ".exe", ".log",
}
BLOCKED_NAMES = {
    "Secrets.plist", "GoogleService-Info.plist", "serviceAccountKey.json",
    "secrets.json", "temp_auto_push.bat", "temp_interactive_push.bat",
}
CREDENTIAL_PATTERNS = tuple(re.compile(pattern) for pattern in (
    rb"-----BEGIN (?:RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----",
    rb"(?<![A-Za-z0-9])sk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{24,}",
    rb"AIza[0-9A-Za-z_-]{35}",
    rb"gh[pousr]_[A-Za-z0-9]{30,}",
    rb"github_pat_[A-Za-z0-9_]{40,}",
    rb'"private_key"\s*:\s*"[^"\r\n]{80,}"',
))


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def required_backup_space(captured):
    # Conservative uncompressed bound, PAX/manifest overhead, and space left
    # after completion. Preflight never relies on an assumed compression ratio.
    return (sum(len(value[0]) for value in captured.values())
            + len(captured) * 8192 + 16 * 1024 * 1024 + 1024 * 1024 * 1024)


def require_backup_space(parent, captured):
    existing = parent
    while not existing.exists():
        existing = existing.parent
    free = shutil.disk_usage(existing).free
    required = required_backup_space(captured)
    if free < required:
        raise RuntimeError(
            f"Not enough free disk space for a verified backup: "
            f"{free / 1_000_000_000:.2f} GB available, "
            f"{required / 1_000_000_000:.2f} GB required. No backup directory created."
        )


def write_source_archive(archive, captured):
    """A full independent archive, with no hardlinks or parent snapshots.

    Put identical content together so the standard-library XZ dictionary can
    compress repeated large delivery assets. Each path remains an independent
    regular tar member with its original mode and modification time.
    """
    expected = {name: sha256(value[0]) for name, value in captured.items()}
    for name in captured:
        relative = Path(name)
        if not relative.parts or relative.is_absolute() or ".." in relative.parts or str(relative) != name:
            raise RuntimeError("Unsafe archive path")
    with tarfile.open(archive, "x:xz", format=tarfile.PAX_FORMAT, preset=8) as output:
        for name in sorted(captured, key=lambda item: (expected[item], item)):
            data, mode, mtime = captured[name]
            info = tarfile.TarInfo("project/" + name)
            info.size, info.mode, info.mtime = len(data), mode, mtime
            output.addfile(info, io.BytesIO(data))
    os.chmod(archive, 0o600)
    with tarfile.open(archive, "r:xz") as saved:
        entries = saved.getmembers()
        if len(entries) != len(expected) or {entry.name for entry in entries} != {"project/" + name for name in expected}:
            raise RuntimeError("Archive file count mismatch")
        for entry in entries:
            name = entry.name.removeprefix("project/")
            if not entry.name.startswith("project/") or not entry.isfile() or name not in captured:
                raise RuntimeError("Archive member verification failed")
            data, mode, mtime = captured[name]
            if (entry.size, entry.mode, entry.mtime) != (len(data), mode, mtime):
                raise RuntimeError("Archive metadata verification failed")
            if sha256(saved.extractfile(entry).read()) != expected[name]:
                raise RuntimeError("Archive content verification failed")
    return expected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--label", default="before-edit", help="Short label for this snapshot")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9._-]{1,80}", args.label):
        parser.error("Label must use 1–80 letters, digits, dots, underscores or hyphens")

    root = Path(__file__).resolve().parents[1]

    def git(*arguments):
        return subprocess.check_output(["git", *arguments], cwd=root)

    if Path(os.fsdecode(git("rev-parse", "--show-toplevel")).strip()).resolve() != root:
        raise RuntimeError("Run only from this script's local Git checkout")
    status = git("status", "--porcelain=v1", "-z")
    head = git("rev-parse", "HEAD")
    branch = git("branch", "--show-current")
    paths = {
        os.fsdecode(path) for path in
        git("ls-files", "--cached", "--others", "--exclude-standard", "-z").split(b"\0") if path
    }
    gitlinks = {}
    for entry in git("ls-files", "--stage", "-z").split(b"\0"):
        if entry:
            metadata, name = entry.split(b"\t", 1)
            mode, commit, _ = metadata.decode().split()
            if mode == "160000":
                gitlinks[os.fsdecode(name)] = commit
    for name in (
        "AGENTS.override.md", "AGENTS.md", ".gitignore",
        "AproposMagazinev2.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
    ):
        if (root / name).is_file():
            paths.add(name)

    captured, excluded = {}, []
    for name in sorted(paths):
        relative = Path(name)
        if relative.is_absolute() or ".." in relative.parts:
            raise RuntimeError("Unsafe relative source path")
        reason = None
        if name in gitlinks:
            reason = "external reference Git link; commit recorded separately"
        elif any(part in BLOCKED_DIRECTORIES or "dropbox" in part.lower()
                 or "quarantine" in part.lower() for part in relative.parts):
            reason = "generated/cache/quarantine path"
        elif relative.name in BLOCKED_NAMES or relative.suffix in BLOCKED_SUFFIXES:
            reason = "credential, generated output, log or legacy temporary push tool"
        elif relative.name.startswith(".env") and relative.name not in {
            ".env.example", ".env.sample", ".env.template",
        }:
            reason = "environment credentials"
        elif "firebase-adminsdk" in relative.name.lower() and ".example." not in relative.name.lower():
            reason = "service-account credentials"
        if reason:
            excluded.append({"path": name, "reason": reason})
            continue
        path = root / relative
        if any((root / Path(*relative.parts[:index])).is_symlink()
               for index in range(1, len(relative.parts) + 1)):
            raise RuntimeError("Review symlink before backup: " + name)
        if not path.exists():
            excluded.append({"path": name, "reason": "deleted in working tree"})
            continue
        if not path.is_file() or root not in path.resolve().parents:
            raise RuntimeError("Not a regular source file inside this checkout: " + name)
        data = path.read_bytes()
        if any(pattern.search(data) for pattern in CREDENTIAL_PATTERNS):
            excluded.append({"path": name, "reason": "credential pattern; content omitted"})
            continue
        info = path.stat()
        captured[name] = (data, stat.S_IMODE(info.st_mode), int(info.st_mtime))

    project = (root / "AproposMagazinev2.xcodeproj/project.pbxproj").read_text()
    version = re.search(r"MARKETING_VERSION = ([0-9.]+);", project).group(1)
    build = re.search(r"CURRENT_PROJECT_VERSION = ([0-9]+);", project).group(1)
    now = datetime.now().astimezone()
    parent = (root.parent / "Backups" / root.name).resolve()
    if parent == root or root in parent.parents or any("dropbox" in part.lower() for part in parent.parts):
        raise RuntimeError("Backup destination must be outside checkout and Dropbox")
    require_backup_space(parent, captured)
    destination = parent / f"v{version}-build{build}_{now:%Y-%m-%d_%H-%M-%S%z}_{args.label}"
    destination.mkdir(parents=True, exist_ok=False, mode=0o700)
    os.chmod(destination, 0o700)
    archive = destination / "project-source.tar.xz"
    expected = write_source_archive(archive, captured)
    for name, checksum in expected.items():
        if sha256((root / name).read_bytes()) != checksum:
            raise RuntimeError("Source changed during backup; retry once editors are idle: " + name)
        info = (root / name).stat()
        if (stat.S_IMODE(info.st_mode), int(info.st_mtime)) != captured[name][1:]:
            raise RuntimeError("Source metadata changed during backup: " + name)
    if (git("status", "--porcelain=v1", "-z"), git("rev-parse", "HEAD"), git("branch", "--show-current")) != (status, head, branch):
        raise RuntimeError("Git state changed during backup; snapshot not verified")

    checksum = sha256(archive.read_bytes())
    manifest = {
        "created_at": now.isoformat(), "version": version, "build": build,
        "label": args.label, "source_checkout": str(root),
        "git_head": head.decode().strip(), "git_branch": branch.decode().strip(),
        "archive": archive.name, "archive_sha256": checksum,
        "archive_format": "tar.xz", "compression_preset": 8,
        "independent_full_snapshot": True,
        "logical_source_bytes": sum(len(value[0]) for value in captured.values()),
        "archive_bytes": archive.stat().st_size,
        "file_count": len(captured), "external_reference_gitlinks": gitlinks,
        "files": [{"path": name, "sha256": expected[name], "bytes": len(data), "mode": oct(mode)}
                  for name, (data, mode, _) in captured.items()],
        "excluded_from_git_candidate_set": excluded,
        "verification": "All archive entries verified; source hashes and Git state unchanged after creation.",
    }
    metadata = {
        "manifest.json": json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
        "SHA256SUMS": checksum + "  " + archive.name + "\n",
        "git-status.txt": git("status", "--short").decode(),
        "README.txt": (
            f"Verified local source snapshot: version {version}, build {build}.\n"
            "Includes modified/untracked source, assets, tests, docs and current lockfile.\n"
            "Full standalone tar.xz archive: no parent backup or shared hardlinks required.\n"
            "Credentials, Git history, builds/caches/logs and external Git checkouts excluded.\n"
            "See manifest.json for included/excluded files. Verify SHA256SUMS before recovery.\n"
            "Extract only into a new empty local directory after review, never over the checkout.\n"
            "Verification does not require executing scripts, installing dependencies, or starting services.\n"
        ),
    }
    for name, content in metadata.items():
        path = destination / name
        path.write_text(content)
        os.chmod(path, 0o600)
    print(json.dumps({"backup": str(destination), "version": version, "build": build,
                      "archive": archive.name, "archive_bytes": archive.stat().st_size,
                      "verified_files": len(captured), "archive_sha256": checksum}, indent=2))


if __name__ == "__main__":
    main()
