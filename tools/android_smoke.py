#!/usr/bin/env python3
"""Install and inspect the native APK on an explicitly selected Android device."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = "org.leyendasestelares.game"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", required=True, help="Exact serial from adb devices")
    parser.add_argument("--adb", default=os.environ.get("ADB", "adb"))
    parser.add_argument("--apk", type=Path, default=ROOT / "build/android/leyendas-estelares.apk")
    parser.add_argument("--out", type=Path, default=ROOT / "build/android/validation")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    command = [args.adb, "-s", args.serial]

    def adb(*words, binary=False):
        result = subprocess.run(command + list(words), check=True, capture_output=True)
        return result.stdout if binary else result.stdout.decode().strip()

    adb("install", "-r", str(args.apk.resolve()))
    adb("shell", "am", "force-stop", PACKAGE)
    activity = adb("shell", "cmd", "package", "resolve-activity", "--brief", PACKAGE).splitlines()[-1]
    started = adb("shell", "am", "start", "-W", "-n", activity)
    if "Status: ok" not in started:
        raise RuntimeError(started)
    time.sleep(4)
    pid = adb("shell", "pidof", PACKAGE)
    if not pid:
        raise RuntimeError("The game did not stay running")
    log = adb("logcat", "-d", "--pid=" + pid, "-t", "1000")
    (args.out / "startup.log").write_text(log)
    (args.out / "title.png").write_bytes(adb("exec-out", "screencap", "-p", binary=True))
    errors = [line for line in log.splitlines() if re.search(r"(?:E godot\s*:|FATAL EXCEPTION|SCRIPT ERROR|shader.*(?:failed|exceed))", line, re.I)]
    report = {
        "model": adb("shell", "getprop", "ro.product.model"),
        "android": adb("shell", "getprop", "ro.build.version.release"),
        "abi": adb("shell", "getprop", "ro.product.cpu.abi"),
        "native_startup": not errors,
        "errors": errors,
        "scope": "Installation, engine startup and screenshot only; not a complete gameplay or battery test.",
    }
    (args.out / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    raise SystemExit(1 if errors else 0)


if __name__ == "__main__":
    main()
