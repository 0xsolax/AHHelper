"""Run the standalone AddonCPU tests with Lua 5.1. Operator: Solazhu."""
import argparse
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / ".tools" / "python"))
from lupa.lua51 import LuaRuntime

parser = argparse.ArgumentParser()
parser.add_argument("--addon-dir", type=Path, default=ROOT / "AddonCPU")
args = parser.parse_args()
lua = LuaRuntime(unpack_returned_tuples=True)
lua.globals().PROJECT_ROOT = ROOT.as_posix()
lua.globals().ADDON_DIR = args.addon_dir.resolve().as_posix()
lua.execute((ROOT / "tests" / "test_addon_cpu.lua").read_text(encoding="utf-8"))
