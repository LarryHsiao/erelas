<#
.SYNOPSIS
  Erelas — build a signed Windows installer on an unattended CI runner.

.DESCRIPTION
  Ported from Orthanc's scripts/build_windows.ps1. Designed to run
  end-to-end with no interactive agent: code-signing secrets arrive
  through environment variables, the script decodes the .pfx into a
  workspace temp file, signs the app .exe and the Inno installer .exe,
  and removes the .pfx on exit (success or failure).

  Prerequisites on the runner:
    - Flutter SDK reachable via `fvm flutter` (FVM on PATH)
    - Inno Setup 6 (ISCC.exe at default path or on PATH)
    - Windows SDK (signtool.exe on PATH)

  Required environment variables:
    WINDOWS_CODESIGN_PFX_BASE64  base64 of the code-signing .pfx
    CERT_PASSWORD                password for the .pfx

  Optional environment variables:
    TIMESTAMP_URL                TSA URL (default: "http://timestamp.digicert.com")
    OUTPUT_DIR                   where to drop artifacts (default: "build\publish")

  Outputs:
    $OUTPUT_DIR\erelas-setup-<version>.exe   signed installer

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_windows.ps1
#>

$ErrorActionPreference = 'Stop'

$AppName      = 'erelas'
$TimestampUrl = if ($env:TIMESTAMP_URL) { $env:TIMESTAMP_URL } else { 'http://timestamp.digicert.com' }
$OutputDir    = if ($env:OUTPUT_DIR)    { $env:OUTPUT_DIR }    else { 'build\publish' }

function Require-Env([string]$Name) {
  if ([string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($Name))) {
    throw "required environment variable $Name is not set"
  }
}
Require-Env 'WINDOWS_CODESIGN_PFX_BASE64'
Require-Env 'CERT_PASSWORD'

$versionLine = Select-String -Path pubspec.yaml -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)' |
  Select-Object -First 1
if (-not $versionLine) {
  throw "could not read version from pubspec.yaml"
}
$Version = $versionLine.Matches.Groups[1].Value
Write-Host "==> Version: $Version"

$DefaultIscc = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
if (Test-Path $DefaultIscc) {
  $Iscc = $DefaultIscc
} else {
  $cmd = Get-Command ISCC -ErrorAction SilentlyContinue
  if (-not $cmd) {
    throw "ISCC.exe not found at $DefaultIscc or on PATH"
  }
  $Iscc = $cmd.Source
}

$onPath = Get-Command signtool -ErrorAction SilentlyContinue
if ($onPath) {
  $SignTool = $onPath.Source
} else {
  $kitBin = "C:\Program Files (x86)\Windows Kits\10\bin"
  $candidate = Get-ChildItem $kitBin -Recurse -Filter signtool.exe -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\x64\\' } |
    Sort-Object FullName -Descending |
    Select-Object -First 1
  if (-not $candidate) {
    throw "signtool.exe not found on PATH or under $kitBin"
  }
  $SignTool = $candidate.FullName
}

$Pfx = Join-Path (Get-Location) 'windows-codesign.pfx'

try {
  Write-Host "==> Decoding code-signing certificate"
  [IO.File]::WriteAllBytes($Pfx, [Convert]::FromBase64String($env:WINDOWS_CODESIGN_PFX_BASE64))

  Write-Host "==> Resolving Flutter dependencies"
  & fvm flutter pub get
  if ($LASTEXITCODE -ne 0) { throw "fvm flutter pub get exited $LASTEXITCODE" }

  Write-Host "==> Building Windows release"
  & fvm flutter build windows --release
  if ($LASTEXITCODE -ne 0) { throw "fvm flutter build windows exited $LASTEXITCODE" }

  $ReleaseDir = "build\windows\x64\runner\Release"
  $AppExe = Join-Path $ReleaseDir "$AppName.exe"
  if (-not (Test-Path $AppExe)) {
    throw "built app not found at $AppExe"
  }

  Write-Host "==> Signing $AppExe"
  & $SignTool sign /f $Pfx /p $env:CERT_PASSWORD `
    /tr $TimestampUrl /td sha256 /fd sha256 $AppExe
  if ($LASTEXITCODE -ne 0) { throw "signtool (app) exited $LASTEXITCODE" }

  Write-Host "==> Compiling Inno installer"
  & $Iscc "/DMyAppVersion=$Version" 'installer\erelas.iss'
  if ($LASTEXITCODE -ne 0) { throw "ISCC exited $LASTEXITCODE" }
  $InstallerSrc = "build\installer\$AppName-setup-$Version.exe"
  if (-not (Test-Path $InstallerSrc)) {
    throw "installer not produced at $InstallerSrc"
  }

  Write-Host "==> Signing $InstallerSrc"
  & $SignTool sign /f $Pfx /p $env:CERT_PASSWORD `
    /tr $TimestampUrl /td sha256 /fd sha256 $InstallerSrc
  if ($LASTEXITCODE -ne 0) { throw "signtool (installer) exited $LASTEXITCODE" }

  New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
  $InstallerOut = Join-Path $OutputDir "$AppName-setup-$Version.exe"
  Copy-Item -Force $InstallerSrc $InstallerOut

  Write-Host "==> Done."
  Write-Host "    Installer: $InstallerOut"
}
finally {
  if (Test-Path $Pfx) { Remove-Item -Force $Pfx -ErrorAction SilentlyContinue }
}
