<#
.SYNOPSIS
  Erelas - build the signed Windows installer; with -Publish, also upload it
  to the draft GitHub release v<VERSION>.

.DESCRIPTION
  Runs scripts\build_windows.ps1 (which needs WINDOWS_CODESIGN_PFX_BASE64 and
  CERT_PASSWORD - taken from the environment when both are set, else from the
  Vaultwarden item erelas-windows-codesign), then with -Publish uploads build\publish\erelas-setup-<VERSION>.exe
  to a draft release tagged at the built commit - the same release the macOS
  script fills with the .dmg. A release that exists is reused only while it is
  still a draft at this commit; a public one is never touched.

  Refuses on a dirty tree, off main, with unpushed commits, and (with -Publish)
  when gh is not logged in.

  After looking at the draft:
    gh release edit v<VERSION> --draft=false
    powershell -File scripts\publish_feed_windows.ps1   # offer it to installed copies

  Platforms: Windows only (Inno Setup and signtool).
#>
param([switch]$Publish)
$ErrorActionPreference = 'Stop'

$ReleaseBranch = 'main'

function Fail([string]$Message) { throw $Message }

# "version: 1.1.1+3" -> "1.1.1"; throws when the line is absent.
function Get-Version([string[]]$PubspecLines) {
  $line = $PubspecLines | Where-Object { $_ -match '^version:\s*(\d+\.\d+\.\d+)' } | Select-Object -First 1
  if (-not $line) { Fail 'could not read the version from pubspec.yaml' }
  return $Matches[1]
}

function Assert-ReleaseState([object[]]$Releases, [string]$Tag, [string]$Head) {
  $found = $Releases | Where-Object { $_.tagName -eq $Tag } | Select-Object -First 1
  if (-not $found) { return 'create' }
  if ($found.isDraft -and $found.targetCommitish -eq $Head) { return 'reuse' }
  Fail "release $Tag exists and is not a draft at $Head - delete it or bump the version"
}

function Assert-CleanTree {
  if (git status --porcelain) { Fail 'the working tree is not clean' }
}

function Assert-OnReleaseBranch {
  $branch = git rev-parse --abbrev-ref HEAD
  if ($branch -ne $ReleaseBranch) { Fail "not on $ReleaseBranch (on $branch)" }
}

function Assert-Pushed {
  git fetch -q origin $ReleaseBranch
  if ($LASTEXITCODE -ne 0) { Fail 'could not fetch origin' }
  if (git rev-list "origin/$ReleaseBranch..HEAD") { Fail "unpushed commits on $ReleaseBranch" }
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

# The code-signing certificate: values already in the environment win; otherwise
# they come from the Vaultwarden item erelas-windows-codesign (password field =
# base64 of the .pfx, notes field = its password) through secret.sh. They are
# set for this process only, so build_windows.ps1 inherits them and nothing is
# written to disk.
function Read-VaultField([string]$Field) {
  try { $out = & bash "$HOME/.claude/hooks/secret.sh" erelas-windows-codesign $Field - }
  catch { return $null }
  if ($LASTEXITCODE -ne 0) { return $null }
  return ($out -join '')
}

function Set-SigningEnv([scriptblock]$Read = { param($field) Read-VaultField $field }) {
  if ($env:WINDOWS_CODESIGN_PFX_BASE64 -and $env:CERT_PASSWORD) { return }
  $pfx = & $Read 'password'
  $password = & $Read 'notes'
  if ([string]::IsNullOrWhiteSpace($pfx) -or [string]::IsNullOrWhiteSpace($password)) {
    Fail 'could not read the code-signing certificate from Vaultwarden (item: erelas-windows-codesign); set WINDOWS_CODESIGN_PFX_BASE64 and CERT_PASSWORD by hand instead'
  }
  $env:WINDOWS_CODESIGN_PFX_BASE64 = $pfx.Trim()
  $env:CERT_PASSWORD = $password.Trim()
}

function Publish-Release([string]$Tag, [string]$Installer) {
  $head = git rev-parse HEAD
  $releases = gh release list --limit 100 --json tagName,isDraft,targetCommitish | ConvertFrom-Json
  if ((Assert-ReleaseState $releases $Tag $head) -eq 'create') {
    Write-Host "==> Creating draft release $Tag at $($head.Substring(0, 7))"
    gh release create $Tag --draft --title $Tag --generate-notes --target $head
    if ($LASTEXITCODE -ne 0) { Fail "gh release create exited $LASTEXITCODE" }
  }
  gh release upload $Tag $Installer --clobber
  if ($LASTEXITCODE -ne 0) { Fail "gh release upload exited $LASTEXITCODE" }
  gh release view $Tag --json url,isDraft --jq '"==> \(.url)  draft=\(.isDraft)"'
}

function Main {
  Set-Location (git rev-parse --show-toplevel)
  Assert-CleanTree
  Assert-OnReleaseBranch
  Assert-Pushed
  if ($Publish) { Assert-GhLoggedIn }
  Set-SigningEnv
  $version = Get-Version (Get-Content pubspec.yaml)
  & powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_windows.ps1
  if ($LASTEXITCODE -ne 0) { Fail "build_windows.ps1 exited $LASTEXITCODE" }
  if ($Publish) { Publish-Release "v$version" "build\publish\erelas-setup-$version.exe" }
}

if ($MyInvocation.InvocationName -ne '.') { Main }
