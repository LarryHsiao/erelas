<#
.SYNOPSIS
  Erelas - offer a released Windows version to installed copies, through the
  update feed (docs/appcast.xml, served by GitHub Pages).

.DESCRIPTION
  Run it AFTER the release is public: the feed points at the release's real
  download URL, and the DSA signature is taken from the very installer users
  download, not the local build. Adds the Windows item (leaving the macOS one
  alone), commits docs/appcast.xml and pushes it to main.

  Usage: scripts\publish_feed_windows.ps1 [vX.Y.Z]   (default: v<pubspec version>)

  Refuses unless the tree is clean, on main, level with origin/main, the tag is
  on origin and contained in main, and the release is not a draft. A build
  lower than the feed's latest Windows build is refused by update_appcast.py.
  Never resets or force-pushes; a lost push race is rebased, a conflicting feed
  edit is aborted and reported.

  The DSA private key is read from Vaultwarden (item orthanc-winsparkle-dsa,
  password field = base64 of dsa_priv.pem - the key Orthanc signs with, reused
  on purpose) through ~/.claude/hooks/secret.sh, written to dsa_priv.pem only
  for the length of the signing call and removed after it.

  Platforms: Windows only (PowerShell; needs bash for secret.sh - Git Bash must
  come before any WSL bash.exe on PATH - plus gh, fvm and python3).
#>
param([string]$Tag)
$ErrorActionPreference = 'Stop'

$Feed = 'docs/appcast.xml'
$RepoSlug = 'LarryHsiao/erelas'
$MaxPushAttempts = 5

function Fail([string]$Message) { throw $Message }

function Get-VersionParts([string[]]$PubspecLines) {
  $line = $PubspecLines | Where-Object { $_ -match '^version:\s*(\d+\.\d+\.\d+)\+(\d+)' } | Select-Object -First 1
  if (-not $line) { Fail 'pubspec has no "version: x.y.z+N" line' }
  return @{ Version = $Matches[1]; Build = $Matches[2] }
}

# sign_update prints: sparkle:dsaSignature="..." length="0". The length it
# prints on Windows is always 0, so only the signature is taken from it.
function Get-DsaSignature([string]$SignOutput) {
  if ($SignOutput -notmatch 'sparkle:dsaSignature="([^"]+)"') {
    Fail "no signature in sign_update output: $SignOutput"
  }
  return $Matches[1]
}

function Assert-ReleasePublic([string]$Tag) {
  $draft = gh release view $Tag --json isDraft --jq .isDraft
  if ($LASTEXITCODE -ne 0) { Fail "no GitHub release $Tag" }
  if ($draft -ne 'false') { Fail "release $Tag is still a draft - promote it first" }
}

function Assert-TagInMain([string]$Tag) {
  git fetch -q origin main "refs/tags/${Tag}:refs/tags/$Tag"
  if ($LASTEXITCODE -ne 0) { Fail "could not fetch main and tag $Tag from origin" }
  git merge-base --is-ancestor "${Tag}^{commit}" origin/main
  if ($LASTEXITCODE -ne 0) { Fail "tag $Tag is not contained in origin/main" }
}

function Assert-ReadyToPublish([string]$Tag) {
  if (git status --porcelain) { Fail 'the working tree is not clean' }
  $branch = git rev-parse --abbrev-ref HEAD
  if ($branch -ne 'main') { Fail "not on main (on $branch)" }
  git fetch -q origin main
  if (git rev-list 'origin/main..HEAD') { Fail 'unpushed commits on main' }
  if (git rev-list 'HEAD..origin/main') { Fail 'main is behind origin/main - pull first' }
  Assert-TagInMain $Tag
  Assert-ReleasePublic $Tag
}

function Get-Installer([string]$Tag, [string]$Dir) {
  $name = "erelas-setup-$($Tag.TrimStart('v')).exe"
  gh release download $Tag -p $name -D $Dir --clobber
  if ($LASTEXITCODE -ne 0) { Fail "could not download $name from $Tag" }
  return Get-Item (Join-Path $Dir $name)
}

# Signs with the key from Vaultwarden. sign_update reads dsa_priv.pem from the
# working directory; it is gitignored and removed in the finally block.
function Get-InstallerSignature([string]$Installer) {
  $b64 = & bash "$HOME/.claude/hooks/secret.sh" orthanc-winsparkle-dsa password
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($b64)) {
    Fail 'could not read the WinSparkle key from Vaultwarden (item: orthanc-winsparkle-dsa)'
  }
  $key = Join-Path (Get-Location) 'dsa_priv.pem'
  [IO.File]::WriteAllBytes($key, [Convert]::FromBase64String($b64))
  try {
    $out = & fvm dart run auto_updater:sign_update $Installer
    if ($LASTEXITCODE -ne 0) { Fail "sign_update exited $LASTEXITCODE" }
    return Get-DsaSignature ($out -join "`n")
  } finally {
    Remove-Item -Force $key -ErrorAction SilentlyContinue
  }
}

function Add-FeedItem([string]$Tag, [hashtable]$Parts, [string]$Signature, [long]$Length) {
  $url = "https://github.com/$RepoSlug/releases/download/$Tag/erelas-setup-$($Parts.Version).exe"
  $date = (Get-Date).ToUniversalTime().ToString('ddd, dd MMM yyyy HH:mm:ss +0000', [Globalization.CultureInfo]::InvariantCulture)
  python3 -I scripts/update_appcast.py --appcast $Feed --os windows `
    --version $Parts.Version --build $Parts.Build --pub-date $date `
    --url $url --length $Length --dsa-signature $Signature
  if ($LASTEXITCODE -ne 0) { Fail "update_appcast.py exited $LASTEXITCODE" }
  try { [xml](Get-Content -Raw $Feed) | Out-Null }
  catch { Fail "$Feed is not valid XML after the update" }
}

# Pushes the feed commit, rebasing over whatever landed on main meanwhile (the
# data writer commits there too). A conflict is aborted, never forced.
function Push-Feed {
  for ($attempt = 1; $attempt -le $MaxPushAttempts; $attempt++) {
    git push origin HEAD:main
    if ($LASTEXITCODE -eq 0) { return }
    Write-Host "==> push lost a race (attempt $attempt/$MaxPushAttempts), rebasing"
    git fetch -q origin main
    git rebase origin/main
    if ($LASTEXITCODE -ne 0) {
      git rebase --abort
      Fail "feed edit conflicts with origin/main - reconcile $Feed by hand (after checking git log origin/main.., drop the local feed commit with: git reset --keep origin/main)"
    }
  }
  Fail "could not push the feed after $MaxPushAttempts attempts"
}

function Main {
  Set-Location (git rev-parse --show-toplevel)
  if (-not $Tag) { $Tag = 'v' + (Get-VersionParts (Get-Content pubspec.yaml)).Version }
  Assert-ReadyToPublish $Tag
  $parts = Get-VersionParts (git show "${Tag}:pubspec.yaml")
  if ("v$($parts.Version)" -ne $Tag) { Fail "tag $Tag holds pubspec version $($parts.Version)" }
  $work = Join-Path ([IO.Path]::GetTempPath()) ("erelas-feed-" + [guid]::NewGuid())
  New-Item -ItemType Directory -Path $work | Out-Null
  try {
    $installer = Get-Installer $Tag $work
    $signature = Get-InstallerSignature $installer.FullName
    Add-FeedItem $Tag $parts $signature $installer.Length
  } catch {
    git checkout -- $Feed
    throw
  } finally {
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
  }
  git add $Feed
  git commit -m "Publish $Tag (Windows) to the update feed"
  if ($LASTEXITCODE -ne 0) { Fail "git commit exited $LASTEXITCODE" }
  Push-Feed
  Write-Host "==> $Feed now lists $Tag (Windows, build $($parts.Build)); Pages serves it in a minute or so"
}

if ($MyInvocation.InvocationName -ne '.') { Main }
