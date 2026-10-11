#!/usr/bin/env python3
"""Play the isolated Android QA APK with real ADB touches; inspect read-only observations."""
import argparse
import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import time

from android_smoke import log_issues

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = 'org.leyendasestelares.game.qa'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--adb', default=os.environ.get('ADB', 'adb'))
    parser.add_argument('--apk', type=Path, default=ROOT / 'build/android/leyendas-estelares-qa.apk')
    parser.add_argument('--out', type=Path, default=ROOT / 'build/android/playthrough')
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    base = [args.adb, '-s', args.serial]
    steps, performance, stages = [], [], set()
    lifecycle_checked = death_checked = False
    trade_checked = trade_bought = False
    game_logs = []
    moves = 0
    supply = None

    def adb(*words, binary=False):
        result = subprocess.run(base + list(words), capture_output=True, check=True)
        return result.stdout if binary else result.stdout.decode().strip()

    def observation(stage=None, newer=None, timeout=35):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                value = json.loads(adb('exec-out', 'run-as', PACKAGE, 'cat', 'files/qa-observation.json'))
                if (stage is None or value['stage'] == stage) and (newer is None or value['tick'] != newer):
                    return value
            except (subprocess.CalledProcessError, json.JSONDecodeError):
                pass
            time.sleep(0.3)
        raise RuntimeError('QA observer did not produce the expected screen; unlock the device and inspect logcat.')

    def foreground():
        windows = adb('shell', 'dumpsys', 'window')
        focus = next((line for line in windows.splitlines() if 'mCurrentFocus=' in line), '')
        if PACKAGE not in focus:
            raise RuntimeError('QA game lost foreground; stopping touch input to avoid interacting with another app.')

    def tap_rect(rect):
        foreground()
        x, y, width, height = rect
        adb('shell', 'input', 'tap', str(round(x + width / 2)), str(round(y + height / 2)))
        time.sleep(0.65)

    def button(report, prefix):
        return next((b for b in report['buttons'] if b['text'].startswith(prefix) and not b['disabled']), None)

    def press(report, item):
        if not item:
            raise RuntimeError('Expected button is missing')
        if not item['visible']:
            scroll(report, item)
            return False
        tap_rect(item['rect'])
        steps.append({'stage': report['stage'], 'action': item['text'].splitlines()[0]})
        return True

    def scroll(report, target=None):
        foreground()
        if not report['scrolls']:
            raise RuntimeError('Button is clipped but no scroll panel is available')
        x, y, width, height = report['scrolls'][-1]
        upward = target is None or target['rect'][1] > y
        start, end = (0.82, 0.22) if upward else (0.22, 0.82)
        adb('shell', 'input', 'swipe', str(round(x + width * .8)), str(round(y + height * start)),
            str(round(x + width * .8)), str(round(y + height * end)), '450')
        time.sleep(.7)
        steps.append({'stage': report['stage'], 'action': 'scroll'})

    def shot(name):
        foreground()
        (args.out / (name + '.png')).write_bytes(adb('exec-out', 'screencap', '-p', binary=True))

    power = adb('shell', 'dumpsys', 'power')
    policy = adb('shell', 'dumpsys', 'window', 'policy')
    if 'mWakefulness=Awake' not in power or re.search(r'^\s+showing=true', policy, re.M):
        raise RuntimeError('Selected device is locked/asleep; unlock it before testing.')
    adb('install', '-r', str(args.apk.resolve()))
    adb('shell', 'am', 'force-stop', PACKAGE)
    activity = adb('shell', 'cmd', 'package', 'resolve-activity', '--brief', PACKAGE).splitlines()[-1]
    adb('shell', 'am', 'start', '-W', '-n', activity)
    report = observation('TitleScreen')
    current_pid = adb('shell', 'pidof', PACKAGE)
    try:
        for step in range(360):
            report = observation()
            if report['stage'] not in stages:
                stages.add(report['stage'])
                shot(report['stage'])
            performance.append({'stage': report['stage'], 'fps': report['fps'],
                                'process_ms': report['process_ms_average'], 'memory_bytes': report['memory_static_bytes']})
            (args.out / 'last-observation.json').write_text(json.dumps(report, indent=2) + '\n')
            if report['stage'] == 'EndScreen':
                shot('ending-' + report['ending'])
                break
            if report['stage'] == 'TitleScreen':
                press(report, button(report, 'New expedition'))
                continue
            if report['active'] == 'Overlay' and button(report, 'Cancel'):
                press(report, button(report, 'New expedition'))
                continue
            if report['stage'] == 'AvatarScreen':
                press(report, button(report, 'Choose'))
                continue
            if report['stage'] == 'SectorScreen' and not lifecycle_checked:
                adb('shell', 'input', 'keyevent', '4')
                time.sleep(.8)
                paused = observation(newer=report['tick'])
                assert paused['paused'] and paused['audio_suspended'], 'Back must pause gameplay and audio'
                adb('shell', 'input', 'keyevent', '3')
                time.sleep(1)
                adb('shell', 'am', 'start', '-W', '-n', activity)
                time.sleep(1)
                paused = observation(newer=paused['tick'])
                assert paused['paused'] and paused['audio_suspended'] and paused['pauses'] > 0, 'Resume must preserve the pause'
                press(paused, button(paused, 'Resume expedition'))
                lifecycle_checked = True
                print('PASS: Back, Home/resume and suspended audio', flush=True)
                continue
            if report['stage'] == 'MapScreen' and report.get('phase') == 'explore' and moves >= 2 and not death_checked:
                before_state, before_player = report['state'], report['player']
                game_logs.append(adb('logcat', '-d', '--pid=' + current_pid, '-t', '2000'))
                adb('shell', 'am', 'force-stop', PACKAGE)
                adb('shell', 'am', 'start', '-W', '-n', activity)
                current_pid = adb('shell', 'pidof', PACKAGE)
                title = observation('TitleScreen')
                while not press(title, button(title, 'Continue game')):
                    title = observation(newer=title['tick'])
                restored = observation('MapScreen')
                assert restored['state'] == before_state and restored['player'] == before_player, 'Process death changed the saved expedition'
                death_checked = True
                shot('restored-after-process-death')
                print('PASS: force-stop and exact saved-state recovery', flush=True)
                continue
            if report['active'] == 'ShipScreen':
                item = next((b for b in report['buttons'] if b['text'].startswith('Use') and not b['disabled'] and supply in b['context'].lower()), None) if supply else None
                if item:
                    if press(report, item):
                        supply = None
                else:
                    press(report, button(report, 'Return'))
                continue
            if report['active'] == 'TradeScreen':
                if not trade_bought:
                    affordable = next((b for b in report['buttons'] if b['text'].startswith('Buy') and not b['disabled']), None)
                    if affordable:
                        if press(report, affordable):
                            trade_bought = True
                        continue
                press(report, button(report, 'Close market'))
                trade_checked = True
                continue
            if report['paused']:
                press(report, button(report, 'Resume expedition'))
                continue
            if report['stage'] == 'SectorScreen':
                nodes = report['nodes']
                if not nodes and report['state']['inventory'].get('fuel_cell', 0):
                    supply = 'fuel'
                    press(report, button(report, 'Crew & cargo'))
                    continue
                if not nodes:
                    raise RuntimeError('No jump is available')
                target = min(nodes, key=lambda n: (n['cost'], {'planet': 0, 'contact': 1, 'anomaly': 2}[n['type']]))
                if report['selected'] != target['id']:
                    tap_rect(target['rect'])
                else:
                    press(report, button(report, 'Jump'))
                continue
            if report['stage'] == 'MapScreen' and report.get('phase') == 'explore':
                if report['state']['oxygen'] <= 12 and report['state']['inventory'].get('oxygen_cell', 0):
                    supply = 'oxygen'
                    press(report, button(report, 'Supplies & equipment'))
                    continue
                point = report.get('suggested_hex')
                if not point:
                    raise RuntimeError('No surface path to the objective or ship')
                foreground()
                adb('shell', 'input', 'tap', str(round(point[0])), str(round(point[1])))
                moves += 1
                steps.append({'stage': report['stage'], 'action': 'move', 'oxygen': report['state']['oxygen']})
                time.sleep(.65)
                continue
            if report['stage'] == 'ContactScreen' and not trade_checked and button(report, 'Open trade channel'):
                press(report, button(report, 'Open trade channel'))
                continue
            for prefix in ['Continue', 'Descend', 'Close the channel']:
                item = button(report, prefix)
                if item:
                    press(report, item)
                    break
            else:
                item = next((b for b in report['buttons'] if b['path'] == report.get('suggested_button')), None)
                if item is None:
                    # Event choices only: decorative/help controls are outside the active overlay.
                    candidates = [b for b in report['buttons'] if not b['disabled'] and b['text'] not in ['?', 'Ⅱ']]
                    item = candidates[0] if candidates else None
                press(report, item)
            if step % 25 == 0:
                print(f'Step {step}: {report["stage"]}; oxygen {report["state"]["oxygen"]}', flush=True)
        else:
            raise RuntimeError('Playthrough exceeded its step limit')
        assert lifecycle_checked and death_checked, 'Lifecycle coverage incomplete'
        pid = adb('shell', 'pidof', PACKAGE)
        game_logs.append(adb('logcat', '-d', '--pid=' + pid, '-t', '2000'))
        log = '\n'.join(game_logs)
        (args.out / 'game.log').write_text(log)
        errors, warnings = log_issues(log)
        assert not errors, '\n'.join(errors)
        memory = adb('shell', 'dumpsys', 'meminfo', PACKAGE)
        (args.out / 'memory.txt').write_text(memory)
        pss = re.search(r'TOTAL PSS:\s*(\d+)', memory)
        summary = {'total_pss_mb_at_end': int(pss.group(1)) / 1024 if pss else None,
                   'model': adb('shell', 'getprop', 'ro.product.model'), 'android': adb('shell', 'getprop', 'ro.build.version.release'),
                   'ending': report['ending'], 'jumps': report['campaign']['jumps'], 'moves': moves,
                   'stages': sorted(stages), 'trade_opened': trade_checked, 'trade_purchase': trade_bought,
                   'touch_scroll_actions': sum(s['action'] == 'scroll' for s in steps), 'back_and_resume': lifecycle_checked, 'process_death_recovery': death_checked,
                   'errors': errors, 'warnings': warnings, 'fps_median': statistics.median(p['fps'] for p in performance[3:]),
                   'process_ms_median': statistics.median(p['process_ms'] for p in performance[3:]),
                   'static_memory_peak_mb': max(p['memory_bytes'] for p in performance) / 1024 ** 2,
                   'scope': 'QA build; read-only state observer; all actions use Android touch events. Path selection uses full map for deterministic test coverage. No battery-life claim.'}
        (args.out / 'report.json').write_text(json.dumps(summary, indent=2) + '\n')
        print(json.dumps(summary, indent=2))
    finally:
        (args.out / 'steps.json').write_text(json.dumps(steps, indent=2) + '\n')
        (args.out / 'performance.json').write_text(json.dumps(performance, indent=2) + '\n')


if __name__ == '__main__':
    main()
