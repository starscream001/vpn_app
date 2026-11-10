"""Package downloaded CI artifacts without confusing UI previews with VPN builds."""
from pathlib import Path
import hashlib
import shutil
import zipfile

root = Path('release-input')
out = Path('release-output')
out.mkdir(exist_ok=True)
for path in root.rglob('*'):
    if path.suffix in ('.apk', '.aab'):
        shutil.copy2(path, out / path.name)
source_bundle = root / 'corresponding-source/FoxWay-corresponding-source.tar.gz'
if not source_bundle.is_file():
    raise RuntimeError('Missing corresponding sources; refusing binary release')
shutil.copy2(source_bundle, out / source_bundle.name)
for platform in ('windows', 'linux', 'macos', 'iOS'):
    directories = [p for p in root.iterdir() if p.is_dir() and p.name.startswith(platform + '-')]
    if len(directories) != 1:
        raise RuntimeError(f'Expected exactly one {platform} artifact')
    source = directories[0]
    if platform in ('macos', 'iOS'):
        # ditto archives were created on Apple runners before artifact transport.
        archives = list(source.glob('*.zip'))
        if len(archives) != 1: raise RuntimeError('Expected preserved Apple bundle')
        target = out / archives[0].name
        shutil.copy2(archives[0], target)
        with zipfile.ZipFile(target, 'a') as archive:
            for notice in [Path('LICENSE'), *Path('docs').glob('LICENSE*'), Path('docs/SOURCES.md'), Path('docs/NATIVE_VPN.md')]:
                archive.write(notice, 'FoxWay-notices/' + notice.name)
        continue
    for file in source.rglob('*'):
        if file.is_file() and (file.name in ('foxway', 'sing-box', 'awg', 'awg-quick', 'amneziawg-go') or file.parent.name == 'MacOS' or file.suffix in ('.so', '.dylib')):
            file.chmod(0o755)
    with zipfile.ZipFile(out / f'FoxWay-{source.name}.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
        for file in source.rglob('*'):
            archive.write(file, file.relative_to(source))
        for notice in [Path('LICENSE'), *Path('docs').glob('LICENSE*'), Path('docs/SOURCES.md'), Path('docs/NATIVE_VPN.md')]:
            archive.write(notice, 'FoxWay-notices/' + notice.name)
with (out / 'SHA256SUMS.txt').open('w') as sums:
    for file in sorted(out.iterdir()):
        if file.name != 'SHA256SUMS.txt':
            digest = hashlib.file_digest(file.open('rb'), 'sha256').hexdigest()
            sums.write(f'{digest}  {file.name}\n')
