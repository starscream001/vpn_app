"""Fetch a pinned upstream core, verify its pinned digest, extract only the executable."""
from pathlib import Path
import hashlib
import io
import json
import platform
import sys
import tarfile
import urllib.request
import zipfile

osname = {'Darwin':'darwin','Windows':'windows','Linux':'linux'}[platform.system()]
arch = 'arm64' if platform.machine().lower() in ('arm64','aarch64') else 'amd64'
if len(sys.argv) > 2:
    arch = sys.argv[2]
    if arch not in ('arm64', 'amd64'): raise ValueError('Unsupported arch')
assets = json.loads(Path(__file__).with_name('sing_box_assets.json').read_text())
asset = assets[f'{osname}-{arch}']
with urllib.request.urlopen(asset['url'], timeout=120) as response:
    data = response.read(150 * 1024 * 1024)
if 'sha256:' + hashlib.sha256(data).hexdigest() != asset['digest']:
    raise RuntimeError('Upstream core digest mismatch; refusing to package')
name = 'sing-box.exe' if osname == 'windows' else 'sing-box'
if asset['url'].endswith('.zip'):
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        entries = [n for n in archive.namelist() if n.split('/')[-1] == name]
        if len(entries) != 1: raise RuntimeError('Unexpected upstream archive')
        binary = archive.read(entries[0])
else:
    with tarfile.open(fileobj=io.BytesIO(data),mode='r:gz') as archive:
        entries = [n for n in archive.getmembers() if n.isfile() and n.name.split('/')[-1] == name]
        if len(entries) != 1: raise RuntimeError('Unexpected upstream archive')
        binary = archive.extractfile(entries[0]).read()
folder = Path(sys.argv[1]);folder.mkdir(parents=True,exist_ok=True)
target = folder / (f'sing-box-{arch}' if osname == 'darwin' and len(sys.argv) > 2 else name);target.write_bytes(binary);target.chmod(0o755)
print(f'Verified sing-box 1.14.4: {target}')
