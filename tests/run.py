"""Offline Haxe regression tests using host doubles; not native game validation."""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--haxe", default="haxe")
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="compass-checks-") as directory:
    runtime = Path(directory)
    shutil.copytree(root / "tests" / "fixtures", runtime, dirs_exist_ok=True)
    shutil.copytree(root / "src", runtime / "mods" / "gate_compass")
    for name in ("GoalChecks", "ClockChecks", "CompassChecks", "GeometryChecks", "PaletteChecks", "HeadingChecks", "ProbeChecks", "PanelChecks", "SkinChecks", "HoverChecks", "VisibilityChecks", "PauseChecks"):
        subprocess.run([args.haxe, "-cp", str(runtime), "-main", name, "--interp"], check=True)

    shutil.copytree(root / "tests" / "entry_host", runtime, dirs_exist_ok=True)
    subprocess.run([args.haxe, "-cp", str(runtime), "-main", "EntryTypeChecks", "--no-output"], check=True)
    print("PASS: full mod entry and rendering/UI source type-check against host adapters", flush=True)

    subprocess.run([args.haxe, "-cp", str(runtime), "-main", "HeadingFlowChecks", "--interp"], check=True)
    subprocess.run([args.haxe, "-cp", str(runtime), "-main", "PerformanceChecks", "--interp"], check=True)
    subprocess.run([args.haxe, "-cp", str(runtime), "-main", "RouteHeadChecks", "--interp"], check=True)
