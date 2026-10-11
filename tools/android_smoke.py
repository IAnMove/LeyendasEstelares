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
PACKAGE = "org.leyendasestelares.game.debug"



def log_issues(log):
    """Godot writes warnings to Android's E stream too; keep them distinct."""
    errors, warnings = [], []
    warning_block = False
    for line in log.splitlines():
        godot_error_stream = bool(re.search(r"E godot\s*:", line))
        if godot_error_stream and "WARNING:" in line:
            warning_block = True
            warnings.append(line)
            continue
        if warning_block and godot_error_stream and re.search(r":\s+(?:at:|GDScript backtrace|\[\d+\])", line):
            warnings.append(line)
            continue
        warning_block = False
        if re.search(r"(?:E (?:godot|GLSurfaceView)\s*:|FATAL EXCEPTION|SCRIPT ERROR|shader.*(?:failed|exceed))", line, re.I):
            errors.append(line)
    return errors, warnings


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", required=True, help="Exact serial from adb devices")
    parser.add_argument("--adb", default=os.environ.get("ADB", "adb"))
    parser.add_argument("--apk", type=Path, default=ROOT / "build/android/leyendas-estelares.apk")
    parser.add_argument("--package", default=PACKAGE, help="Package ID; release uses org.leyendasestelares.game")
    parser.add_argument("--out", type=Path, default=ROOT / "build/android/validation")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    command = [args.adb, "-s", args.serial]

    def adb(*words, binary=False):
        result = subprocess.run(command + list(words), check=True, capture_output=True)
        return result.stdout if binary else result.stdout.decode().strip()

    policy = adb("shell", "dumpsys", "window", "policy")
    power = adb("shell", "dumpsys", "power")
    if "mWakefulness=Awake" not in power or re.search(r"^\s+showing=true", policy, re.M):
        report = {"native_startup": False, "blocked": "Selected device is locked or asleep; unlock it before testing."}
        (args.out / "report.json").write_text(json.dumps(report, indent=2) + "\n")
        raise SystemExit(report["blocked"])
    adb("install", "-r", str(args.apk.resolve()))
    adb("shell", "am", "force-stop", args.package)
    activity = adb("shell", "cmd", "package", "resolve-activity", "--brief", args.package).splitlines()[-1]
    started = adb("shell", "am", "start", "-W", "-n", activity)
    if "Status: ok" not in started:
        raise RuntimeError(started)
    time.sleep(4)
    pid = adb("shell", "pidof", args.package)
    if not pid:
        raise RuntimeError("The game did not stay running")
    log = adb("logcat", "-d", "--pid=" + pid, "-t", "1000")
    engine_ready = bool(re.search(r"(?:OpenGL.*(?:API|Renderer)|Vulkan.*API)", log, re.I))
    foreground = args.package in adb("shell", "dumpsys", "window").split("mCurrentFocus=")[-1].splitlines()[0]
    (args.out / "startup.log").write_text(log)
    if foreground:
        (args.out / "title.png").write_bytes(adb("exec-out", "screencap", "-p", binary=True))
    errors, warnings = log_issues(log)
    report = {
        "model": adb("shell", "getprop", "ro.product.model"),
        "android": adb("shell", "getprop", "ro.build.version.release"),
        "abi": adb("shell", "getprop", "ro.product.cpu.abi"),
        "native_startup": engine_ready and foreground and not errors,
        "engine_renderer_ready": engine_ready,
        "foreground": foreground,
        "errors": errors,
        "warnings": warnings,
        "scope": "Installation, engine startup and screenshot only; not a complete gameplay or battery test.",
    }
    (args.out / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    raise SystemExit(0 if report["native_startup"] else 1)


if __name__ == "__main__":
    main()
