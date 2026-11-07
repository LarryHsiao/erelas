# Erelas

Keeps the TAIEX close in view: a desktop bar on macOS and Windows, an ongoing
notification on Android, a widget on iOS — one Flutter codebase.

- `writer/` — scheduled GitHub Action that fetches TWSE's daily index closes and
  publishes `docs/today.json` on GitHub Pages. Contract: `docs/today-contract.md`.
- `lib/` — the desktop client, shared by macOS and Windows: a borderless
  always-on-top bar with the TAIEX close, a looping 今日焦點 crawl of sector
  indices, a tap-to-open detail drawer, and a tray item to hide, show and quit.
  It reloads every 15 minutes.
- `macos/` — the macOS runner. Run and checked on a Mac.
- `windows/` — the Windows runner. It compiles in CI (`client-ci`) but has not
  yet been run on a Windows machine, so docking and the tray are unverified.
- Android and iOS clients are not started.

Source of the numbers: TWSE OpenAPI (open government data). Every client shows
"Source: TWSE".

```
python3 -I -m unittest discover -s writer   # writer tests
fvm flutter test                            # client tests (Flutter 3.47.9, see .fvmrc)
```

## Releasing

**A release is a tag.** Push `v<VERSION>` (the version in `pubspec.yaml`, with
its `+N` build number raised, on a commit that `main` contains) and the
pipeline in [`docs/releasing.md`](docs/releasing.md) runs by itself:

1. TeamCity builds, signs and uploads both platforms to a **draft** GitHub
   release `v<VERSION>`: the macOS `.dmg` and the Windows installer. Each build
   also uploads an `update-<os>.json` holding its own Sparkle or WinSparkle
   signature, made on that platform's machine.
2. When both have uploaded, `scripts/publish_release.py` promotes the draft and
   adds both items to `docs/appcast.xml` in **one commit** to `main`; GitHub
   Pages serves it at `https://larryhsiao.github.io/erelas/appcast.xml`. If
   either build fails, the draft stays and the feed is not touched.
3. Installed apps check at launch and once a day (Sparkle on macOS, WinSparkle
   on Windows), or from the tray menu's "Check for Updates…".

Sparkle and WinSparkle compare the build number, so every release needs a
higher one; the feed writer refuses a lower build than the platform's latest.
Version 1.0.0 contains no updater, so those copies must be replaced by hand
once, with the first release that includes it.

### What runs on each machine

On the Mac, for a tag build (TeamCity runs it headlessly; see below for both ways):

```
IDENTITY=<hash> scripts/publish_macos.sh --publish
```

It builds, signs, notarizes and staples `build/publish/erelas.dmg`, signs it for
Sparkle with the key in the Mac's keychain (`macos/Pods/Sparkle/bin/generate_keys
-p` prints the public half, which is `SUPublicEDKey` in `Info.plist`), and
uploads both to the draft. Without `--publish` it only builds. With `--publish`
it refuses unless HEAD carries the tag `v<VERSION>` and `origin/main` contains
it; without, it wants a clean, pushed `main`. Either way it refuses without
signing credentials, on a dirty tree, or when `analyze` or the tests fail.

Signing credentials come one of two ways. A **headless** run (TeamCity) sets
`DEVELOPER_ID_CERT_BASE64` and the other variables listed in the script's header:
it builds a throwaway keychain from them and notarizes with an API key, so it
needs no signing identity or notary profile installed on the machine (it still
needs Xcode, Flutter via `fvm`, CocoaPods, `gh`, and the Sparkle key in the
keychain). An **interactive** run uses `IDENTITY` and
a stored notary profile instead, set up once on the Mac:

```
security find-identity -v -p codesigning          # note the Developer ID Application hash
xcrun notarytool store-credentials erelas-notary --apple-id <Apple ID> --team-id 2SX9WGZ5F8
```

(`store-credentials` asks for an app-specific password from account.apple.com.)

On Windows, for a tag build:

```
powershell -File scripts\publish_windows.ps1 -Publish
```

It builds and signs `build\publish\erelas-setup-<VERSION>.exe` (Flutter via
`fvm`, Inno Setup 6, `signtool`), signs it for WinSparkle, and uploads both to
the same draft. Without `-Publish` it only builds. With `-Publish` it refuses
unless HEAD carries the tag and `origin/main` contains it. The code-signing
certificate comes from `WINDOWS_CODESIGN_PFX_BASE64` and `CERT_PASSWORD` when
set, otherwise from the Vaultwarden item `erelas-windows-codesign` (password
field = base64 of the `.pfx`, notes field = its password). The update key is the
DSA key in the Vaultwarden item `orthanc-winsparkle-dsa` (the one Orthanc uses);
its public half is `dsa_pub.pem`, compiled into the exe by
`windows/runner/Runner.rc`. The private half is read only while signing and is
gitignored. Secrets are read through `bash`, so `bw serve` must be running and
unlocked, and Git Bash must come before any WSL `bash.exe` on `PATH`. The
certificate is self-signed, so Windows shows a SmartScreen warning on a fresh
download; updates are unaffected, because WinSparkle checks the DSA signature.

Anywhere with Python, git and `gh`, once per release (TeamCity runs it after
both uploads):

```
python3 -I scripts/publish_release.py v<VERSION>
```

It refuses, changing nothing, unless the tree is clean, the tag is on origin and
in `origin/main` and equals `v` plus the pubspec version, and both handoff files
name this version and build with an asset whose size on the release equals the
size that was signed. It runs on a throwaway checkout of `origin/main`, so the
caller's tree is never touched, rebases over a lost push race, and aborts on a
conflicting edit instead of forcing. Re-running it after a partial failure is
safe.

### Tests

```
bash scripts/test_publish_macos.sh                              # macOS script checks
powershell -File scripts\test_publish_windows.ps1               # Windows script checks
python3 -I -m unittest discover -s scripts                      # feed writer and release job
```

The scripts' tests also run in CI (`script-tests`) on every change under
`scripts/` or `installer/`: the Python tests on Linux, macOS and Windows, the
macOS script checks on Linux and on macOS's own bash 3.2, and the Windows checks
in Windows PowerShell 5.1.

The update flow itself (download, verify, swap) belongs to Sparkle and
WinSparkle and is not run by these tests. Release 1.1.2 ran the macOS signing
and both builds through the pipeline for real; an installed copy updating on
either platform has not yet been walked.
