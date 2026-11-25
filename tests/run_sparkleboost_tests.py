"""Run isolated SparkleBoost lifecycle, visual and settings checks with Lua 5.1."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / ".tools" / "python"))
from lupa.lua51 import LuaRuntime

def runtime():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().PROJECT_ROOT = ROOT.as_posix()
    lua.execute((ROOT / "tests" / "sparkleboost_mock.lua").read_text(encoding="utf-8"))
    lua.execute((ROOT / "tests" / "test_sparkleboost.lua").read_text(encoding="utf-8"))
    return lua

compiler = LuaRuntime(unpack_returned_tuples=True)
for path in (ROOT / "SparkleBoost").glob("*.lua"):
    compiler.execute("assert(loadstring(...))", path.read_text(encoding="utf-8"))
print("PASS Lua 5.1 syntax: all addon files")
names = sorted(runtime().globals().TESTS.keys())
failed = 0
for name in names:
    try:
        runtime().globals().TESTS[name]()
        print("PASS", name)
    except Exception as error:
        failed += 1
        print("FAIL", name, "\n", error)
print(f"{len(names) - failed}/{len(names)} scenarios passed")
sys.exit(bool(failed))
