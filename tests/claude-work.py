#!/usr/bin/env python3
import plistlib
import runpy
import tempfile
from pathlib import Path

repo = Path(__file__).resolve().parent.parent
install = runpy.run_path(str(repo / 'bootstrap/claude-work.py'))['install']
with tempfile.TemporaryDirectory() as temp:
    home = Path(temp)
    app = home / 'Claude.app'
    (app / 'Contents/Resources').mkdir(parents=True)
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIconFile': 'icon.icns'}))
    (app / 'Contents/Resources/icon.icns').write_bytes(b'icon')
    install(home, app)
    launcher = home / 'Applications/Claude Work.app/Contents/MacOS/Claude Work'
    assert 'CLAUDE_CONFIG_DIR="$HOME/.claude-work"' in launcher.read_text()
    assert '--user-data-dir="$HOME/.claude-profiles/work/desktop"' in launcher.read_text()
    personal = home / 'Applications/Claude Personal.app/Contents/MacOS/Claude Personal'
    assert 'CLAUDE_CONFIG_DIR="$HOME/.claude"' in personal.read_text()
    assert '--user-data-dir="$HOME/Library/Application Support/Claude"' in personal.read_text()
    assert '.claude-work' not in personal.read_text()
    personal_before = personal.stat().st_mtime_ns
    before = launcher.stat().st_mtime_ns
    install(home, app)
    assert launcher.stat().st_mtime_ns == before
    assert personal.stat().st_mtime_ns == personal_before
    plist = launcher.parent.parent / 'Info.plist'
    plist.write_bytes(plistlib.dumps({'CFBundleIdentifier': 'someone.else'}))
    launcher.write_text('unmanaged')
    install(home, app)
    assert launcher.read_text() == 'unmanaged'
print('Claude Work isolation, rerun, and preservation checks passed.')
