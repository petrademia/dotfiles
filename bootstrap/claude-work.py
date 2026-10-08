#!/usr/bin/env python3
"""Create a macOS launcher using Claude's separate work data directory."""
import plistlib
import shutil
from pathlib import Path


def install(home, claude_app):
    if not claude_app.is_dir():
        print('[-] Claude Desktop is not installed; skipping Claude Work launcher')
        return
    destination = home / 'Applications/Claude Work.app'
    plist = destination / 'Contents/Info.plist'
    bundle_id = 'com.petra.claude-work'
    if destination.exists() and (not plist.exists() or plistlib.loads(plist.read_bytes()).get('CFBundleIdentifier') != bundle_id):
        print('[!] Existing Claude Work app is unmanaged; preserving it')
        return
    contents = destination / 'Contents'
    (contents / 'MacOS').mkdir(parents=True, exist_ok=True)
    (contents / 'Resources').mkdir(exist_ok=True)
    executable = contents / 'MacOS/Claude Work'
    script = '''#!/bin/bash
export CLAUDE_CONFIG_DIR="$HOME/.claude-work"
exec /Applications/Claude.app/Contents/MacOS/Claude \\
  --user-data-dir="$HOME/.claude-profiles/work/desktop" "$@"
'''
    if not executable.exists() or executable.read_text() != script:
        executable.write_text(script)
    executable.chmod(0o755)
    metadata = dict(CFBundleIdentifier=bundle_id, CFBundleName='Claude Work',
                    CFBundleDisplayName='Claude Work', CFBundleExecutable='Claude Work',
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
    print('[+] Claude Work launcher ready')


if __name__ == '__main__':
    install(Path.home(), Path('/Applications/Claude.app'))
