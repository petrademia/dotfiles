#!/usr/bin/env python3
"""Create macOS launchers for Claude personal and work profiles."""
import plistlib
import shutil
from pathlib import Path


def install(home, claude_app):
    if not claude_app.is_dir():
        print('[-] Claude Desktop is not installed; skipping Claude profile launchers')
        return
    for profile in ('personal', 'work'):
        install_profile(home, claude_app, profile)


def install_profile(home, claude_app, profile):
    name = f'Claude {profile.title()}'
    destination = home / f'Applications/{name}.app'
    plist = destination / 'Contents/Info.plist'
    bundle_id = f'com.petra.claude-{profile}'
    if destination.exists() and (not plist.exists() or plistlib.loads(plist.read_bytes()).get('CFBundleIdentifier') != bundle_id):
        print(f'[!] Existing {name} app is unmanaged; preserving it')
        return
    contents = destination / 'Contents'
    (contents / 'MacOS').mkdir(parents=True, exist_ok=True)
    (contents / 'Resources').mkdir(exist_ok=True)
    executable = contents / f'MacOS/{name}'
    config_dir = '.claude-work' if profile == 'work' else '.claude'
    data_dir = '.claude-profiles/work/desktop' if profile == 'work' else 'Library/Application Support/Claude'
    script = f'''#!/bin/bash
export CLAUDE_CONFIG_DIR="$HOME/{config_dir}"
exec /Applications/Claude.app/Contents/MacOS/Claude \\
  --user-data-dir="$HOME/{data_dir}" "$@"
'''
    if not executable.exists() or executable.read_text() != script:
        executable.write_text(script)
    executable.chmod(0o755)
    metadata = dict(CFBundleIdentifier=bundle_id, CFBundleName=name,
                    CFBundleDisplayName=name, CFBundleExecutable=name,
                    CFBundlePackageType='APPL', CFBundleVersion='1', CFBundleIconFile='ClaudeWork.icns')
    payload = plistlib.dumps(metadata)
    if not plist.exists() or plist.read_bytes() != payload:
        plist.write_bytes(payload)
    original = plistlib.loads((claude_app / 'Contents/Info.plist').read_bytes())
    icon = claude_app / 'Contents/Resources' / original.get('CFBundleIconFile', 'electron.icns')
    if not icon.suffix:
        icon = icon.with_suffix('.icns')
    target = contents / 'Resources/ClaudeWork.icns'
    if icon.is_file() and (not target.exists() or target.read_bytes() != icon.read_bytes()):
        shutil.copy2(icon, target)
    print(f'[+] {name} launcher ready')


if __name__ == '__main__':
    install(Path.home(), Path('/Applications/Claude.app'))
