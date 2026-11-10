"""Collect the application and pinned native corresponding sources, including Go modules.

Run on the source commit with Go and Flutter dependencies already installed.
No VPN executable is started. Module zip files are verified by Go's checksum database.
"""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import tarfile
import urllib.parse
import urllib.request

root = Path.cwd()
out = root / 'build/corresponding-source'
out.mkdir(parents=True, exist_ok=True)
scratch = root / 'build/source-checkouts'
scratch.mkdir(parents=True, exist_ok=True)


def run(*args, cwd=root):
    return subprocess.check_output(args, cwd=cwd, text=True)


run('git', 'archive', '--format=tar.gz', '-o', str(out / 'FoxWay-source.tar.gz'), 'HEAD')
sources = {
    'sing-box': ('https://github.com/SagerNet/sing-box.git', 'c005f35300ce76427dc285481ec5695f5b179cd2'),
    'AndroidLibXrayLite': ('https://github.com/2dust/AndroidLibXrayLite.git', '1be1e621be15702da7b7faf16ef83f2493c5aa01'),
}
module_roots = [root / p for p in (
    'native/windows-awg', 'native/awg-cli',
    'native/amnezia-apple/Sources/WireGuardKitGo',
)]
for name, (url, commit) in sources.items():
    folder = scratch / name
    if not folder.exists():
        run('git', 'init', str(folder))
        run('git', 'fetch', '--depth=1', url, commit, cwd=folder)
        run('git', 'checkout', '--detach', 'FETCH_HEAD', cwd=folder)
    if run('git', 'rev-parse', 'HEAD', cwd=folder).strip() != commit:
        raise RuntimeError('Source revision mismatch')
    run('git', 'archive', '--format=tar.gz', '-o', str(out / f'{name}-source.tar.gz'), 'HEAD', cwd=folder)
    module_roots.append(folder)

module_dir = out / 'go-modules'
module_dir.mkdir(exist_ok=True)
manifest = {}
decoder = json.JSONDecoder()
for folder in module_roots:
    data = run('go', 'mod', 'download', '-json', 'all', cwd=folder)
    while data.strip():
        info, end = decoder.raw_decode(data.lstrip())
        data = data.lstrip()[end:]
        if info.get('Error'):
            raise RuntimeError(info['Error'])
        key = info['Path'] + '@' + info['Version']
        if key in manifest:
            continue
        files = {}
        for field in ('Zip', 'GoMod', 'Info'):
            if info.get(field):
                src = Path(info[field])
                name = urllib.parse.quote(key, safe='') + src.suffix
                shutil.copy2(src, module_dir / name)
                files[field] = name
        manifest[key] = {'sum': info.get('Sum'), 'go_mod_sum': info.get('GoModSum'), 'files': files}

(out / 'go-module-manifest.json').write_text(json.dumps(manifest, indent=2))
# Include Dart plugin sources and their original notices, not just dependency names.
config = root / '.dart_tool/package_config.json'
packages = out / 'dart-packages'
packages.mkdir(exist_ok=True)
for package in json.loads(config.read_text())['packages']:
    uri = urllib.parse.urljoin(config.as_uri(), package['rootUri'])
    src = Path(urllib.parse.unquote(urllib.parse.urlparse(uri).path))
    if '.pub-cache' in str(src) and src.is_dir():
        shutil.copytree(src, packages / package['name'], dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns('.git', 'build', '.dart_tool'))

maven_url = 'https://repo.maven.apache.org/maven2/com/zaneschepke/amneziawg-android/2.3.7/amneziawg-android-2.3.7-sources.jar'
with urllib.request.urlopen(maven_url, timeout=90) as response:
    (out / 'amneziawg-android-2.3.7-sources.jar').write_bytes(response.read())
shutil.copy2(root / 'docs/SOURCES.md', out / 'README.md')
with (out / 'SHA256SUMS.txt').open('w') as sums:
    for file in sorted(out.rglob('*')):
        if file.is_file() and file.name != 'SHA256SUMS.txt':
            digest = hashlib.file_digest(file.open('rb'), 'sha256').hexdigest()
            sums.write(f'{digest}  {file.relative_to(out)}\n')
archive = root / 'build/FoxWay-corresponding-source.tar.gz'
with tarfile.open(archive, 'w:gz') as tar:
    tar.add(out, arcname='FoxWay-corresponding-source')
print(f'Collected {len(manifest)} native dependency modules: {archive}')
