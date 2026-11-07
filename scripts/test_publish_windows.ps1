# Tests for publish_windows.ps1 decision logic.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test_publish_windows.ps1
# Platforms: Windows (PowerShell 5.1+). The publish path itself needs a live
# release and the signing keys, so it is walked by hand, not here.
$ErrorActionPreference = 'Stop'
$script:failed = 0

function Check([string]$Name, $Expected, $Actual) {
  if ("$Expected" -eq "$Actual") { Write-Host "ok   - $Name" }
  else { Write-Host "FAIL - ${Name}: expected '$Expected', got '$Actual'"; $script:failed++ }
}

function Throws([scriptblock]$Block) {
  try { & $Block | Out-Null; return $false } catch { return $true }
}

$here = Split-Path -Parent $MyInvocation.MyCommand.Path

& {
  . (Join-Path $here 'publish_windows.ps1')

  $parts = Get-VersionParts @('name: erelas', 'version: 1.1.1+3')
  Check 'the version part is read' '1.1.1' $parts.Version
  Check 'the build part is read' '3' $parts.Build
  Check 'a pubspec without a build number is refused' $true (Throws { Get-VersionParts @('version: 1.1.1') })
  Check 'a pubspec without a version is refused' $true (Throws { Get-VersionParts @('name: erelas') })

  Check 'a missing release is created' 'create' (Assert-ReleaseState @() 'v1.1.1')
  $draft = @(@{ tagName = 'v1.1.1'; isDraft = $true })
  Check 'a draft is reused' 'reuse' (Assert-ReleaseState $draft 'v1.1.1')
  $public = @(@{ tagName = 'v1.1.1'; isDraft = $false })
  Check 'a public release is refused' $true (Throws { Assert-ReleaseState $public 'v1.1.1' })

  $one = @(@{ tagName = 'v1.1.1' }, @{ tagName = 'v1.0.0' })
  $twice = @(@{ tagName = 'v1.1.1' }, @{ tagName = 'v1.1.1' })
  Check 'exactly one release for the tag is accepted' $false (Throws { Assert-SingleRelease $one 'v1.1.1' })
  Check 'two releases for one tag are refused' $true (Throws { Assert-SingleRelease $twice 'v1.1.1' })
  Check 'no release for the tag is refused' $true (Throws { Assert-SingleRelease @(@{ tagName = 'v1.0.0' }) 'v1.1.1' })

  Check 'the signature is taken from sign_update output' 'SIG==' (Get-DsaSignature 'sparkle:dsaSignature="SIG==" length="0"')
  Check 'output without a signature is refused' $true (Throws { Get-DsaSignature 'nothing here' })

  $handoff = New-Handoff '1.2.0' 5 'erelas-setup-1.2.0.exe' 'SIG==' 2000 | ConvertFrom-Json
  $expected = 'windows|1.2.0|5|erelas-setup-1.2.0.exe|SIG==|2000'
  $actual = (@($handoff.os, $handoff.version, $handoff.build, $handoff.asset, $handoff.signature, $handoff.length)) -join '|'
  Check 'the handoff carries what publish_release.py reads' $expected $actual
}

& {
  . (Join-Path $here 'publish_windows.ps1')
  $savedPfx, $savedPw = $env:WINDOWS_CODESIGN_PFX_BASE64, $env:CERT_PASSWORD
  try {
    $env:WINDOWS_CODESIGN_PFX_BASE64 = $null; $env:CERT_PASSWORD = $null
    $vault = { param($field) if ($field -eq 'password') { 'PFX64==' } else { 'pw' } }
    Set-SigningEnv $vault
    Check 'the pfx is taken from the vault when unset' 'PFX64==' $env:WINDOWS_CODESIGN_PFX_BASE64
    Check 'the password is taken from the vault when unset' 'pw' $env:CERT_PASSWORD

    $env:WINDOWS_CODESIGN_PFX_BASE64 = 'by-hand'; $env:CERT_PASSWORD = 'by-hand-pw'
    Set-SigningEnv { throw 'the vault must not be asked' }
    Check 'values set by hand win over the vault' 'by-hand' $env:WINDOWS_CODESIGN_PFX_BASE64
    Check 'the password set by hand wins too' 'by-hand-pw' $env:CERT_PASSWORD

    $env:WINDOWS_CODESIGN_PFX_BASE64 = 'by-hand'; $env:CERT_PASSWORD = $null
    Set-SigningEnv $vault
    Check 'with only one value set, the vault supplies both' 'PFX64==' $env:WINDOWS_CODESIGN_PFX_BASE64

    $env:WINDOWS_CODESIGN_PFX_BASE64 = $null; $env:CERT_PASSWORD = $null
    Check 'an empty vault answer is refused' $true (Throws { Set-SigningEnv { param($field) '' } })
  } finally {
    $env:WINDOWS_CODESIGN_PFX_BASE64, $env:CERT_PASSWORD = $savedPfx, $savedPw
  }
}

# Assert-TagAtHead against real, throwaway repositories.
& {
  . (Join-Path $here 'publish_windows.ps1')
  $tmp = Join-Path ([IO.Path]::GetTempPath()) ("erelas-tag-test-" + [guid]::NewGuid())
  New-Item -ItemType Directory -Path $tmp | Out-Null
  Push-Location $tmp
  try {
    git init -q --bare -b main origin.git | Out-Null
    git init -q -b main work | Out-Null
    Set-Location work
    foreach ($kv in 'user.email=t@example.com', 'user.name=T', 'commit.gpgsign=false', 'tag.gpgsign=false') {
      git config $kv.Split('=')[0] $kv.Split('=')[1]
    }
    git remote add origin ..\origin.git
    Set-Content release.txt 'one'
    git add -A; git commit -q -m one
    git tag v1.2.0
    git push -q origin main v1.2.0 2>$null

    Check 'a tag at HEAD that main contains is accepted' $false (Throws { Assert-TagAtHead '1.2.0' })

    Set-Content release.txt 'two'
    git add -A; git commit -q -m two
    Check 'HEAD without the tag is refused' $true (Throws { Assert-TagAtHead '1.2.0' })

    git switch -q -c side
    Set-Content release.txt 'three'
    git add -A; git commit -q -m three
    git tag v1.3.0
    Check 'a tag that exists only locally is refused' $true (Throws { Assert-TagAtHead '1.3.0' })
    git push -q origin v1.3.0 2>$null
    Check 'a tag that origin/main does not contain is refused' $true (Throws { Assert-TagAtHead '1.3.0' })
  } finally {
    Pop-Location
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
  }
}

if ($script:failed -gt 0) { Write-Host "$script:failed failed"; exit 1 }
Write-Host 'all passed'
