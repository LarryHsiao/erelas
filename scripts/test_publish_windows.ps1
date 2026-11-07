# Tests for publish_windows.ps1 and publish_feed_windows.ps1 decision logic.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test_publish_windows.ps1
# Platforms: Windows (PowerShell 5.1+). The publish paths themselves need a
# live release and the signing key, so they are walked by hand, not here.
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

# Each script is loaded in its own scope: they define functions of the same name.
& {
  . (Join-Path $here 'publish_windows.ps1')
  $head = 'abc123'

  Check 'version is read without the build suffix' '1.1.1' (Get-Version @('name: erelas', 'version: 1.1.1+3'))
  Check 'a pubspec without a version is refused' $true (Throws { Get-Version @('name: erelas') })
  Check 'a missing release is created' 'create' (Assert-ReleaseState @() 'v1.1.1' $head)
  $draft = @(@{ tagName = 'v1.1.1'; isDraft = $true; targetCommitish = $head })
  Check 'a draft at this commit is reused' 'reuse' (Assert-ReleaseState $draft 'v1.1.1' $head)
  $other = @(@{ tagName = 'v1.1.1'; isDraft = $true; targetCommitish = 'zzz' })
  Check 'a draft at another commit is refused' $true (Throws { Assert-ReleaseState $other 'v1.1.1' $head })
  $public = @(@{ tagName = 'v1.1.1'; isDraft = $false; targetCommitish = $head })
  Check 'a public release is refused' $true (Throws { Assert-ReleaseState $public 'v1.1.1' $head })
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

& {
  . (Join-Path $here 'publish_feed_windows.ps1')

  $parts = Get-VersionParts @('version: 1.1.1+3')
  Check 'feed version part' '1.1.1' $parts.Version
  Check 'feed build part' '3' $parts.Build
  Check 'a pubspec without a build number is refused' $true (Throws { Get-VersionParts @('version: 1.1.1') })
  Check 'the signature is taken from sign_update output' 'SIG==' (Get-DsaSignature 'sparkle:dsaSignature="SIG==" length="0"')
  Check 'output without a signature is refused' $true (Throws { Get-DsaSignature 'nothing here' })
}

if ($script:failed -gt 0) { Write-Host "$script:failed failed"; exit 1 }
Write-Host 'all passed'
