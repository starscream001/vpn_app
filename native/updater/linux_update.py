#!/usr/bin/env python3
"""Local, consented bundle replacement. Never reads the OS credential vault."""
import hashlib
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import zipfile


def validate(archive, expected):
    if len(expected)!=64 or any(c not in '0123456789abcdef' for c in expected):raise ValueError('Invalid digest')
    with archive.open('rb') as f:
        if hashlib.file_digest(f,'sha256').hexdigest()!=expected:raise ValueError('Digest mismatch')
    with zipfile.ZipFile(archive) as z:
        names=set();size=0
        for e in z.infolist():
            p=Path(e.filename)
            if p.is_absolute() or '..' in p.parts or '\\' in e.filename or ':' in e.filename or stat.S_ISLNK(e.external_attr>>16):raise ValueError('Unsafe archive entry')
            if e.filename in names:raise ValueError('Duplicate entry')
            names.add(e.filename);size+=e.file_size
            if len(names)>20000 or size>2*1024**3:raise ValueError('Archive too large')
        if not {'foxway','sing-box','amneziawg-go','awg','awg-quick','foxway-guard.py'}<=names:raise ValueError('Incomplete bundle')
    return True


def apply(archive,expected,target,pid):
    validate(archive,expected)
    if target.is_symlink() or pid<=0:raise ValueError('Invalid installation or pid')
    target=target.resolve()
    if target==target.parent or not (target/'foxway').is_file() or not (target/'data/flutter_assets').is_dir():raise ValueError('Not a FoxWay installation')
    if target.is_symlink():raise ValueError('Symlink installation rejected')
    stage=Path(tempfile.mkdtemp(prefix='.foxway-update-',dir=target.parent))
    backup=target.with_name(target.name+'.previous-'+stage.name.rsplit('-',1)[-1])
    installed=False;moved=False
    try:
        with zipfile.ZipFile(archive) as z:z.extractall(stage)
        for name in ('foxway','sing-box','amneziawg-go','awg','awg-quick'):(stage/name).chmod(0o755)
        for lib in stage.rglob('*.so'):lib.chmod(0o755)
        print('READY',flush=True)
        deadline=time.monotonic()+120
        while time.monotonic()<deadline:
            try:os.kill(pid,0)
            except ProcessLookupError:break
            time.sleep(.25)
        else:raise RuntimeError('Application did not exit')
        target.rename(backup);moved=True
        stage.rename(target);installed=True
        process=subprocess.Popen([str(target/'foxway')],cwd=target,start_new_session=True)
        time.sleep(2)
        if process.poll() not in (None,0):raise RuntimeError('New application failed to start')
        # Keep the complete previous bundle for an explicit rollback. No user files deleted.
    except Exception:
        if installed:target.rename(stage)
        if moved:backup.rename(target)
        if moved:subprocess.Popen([str(target/'foxway'),'--foxway-update-failed'],cwd=target,start_new_session=True)
        raise
    finally:
        if stage.exists():shutil.rmtree(stage)

if __name__=='__main__':
    try:apply(Path(sys.argv[1]),sys.argv[2],Path(sys.argv[3]),int(sys.argv[4]))
    except Exception:
        Path(__file__).with_suffix('.log').write_text('FoxWay update failed; existing installation restored when possible.\n')
        sys.exit(1)
