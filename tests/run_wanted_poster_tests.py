"""Exercise the WantedPoster TOC and user-facing flows with Lua 5.1."""

from pathlib import Path
import argparse
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / ".tools" / "python"))
from lupa.lua51 import LuaRuntime


def runtime(addon_root=ROOT / "WantedPoster"):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().ADDON_ROOT = addon_root.resolve().as_posix()
    lua.execute((ROOT / "tests" / "wanted_poster_mock.lua").read_text(encoding="utf-8"))
    return lua


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("addon_root", type=Path, nargs="?", default=ROOT / "WantedPoster")
    folder = parser.parse_args().addon_root
    source = (ROOT / "tests" / "test_wanted_poster.lua").read_text(encoding="utf-8")
    tests = runtime(folder)
    tests.execute(source)
    names = sorted(tests.globals().TESTS.keys())
    failures = 0
    for name in names:
        lua = runtime(folder)
        lua.execute(source)
        try:
            lua.globals().TESTS[name]()
            print("PASS", name)
        except Exception as error:
            failures += 1
            print("FAIL", name, error)
    print(f"{len(names) - failures}/{len(names)} scenarios passed")
    return bool(failures)


if __name__ == "__main__":
    sys.exit(main())
