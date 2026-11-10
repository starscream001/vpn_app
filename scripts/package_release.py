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
for platform in ('windows', 'linux', 'macos', 'iOS'):
    directories = [p for p in root.iterdir() if p.is_dir() and p.name.startswith(platform + '-')]
    if len(directories) != 1:
        raise RuntimeError(f'Expected exactly one {platform} artifact')
    source = directories[0]
    for file in source.rglob('*'):
        if file.is_file() and (file.name == 'foxway' or file.parent.name == 'MacOS' or file.suffix in ('.so', '.dylib')):
            file.chmod(0o755)
    with zipfile.ZipFile(out / f'FoxWay-{source.name}.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
        for file in source.rglob('*'):
            archive.write(file, file.relative_to(source))
with (out / 'SHA256SUMS.txt').open('w') as sums:
    for file in sorted(out.iterdir()):
        if file.name != 'SHA256SUMS.txt':
            digest = hashlib.file_digest(file.open('rb'), 'sha256').hexdigest()
            sums.write(f'{digest}  {file.name}\n')
