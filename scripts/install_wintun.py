from pathlib import Path
import hashlib
import io
import json
import sys
import urllib.request
import zipfile

asset=json.loads(Path(__file__).with_name('wintun_asset.json').read_text())
with urllib.request.urlopen(asset['url'],timeout=90) as response:data=response.read(5*1024*1024)
if hashlib.sha256(data).hexdigest()!=asset['sha256']:raise RuntimeError('Wintun digest mismatch')
with zipfile.ZipFile(io.BytesIO(data)) as archive:
    binary=archive.read('wintun/bin/amd64/wintun.dll')
    license=archive.read('wintun/LICENSE.txt')
folder=Path(sys.argv[1]);folder.mkdir(parents=True,exist_ok=True)
(folder/'wintun.dll').write_bytes(binary)
(folder/'WINTUN-LICENSE.txt').write_bytes(license)
print('Verified official Wintun 0.14.1 (amd64)')
