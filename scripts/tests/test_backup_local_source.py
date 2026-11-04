"""Disposable data only: no app, existing backup, credentials, Git or service use."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import random
import stat
import tarfile
import tempfile
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location(
    "backup_local_source", Path(__file__).resolve().parents[1] / "backup-local-source.py")
backup = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(backup)


class BackupSourceTests(unittest.TestCase):
    def test_full_archive_preserves_paths_modes_times_and_independent_files(self):
        block = random.Random(165).randbytes(1024 * 1024)
        captured = {"one/data": (block, 0o600, 1), "two/data": (block, 0o640, 2),
                    "three/data": (block, 0o644, 3), "empty/a": (b"", 0o600, 4),
                    "empty/b": (b"", 0o644, 5), "space and æøå": (b"text", 0o640, 6)}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); archive = root / "source.tar.xz"
            expected = backup.write_source_archive(archive, captured)
            self.assertEqual(set(expected), set(captured))
            self.assertEqual(stat.S_IMODE(archive.stat().st_mode), 0o600)
            with tarfile.open(archive, "r:*") as saved:
                members = saved.getmembers()
                self.assertEqual({x.name for x in members}, {"project/" + x for x in captured})
                self.assertTrue(all(x.isfile() and not x.islnk() and not x.issym() for x in members))
                for entry in members:
                    data, mode, mtime = captured[entry.name.removeprefix("project/")]
                    self.assertEqual((saved.extractfile(entry).read(), entry.size, entry.mode, entry.mtime),
                                     (data, len(data), mode, mtime))
                # Only our verified synthetic regular members are extracted.
                saved.extractall(root / "restored")
            a, b = root / "restored/project/one/data", root / "restored/project/two/data"
            self.assertNotEqual(a.stat().st_ino, b.stat().st_ino)
            a.write_bytes(b"an independent future edit")
            self.assertEqual(b.read_bytes(), block)
            # Compare complete ordinary gzip, not a hardlink/delta baseline.
            gzip_path = root / "comparison.tar.gz"
            with tarfile.open(gzip_path, "x:gz") as saved:
                for name, (data, mode, mtime) in captured.items():
                    entry = tarfile.TarInfo("project/" + name)
                    entry.size, entry.mode, entry.mtime = len(data), mode, mtime
                    saved.addfile(entry, io.BytesIO(data))
            self.assertLess(archive.stat().st_size, gzip_path.stat().st_size * 0.6)

    def test_unsafe_paths_are_rejected_before_archive_creation(self):
        with tempfile.TemporaryDirectory() as directory:
            for name in ["", ".", "../escape", "/absolute", "a/../b", "a//b", "a/./b"]:
                archive = Path(directory) / "not-created.tar.xz"
                with self.subTest(name=name), self.assertRaisesRegex(RuntimeError, "Unsafe archive path"):
                    backup.write_source_archive(archive, {name: (b"x", 0o600, 1)})
                self.assertFalse(archive.exists())

    def run_main_fixture(self, *, free=10**12, mutate=None, git_changed=False, writer_error=False, verifier_error=False):
        """Use main's actual selection/write/verification with a fake Git read API."""
        temporary = tempfile.TemporaryDirectory(); self.addCleanup(temporary.cleanup)
        root = (Path(temporary.name) / "source").resolve(); (root / "scripts").mkdir(parents=True)
        project = root / "AproposMagazinev2.xcodeproj/project.pbxproj"
        project.parent.mkdir(); project.write_text("MARKETING_VERSION = 1.155.0;\nCURRENT_PROJECT_VERSION = 165;\n")
        note = root / "note.txt"; note.write_text("source data"); note.chmod(0o640)
        names = ["note.txt", str(project.relative_to(root))]
        status_reads = 0

        def git(args, cwd):
            nonlocal status_reads
            self.assertEqual(cwd, root)
            command = args[1:]
            if command == ["rev-parse", "--show-toplevel"]: return str(root).encode() + b"\n"
            if command == ["status", "--porcelain=v1", "-z"]:
                status_reads += 1
                return b"different" if git_changed and status_reads > 1 else b"?? note.txt\0"
            if command == ["rev-parse", "HEAD"]: return b"f" * 40 + b"\n"
            if command == ["branch", "--show-current"]: return b"fixture\n"
            if command == ["ls-files", "--cached", "--others", "--exclude-standard", "-z"]:
                return ("\0".join(names) + "\0").encode()
            if command == ["ls-files", "--stage", "-z"]: return b""
            if command == ["status", "--short"]: return b"?? note.txt\n"
            self.fail("Unexpected Git operation: " + repr(command))

        original = backup.write_source_archive

        def write(*args):
            if writer_error: raise OSError("injected storage failure")
            result = original(*args)
            if mutate == "bytes": note.write_text("changed during the archive write")
            if mutate == "mode": note.chmod(0o600)
            if mutate == "mtime": os.utime(note, (note.stat().st_atime, note.stat().st_mtime + 2))
            return result

        original_open = backup.tarfile.open

        def archive_open(path, mode, **kwargs):
            if verifier_error and mode == "r:xz": raise tarfile.ReadError("injected verification failure")
            return original_open(path, mode, **kwargs)

        output = io.StringIO(); error = None
        with patch.object(backup, "__file__", str(root / "scripts/backup-local-source.py")), \
                patch.object(backup.subprocess, "check_output", side_effect=git), \
                patch.object(backup.shutil, "disk_usage") as disk, \
                patch.object(backup, "write_source_archive", side_effect=write), \
                patch.object(backup.tarfile, "open", side_effect=archive_open), \
                patch("sys.argv", ["backup-local-source.py", "--label", "fixture"]), \
                contextlib.redirect_stdout(output):
            disk.return_value.free = free
            try: backup.main()
            except (RuntimeError, OSError, tarfile.TarError) as caught: error = caught
        return root, output.getvalue(), error

    def test_main_creates_verified_standalone_archive_and_preserves_output_contract(self):
        root, output, error = self.run_main_fixture()
        self.assertIsNone(error)
        receipt = json.loads(output)
        for key in ["backup", "version", "build", "verified_files", "archive_sha256"]:
            self.assertIn(key, receipt)
        destination = Path(receipt["backup"])
        manifest = json.loads((destination / "manifest.json").read_text())
        self.assertTrue(manifest["independent_full_snapshot"])
        self.assertEqual(manifest["archive_format"], "tar.xz")
        self.assertEqual(manifest["file_count"], 2)
        self.assertEqual(manifest["archive"], "project-source.tar.xz")
        self.assertEqual(receipt["archive_sha256"], backup.sha256((destination / manifest["archive"]).read_bytes()))
        self.assertEqual((destination / "SHA256SUMS").read_text(), receipt["archive_sha256"] + "  project-source.tar.xz\n")
        # The archive remains readable after removing the synthetic original.
        (root / "note.txt").unlink()
        with tarfile.open(destination / manifest["archive"], "r:*") as saved:
            self.assertEqual(saved.extractfile("project/note.txt").read(), b"source data")

    def test_low_space_creates_no_destination_or_success_receipt(self):
        root, output, error = self.run_main_fixture(free=0)
        self.assertIsInstance(error, RuntimeError)
        self.assertIn("Not enough free disk space", str(error))
        self.assertEqual(output, "")
        self.assertFalse((root.parent / "Backups").exists())

    def test_source_byte_and_mode_changes_cannot_become_verified(self):
        for mutation in ["bytes", "mode", "mtime"]:
            with self.subTest(mutation=mutation):
                root, output, error = self.run_main_fixture(mutate=mutation)
                self.assertIsInstance(error, RuntimeError); self.assertEqual(output, "")
                self.assertFalse(list((root.parent / "Backups").rglob("manifest.json")))

    def test_git_change_and_storage_failure_cannot_become_verified(self):
        for kwargs in [{"git_changed": True}, {"writer_error": True}, {"verifier_error": True}]:
            with self.subTest(kwargs=kwargs):
                root, output, error = self.run_main_fixture(**kwargs)
                self.assertIsNotNone(error); self.assertEqual(output, "")
                self.assertFalse(list((root.parent / "Backups").rglob("manifest.json")))


if __name__ == "__main__":
    unittest.main()
