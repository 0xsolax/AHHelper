"""Run the addon's Lua 5.1 tests. Operator: Solazhu."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / ".tools" / "python"))
from lupa.lua51 import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
lua.globals().PROJECT_ROOT = ROOT.as_posix()
lua.execute((ROOT / "tests" / "test_addon.lua").read_text(encoding="utf-8"))
lua = LuaRuntime(unpack_returned_tuples=True)
lua.globals().PROJECT_ROOT = ROOT.as_posix()
lua.execute((ROOT / "tests" / "test_ui.lua").read_text(encoding="utf-8"))
lua = LuaRuntime(unpack_returned_tuples=True)
lua.globals().PROJECT_ROOT = ROOT.as_posix()
lua.execute((ROOT / "tests" / "test_history.lua").read_text(encoding="utf-8"))
