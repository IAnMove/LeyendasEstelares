#!/usr/bin/env python3
"""Create a private signing key, or export and verify signed Android APK/AAB files."""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import secrets
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SIGNING = Path.home() / '.local/share/leyendas-estelares/signing'


def run(command, env, log_path, secret=''):
    result = subprocess.run(command, env=env, cwd=ROOT, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True)
    output = result.stdout.replace(secret, '[REDACTED]') if secret else result.stdout
    log_path.write_text(output)
    if result.returncode or re.search(r"^(?:SCRIPT ERROR:|ERROR:)", output, re.M):
        raise RuntimeError(f'{Path(command[0]).name} failed; see {log_path}\n{output[-3000:]}')
    return output


def init_key(directory, keytool):
    directory = directory.expanduser().resolve()
    if directory.is_relative_to(ROOT):
        raise ValueError('Signing credentials must be outside the project.')
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    key = directory / 'release.p12'
    config = directory / 'signing.json'
    if key.exists() or config.exists():
        raise ValueError('A signing key/config already exists; it will not be replaced.')
    password = secrets.token_urlsafe(36)
    env = os.environ.copy()
    env['LEYENDAS_SIGNING_PASSWORD'] = password
    run([keytool, '-genkeypair', '-noprompt', '-keystore', str(key), '-storetype', 'PKCS12',
         '-alias', 'leyendas-release', '-keyalg', 'RSA', '-keysize', '4096', '-validity', '10000',
         '-dname', 'CN=Leyendas Estelares', '-storepass:env', 'LEYENDAS_SIGNING_PASSWORD',
         '-keypass:env', 'LEYENDAS_SIGNING_PASSWORD'], env, directory / 'key-generation.log', password)
    config.write_text(json.dumps({'keystore': str(key), 'alias': 'leyendas-release', 'password': password}, indent=2) + '\n')
    for path in directory.iterdir():
        if path.is_file():
            path.chmod(0o600)
    print(f'Private signing configuration created: {config}')
    print('Back up this directory securely before distributing updates. Credentials were not printed.')


def export(args):
    config_path = args.signing_dir.expanduser() / 'signing.json'
    config = json.loads(config_path.read_text())
    key = Path(config['keystore']).expanduser().resolve()
    if key.is_relative_to(ROOT) or config_path.resolve().is_relative_to(ROOT):
        raise ValueError('Signing credentials must be outside the project.')
    if not key.is_file():
        raise ValueError('Signing key not found.')
    env = os.environ.copy()
    env.update({'GODOT_ANDROID_KEYSTORE_RELEASE_PATH': str(key),
                'GODOT_ANDROID_KEYSTORE_RELEASE_USER': config['alias'],
                'GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD': config['password']})
    if args.java_home:
        env['JAVA_HOME'] = str(args.java_home)
    env['ANDROID_HOME'] = str(args.sdk)
    out = ROOT / 'build/android/release'
    out.mkdir(parents=True, exist_ok=True)
    (ROOT / 'build/.gdignore').touch()
    base = [args.godot, '--headless', '--path', str(ROOT)]
    tools_dir = args.sdk / 'build-tools' / args.build_tools
    with tempfile.TemporaryDirectory(prefix='android-release-', dir=ROOT / 'build') as scratch:
        env['TMPDIR'] = scratch
        env['JAVA_TOOL_OPTIONS'] = env.get('JAVA_TOOL_OPTIONS', '') + f' -Djava.io.tmpdir="{scratch}"'
        run(base + ['--editor', '--import', '--quit'], env, out / 'import.log', config['password'])
        for kind, preset in [('apk', 'Android Release APK'), ('aab', 'Android Release AAB')]:
            artifact = out / f'leyendas-estelares.{kind}'
            command = base + ['--export-release', preset, str(artifact)]
            if not (ROOT / 'android/build/build.gradle').exists():
                command.append('--install-android-build-template')
            run(command, env, out / f'export-{kind}.log', config['password'])
            if not artifact.is_file():
                raise RuntimeError(f'Export did not produce {artifact}')
            print(f'Exported {artifact}', flush=True)
        apk = out / 'leyendas-estelares.apk'
        run([str(tools_dir / 'apksigner'), 'verify', '--verbose', '--print-certs', str(apk)],
            env, out / 'apk-signature.txt')
        run([str(tools_dir / 'zipalign'), '-c', '-P', '16', '4', str(apk)],
            env, out / 'apk-alignment.txt')
        elf_report = {}
        with zipfile.ZipFile(apk) as archive:
            for name in archive.namelist():
                if name.startswith('lib/') and name.endswith('.so'):
                    library = Path(scratch) / Path(name).name
                    library.write_bytes(archive.read(name))
                    headers = run(['readelf', '-lW', str(library)], env, out / 'elf-inspection.txt')
                    alignments = [int(line.split()[-1], 16) for line in headers.splitlines() if line.strip().startswith('LOAD ')]
                    required_alignment = 16384 if name.split('/')[1] in ('arm64-v8a', 'x86_64') else 4096
                    if not alignments or any(value < required_alignment for value in alignments):
                        raise RuntimeError(f'{name} does not meet ELF page alignment for its ABI')
                    elf_report[name] = alignments
        (out / 'elf-alignment.json').write_text(json.dumps(elf_report, indent=2) + '\n')
        if args.bundletool:
            java = str(args.java_home / 'bin/java') if args.java_home else 'java'
            run([java, '-jar', str(args.bundletool), 'validate', '--bundle=' + str(out / 'leyendas-estelares.aab')],
                env, out / 'bundle-validation.txt')
        jarsigner = str(args.java_home / 'bin/jarsigner') if args.java_home else 'jarsigner'
        bundle_check = run([jarsigner, '-verify', str(out / 'leyendas-estelares.aab')],
                          env, out / 'aab-signature.txt')
        # jarsigner may return zero for unsigned input; require a verified signature.
        if 'jar verified.' not in bundle_check:
            raise RuntimeError('AAB signature was not verified; see aab-signature.txt')
    shutil.copy2(ROOT / 'LICENSE', out / 'LICENSE')
    shutil.copy2(ROOT / 'art/fonts/LICENSE', out / 'FONTS-LICENSE.txt')
    report = {p.name: {'bytes': p.stat().st_size, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
              for p in [out / 'leyendas-estelares.apk', out / 'leyendas-estelares.aab']}
    (out / 'artifacts.json').write_text(json.dumps(report, indent=2) + '\n')
    print('Verified APK signature, 16 KiB ZIP alignment and AAB signature.')
    print('Distribution files are ready locally. Nothing has been uploaded to a store.')


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['init-key', 'export'])
    parser.add_argument('--signing-dir', type=Path, default=DEFAULT_SIGNING)
    parser.add_argument('--godot', default=os.environ.get('GODOT', 'godot'))
    parser.add_argument('--sdk', type=Path, default=Path(os.environ.get('ANDROID_HOME', Path.home() / 'Android/Sdk')))
    parser.add_argument('--java-home', type=Path, default=Path(os.environ['JAVA_HOME']) if 'JAVA_HOME' in os.environ else None)
    parser.add_argument('--bundletool', type=Path, help='Optional local bundletool JAR for AAB structural validation')
    parser.add_argument('--build-tools', default='36.0.0')
    args = parser.parse_args()
    if args.action == 'init-key':
        init_key(args.signing_dir, str(args.java_home / 'bin/keytool') if args.java_home else 'keytool')
    else:
        export(args)


if __name__ == '__main__':
    main()
