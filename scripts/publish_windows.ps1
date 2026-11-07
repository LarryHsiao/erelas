<#
.SYNOPSIS
  Erelas - build the signed Windows installer; with -Publish, also upload it
  and its update handoff to the draft GitHub release v<VERSION>.

.DESCRIPTION
  Runs scripts\build_windows.ps1 (which needs WINDOWS_CODESIGN_PFX_BASE64 and
  CERT_PASSWORD - taken from the environment when both are set, else from the
  Vaultwarden item erelas-windows-codesign).

  With -Publish it then creates the draft release v<VERSION> if the macOS build
  has not already, signs the installer for WinSparkle (DSA key from the
  Vaultwarden item orthanc-winsparkle-dsa, the one Orthanc uses) and uploads
  build\publish\erelas-setup-<VERSION>.exe plus update-windows.json to it. It
  does NOT touch the update feed: scripts\publish_release.py does that once,
  after both platforms have uploaded.

  Refuses on a dirty tree. With -Publish it also refuses unless gh is logged
  in, HEAD carries the tag v<VERSION> and origin/main contains that tag; a
  release that exists is reused only while it is still a draft.

  This is what TeamCity runs on a tag build, so the tag IS the release decision.

  Platforms: Windows only (Inno Setup and signtool).
#>
param([switch]$Publish)
$ErrorActionPreference = 'Stop'

function Fail([string]$Message) { throw $Message }

# "version: 1.1.1+3" -> @{ Version = '1.1.1'; Build = '3' }; throws when absent.
function Get-VersionParts([string[]]$PubspecLines) {
  $line = $PubspecLines | Where-Object { $_ -match '^version:\s*(\d+\.\d+\.\d+)\+(\d+)' } | Select-Object -First 1
  if (-not $line) { Fail 'pubspec has no "version: x.y.z+N" line' }
  return @{ Version = $Matches[1]; Build = $Matches[2] }
}

function Assert-ReleaseState([object[]]$Releases, [string]$Tag) {
  $found = $Releases | Where-Object { $_.tagName -eq $Tag } | Select-Object -First 1
  if (-not $found) { return 'create' }
  if ($found.isDraft) { return 'reuse' }
  Fail "release $Tag is already public - bump the version"
}

function Assert-CleanTree {
  if (git status --porcelain) { Fail 'the working tree is not clean' }
}

# The release is decided by a tag: HEAD must carry v<version>, and main must
# contain it, so what ships is what was merged.
function Get-TagCommit([string[]]$LsRemote) {
  $peeled = $LsRemote | Where-Object { $_ -match '\^\{\}$' } | Select-Object -First 1
  $line = if ($peeled) { $peeled } else { $LsRemote | Select-Object -First 1 }
  return ($line -split '\s+')[0]
}

# Origin is asked, not the local tag list: a CI checkout may carry no local tag,
# and an unpushed local tag must not pass.
function Assert-TagAtHead([string]$Version) {
  $tag = "v$Version"
  $refs = @(git ls-remote origin "refs/tags/$tag" "refs/tags/$tag^{}")
  if ($LASTEXITCODE -ne 0) { Fail "could not ask origin about tag $tag" }
  if ($refs.Count -eq 0) { Fail "tag $tag is not on origin - push the tag to release" }
  if ((Get-TagCommit $refs) -ne (git rev-parse HEAD)) { Fail "tag $tag is not at HEAD" }
  git fetch -q origin main
  if ($LASTEXITCODE -ne 0) { Fail 'could not fetch origin/main' }
  git merge-base --is-ancestor HEAD origin/main
  if ($LASTEXITCODE -ne 0) { Fail "tag $tag is not contained in origin/main" }
}

# Two builds creating the draft in the same instant can each make one, splitting
# the assets; better to stop loudly than to leave that for the feed job to find.
function Assert-SingleRelease([object[]]$Releases, [string]$Tag) {
  $count = @($Releases | Where-Object { $_.tagName -eq $Tag }).Count
  if ($count -ne 1) {
    Fail "expected exactly one release for $Tag, found $count - two builds may each have created a draft; merge them by hand"
  }
}

function Assert-GhLoggedIn {
  # gh prints status to stderr; under 'Stop', Windows PowerShell 5.1 would turn
  # that into an error before the exit code is read.
  $ErrorActionPreference = 'Continue'
  cmd /c 'gh auth status >nul 2>&1'
  $loggedIn = ($LASTEXITCODE -eq 0)
  $ErrorActionPreference = 'Stop'
  if (-not $loggedIn) { Fail 'gh is not logged in' }
}

# Secrets come from Vaultwarden through secret.sh (Git Bash must come before any
# WSL bash.exe on PATH). Nothing here is written to disk or printed.
function Read-VaultField([string]$Item, [string]$Field) {
  try { $out = & bash "$HOME/.claude/hooks/secret.sh" $Item $Field - }
  catch { return $null }
  if ($LASTEXITCODE -ne 0) { return $null }
  return ($out -join '')
}

# The code-signing certificate: values already in the environment win; otherwise
# the Vaultwarden item erelas-windows-codesign (password field = base64 of the
# .pfx, notes field = its password). Set for this process only, so
# build_windows.ps1 inherits them.
function Set-SigningEnv([scriptblock]$Read = { param($field) Read-VaultField 'erelas-windows-codesign' $field }) {
  if ($env:WINDOWS_CODESIGN_PFX_BASE64 -and $env:CERT_PASSWORD) { return }
  $pfx = & $Read 'password'
  $password = & $Read 'notes'
  if ([string]::IsNullOrWhiteSpace($pfx) -or [string]::IsNullOrWhiteSpace($password)) {
    Fail 'could not read the code-signing certificate from Vaultwarden (item: erelas-windows-codesign); set WINDOWS_CODESIGN_PFX_BASE64 and CERT_PASSWORD by hand instead'
  }
  $env:WINDOWS_CODESIGN_PFX_BASE64 = $pfx.Trim()
  $env:CERT_PASSWORD = $password.Trim()
}

# sign_update prints: sparkle:dsaSignature="..." length="0". The length it
# prints on Windows is always 0, so only the signature is taken from it.
function Get-DsaSignature([string]$SignOutput) {
  if ($SignOutput -notmatch 'sparkle:dsaSignature="([^"]+)"') {
    Fail "no signature in sign_update output: $SignOutput"
  }
  return $Matches[1]
}

# sign_update reads dsa_priv.pem from the working directory; it is gitignored and
# removed in the finally block.
function Get-InstallerSignature([string]$Installer) {
  $b64 = Read-VaultField 'orthanc-winsparkle-dsa' 'password'
  if ([string]::IsNullOrWhiteSpace($b64)) {
    Fail 'could not read the WinSparkle key from Vaultwarden (item: orthanc-winsparkle-dsa)'
  }
  $key = Join-Path (Get-Location) 'dsa_priv.pem'
  [IO.File]::WriteAllBytes($key, [Convert]::FromBase64String($b64.Trim()))
  try {
    $out = & fvm dart run auto_updater:sign_update $Installer
    if ($LASTEXITCODE -ne 0) { Fail "sign_update exited $LASTEXITCODE" }
    return Get-DsaSignature ($out -join "`n")
  } finally {
    Remove-Item -Force $key -ErrorAction SilentlyContinue
  }
}

# What scripts\publish_release.py reads to write this platform's feed item.
function New-Handoff([string]$Version, [int]$Build, [string]$Asset, [string]$Signature, [long]$Length) {
  [ordered]@{
    os = 'windows'; version = $Version; build = $Build
    asset = $Asset; signature = $Signature; length = $Length
  } | ConvertTo-Json
}

function Get-DraftState([string]$Tag) {
  $releases = gh release list --limit 100 --json tagName,isDraft | ConvertFrom-Json
  return Assert-ReleaseState $releases $Tag
}

# The macOS build may create the draft in the same moment; a failed create is
# fine when the draft is there afterwards.
function Initialize-Release([string]$Tag) {
  if ((Get-DraftState $Tag) -eq 'reuse') { return }
  Write-Host "==> Creating draft release $Tag"
  gh release create $Tag --draft --verify-tag --title $Tag --generate-notes
  if ($LASTEXITCODE -eq 0) { return }
  $code = $LASTEXITCODE
  if ((Get-DraftState $Tag) -ne 'reuse') { Fail "gh release create exited $code" }
}

function Write-Utf8NoBom([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}

function Publish-Release([hashtable]$Parts, [string]$Installer) {
  $tag = "v$($Parts.Version)"
  Initialize-Release $tag
  $file = Get-Item $Installer
  $signature = Get-InstallerSignature $file.FullName
  $handoff = Join-Path $file.DirectoryName 'update-windows.json'
  Write-Utf8NoBom $handoff (New-Handoff $Parts.Version $Parts.Build $file.Name $signature $file.Length)
  gh release upload $tag $file.FullName $handoff --clobber
  if ($LASTEXITCODE -ne 0) { Fail "gh release upload exited $LASTEXITCODE" }
  Assert-SingleRelease @(gh release list --limit 100 --json tagName | ConvertFrom-Json) $tag
  Write-Host "==> $($file.Name) and update-windows.json uploaded to the draft $tag"
}

function Main {
  Set-Location (git rev-parse --show-toplevel)
  Assert-CleanTree
  $parts = Get-VersionParts (Get-Content pubspec.yaml)
  if ($Publish) { Assert-GhLoggedIn; Assert-TagAtHead $parts.Version }
  Set-SigningEnv
  & powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_windows.ps1
  if ($LASTEXITCODE -ne 0) { Fail "build_windows.ps1 exited $LASTEXITCODE" }
  if ($Publish) { Publish-Release $parts "build\publish\erelas-setup-$($parts.Version).exe" }
}

if ($MyInvocation.InvocationName -ne '.') { Main }
