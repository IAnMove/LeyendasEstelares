#!/usr/bin/env python3
"""Export configured desktop/web releases and an Android debug APK with Godot."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TARGETS = {"linux": "Linux", "windows": "Windows", "macos": "macOS", "web": "Web", "android": "Android"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("targets", nargs="*", default=list(TARGETS), help="linux windows macos web android (default: all)")
    parser.add_argument("--godot", default=os.environ.get("GODOT", "godot"), help="Godot 4 executable, or set GODOT")
    args = parser.parse_args()
    if not shutil.which(args.godot):
        parser.error("Godot not found. Pass --godot /path/to/Godot or set GODOT.")
    for target in args.targets:
        if target not in TARGETS:
            parser.error(f"Unknown target: {target}")
    command = [args.godot, "--headless", "--path", str(ROOT)]
    (ROOT / "build").mkdir(exist_ok=True)
    (ROOT / "build" / ".gdignore").touch()
    # Large native templates can exceed RAM-backed /tmp quotas. Keep export
    # scratch files beside the builds; TemporaryDirectory cleans only our files.
    with tempfile.TemporaryDirectory(prefix="export-", dir=ROOT / "build") as scratch:
        env = os.environ.copy()
        env["TMPDIR"] = scratch
        env["JAVA_TOOL_OPTIONS"] = env.get("JAVA_TOOL_OPTIONS", "") + f' -Djava.io.tmpdir="{scratch}"'
        subprocess.run(command + ["--editor", "--import", "--quit"], check=True, env=env)
        for target in args.targets:
            out = ROOT / "build" / target
            out.mkdir(parents=True, exist_ok=True)
            mode = "--export-debug" if target == "android" else "--export-release"
            subprocess.run(command + [mode, TARGETS[target]], check=True, env=env)
            if target == "macos":
                # Export .app directly: Godot's ZIP exporter stages the entire
                # bundle in its own system temporary directory.
                shutil.make_archive(str(out / "leyendas-estelares"), "zip", out, "Leyendas Estelares.app")
            shutil.copy2(ROOT / "LICENSE", out / "LICENSE")
            shutil.copy2(ROOT / "art" / "fonts" / "LICENSE", out / "FONTS-LICENSE.txt")
            print(f"Exported {target}: {out}", flush=True)


if __name__ == "__main__":
    main()
