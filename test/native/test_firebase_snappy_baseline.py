import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "baseline", Path(__file__).resolve().parents[2] / "tool/firebase_snappy_baseline.py")
baseline = importlib.util.module_from_spec(spec)
spec.loader.exec_module(baseline)


def member(name, data=b""):
    header = (f"{name:<16}{0:<12}{0:<6}{0:<6}{0:<8}{len(data):<10}`\n").encode()
    return header + data + (b"\n" if len(data) % 2 else b"")


class ArchiveTests(unittest.TestCase):
    def parse(self, contents):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "firebase.lib"
            archive.write_bytes(contents)
            return baseline.snappy_members(archive)

    def test_removes_only_snappy_implementation_with_coff_long_names(self):
        names = ["hash_snappy.dir_Release_snappy.obj",
                 "hash_snappy.dir_Release_snappy_stubs_internal.obj",
                 "hash_snappy.dir_Release_snappy_sinksource.obj",
                 "hash_snappy.dir_Release_snappy_c.obj",
                 "firestore_snappy_compressor.obj", "firebase_app.obj"]
        table = b""
        entries = b""
        for name in names:
            entries += member(f"/{len(table)}", b"object")
            table += name.encode() + b"/\n"
        archive = b"!<arch>\n" + member("/", b"index") + member("//", table) + entries
        self.assertEqual(self.parse(archive), names[:4])

    def test_sdk_without_snappy_stays_unchanged(self):
        self.assertEqual(self.parse(b"!<arch>\n" + member("other.obj/", b"x")), [])

    def test_invalid_archives_fail_instead_of_silently_skipping(self):
        for archive in [b"invalid", b"!<arch>\nshort", b"!<arch>\n" + member("/123")]:
            with self.subTest(archive=archive), self.assertRaises(ValueError):
                self.parse(archive)


if __name__ == "__main__":
    unittest.main()
