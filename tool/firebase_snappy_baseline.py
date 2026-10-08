"""Copy an MSVC Firebase archive with only its bundled Snappy objects removed.

The package cache and downloaded SDK are never edited in place. CMake links
Snappy built from source in their place. This also handles COFF long names.
"""
import argparse
from pathlib import Path
import re
import subprocess


def snappy_members(archive: Path) -> list[str]:
    members = []
    with archive.open("rb") as stream:
        if stream.read(8) != b"!<arch>\n":
            raise ValueError(f"Not a COFF archive: {archive}")
        long_names = b""
        while header := stream.read(60):
            if len(header) != 60 or header[58:] != b"`\n":
                raise ValueError("Invalid archive member header")
            size = int(header[48:58])
            name = header[:16].decode("ascii").strip()
            if name == "//":
                long_names = stream.read(size)
            else:
                stream.seek(size, 1)
                if name.startswith("/") and name[1:].isdigit():
                    offset = int(name[1:])
                    if offset >= len(long_names):
                        raise ValueError("Invalid long-name offset")
                    name = re.split(b"/\n|\x00", long_names[offset:], maxsplit=1)[0].decode("utf-8")
                else:
                    name = name.rstrip("/")
                if re.search(r"(?:^|[/\\_])snappy(?:_stubs_internal|_sinksource|_c)?\.obj$", name):
                    members.append(name)
            if size % 2:
                stream.seek(1, 1)
    return list(dict.fromkeys(members))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lib-tool", required=True)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if args.input.resolve() == args.output.resolve():
        raise ValueError("Refusing to edit the original SDK archive")
    members = snappy_members(args.input)
    if not members:
        print("UNCHANGED")
        return
    args.output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([args.lib_tool, "/NOLOGO", str(args.input),
                    f"/OUT:{args.output}", *(f"/REMOVE:{name}" for name in members)],
                   check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if snappy_members(args.output):
        raise ValueError("Bundled Snappy objects remain in copied SDK archive")
    print("UPDATED")


if __name__ == "__main__":
    main()
