param([Parameter(Mandatory=$true)][string]$Archive,[Parameter(Mandatory=$true)][string]$Digest,[Parameter(Mandatory=$true)][string]$Target,[Parameter(Mandatory=$true)][int]$AppPid)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$stage=$null; $backup=$null; $moved=$false; $installed=$false
try {
  if ($Digest -notmatch '^[0-9a-f]{64}$' -or (Get-FileHash -Algorithm SHA256 -LiteralPath $Archive).Hash.ToLower() -ne $Digest) { throw 'Digest mismatch' }
  $Target=[IO.Path]::GetFullPath($Target).TrimEnd('\')
  if (!(Test-Path -LiteralPath "$Target\foxway.exe") -or !(Test-Path -LiteralPath "$Target\data\flutter_assets") -or ((Get-Item -LiteralPath $Target).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Not a FoxWay bundle' }
  $parent=[IO.Directory]::GetParent($Target).FullName
  $stage=Join-Path $parent ('.foxway-update-'+[Guid]::NewGuid().ToString('N'))
  [IO.Directory]::CreateDirectory($stage) | Out-Null
  $prefix=$stage+'\';$names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase);$size=0L
  $zip=[IO.Compression.ZipFile]::OpenRead($Archive)
  try {
    foreach ($entry in $zip.Entries) {
      $path=[IO.Path]::GetFullPath((Join-Path $stage $entry.FullName))
      $size+=$entry.Length
      if (!$path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or $entry.FullName.Contains(':') -or (($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000 -or !$names.Add($path) -or $names.Count -gt 20000 -or $size -gt 2GB) { throw 'Unsafe archive' }
    }
    foreach ($required in @('foxway.exe','sing-box.exe','foxway-awg.exe','wintun.dll')) { if (!$names.Contains((Join-Path $stage $required))) { throw 'Incomplete bundle' } }
    foreach ($entry in $zip.Entries) {
      $path=[IO.Path]::GetFullPath((Join-Path $stage $entry.FullName))
      if ($entry.FullName.EndsWith('/')) { [IO.Directory]::CreateDirectory($path) | Out-Null; continue }
      [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path)) | Out-Null
      [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$path,$false)
    }
  } finally { $zip.Dispose() }
  Write-Output 'READY'
  $deadline=[DateTime]::UtcNow.AddSeconds(120)
  while (Get-Process -Id $AppPid -ErrorAction SilentlyContinue) { if ([DateTime]::UtcNow -ge $deadline) { throw 'Application did not exit' };Start-Sleep -Milliseconds 250 }
  $backup=$Target+'.previous-'+[Guid]::NewGuid().ToString('N')
  [IO.Directory]::Move($Target,$backup);$moved=$true
  [IO.Directory]::Move($stage,$Target);$installed=$true
  $p=Start-Process -FilePath "$Target\foxway.exe" -WorkingDirectory $Target -PassThru
  Start-Sleep -Seconds 2
  if ($p.HasExited -and $p.ExitCode -ne 0) { throw 'New application failed' }
} catch {
  if ($installed) { [IO.Directory]::Move($Target,$stage) }
  if ($moved) { [IO.Directory]::Move($backup,$Target);Start-Process -FilePath "$Target\foxway.exe" -ArgumentList '--foxway-update-failed' -WorkingDirectory $Target }
  'FoxWay update failed; existing installation restored when possible.' | Set-Content -LiteralPath ($PSCommandPath+'.log')
  exit 1
} finally {
  if ($stage -and (Test-Path -LiteralPath $stage)) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
