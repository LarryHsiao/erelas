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

## Releasing the macOS app

`scripts/publish_macos.sh` builds, signs, notarizes and staples
`build/publish/erelas.dmg`; with `--publish` it also uploads it to a **draft**
GitHub release `v<VERSION>` (the version in `pubspec.yaml`), tagged at the
built commit. macOS only. The app checks for updates itself (Sparkle), at launch
and once a day, or from the ◆ menu's "Check for Updates…".

One-time setup, on the releasing Mac:

```
security find-identity -v -p codesigning          # note the Developer ID Application hash
xcrun notarytool store-credentials erelas-notary --apple-id <Apple ID> --team-id 2SX9WGZ5F8
```

(`store-credentials` asks for an app-specific password from account.apple.com.)

Each release, from a clean, pushed `main` with the version bumped:

```
IDENTITY=<hash> scripts/publish_macos.sh --publish
gh release edit v<VERSION> --draft=false          # after looking at the draft
scripts/publish_feed_macos.sh                     # then offer it to installed copies
```

The feed step signs the public DMG with the Sparkle key in this Mac's keychain
(`macos/Pods/Sparkle/bin/generate_keys -p` prints the public half, which is
`SUPublicEDKey` in `Info.plist`), adds the release to `docs/appcast.xml` and
pushes it; GitHub Pages serves it at
`https://larryhsiao.github.io/erelas/appcast.xml`. Sparkle compares the build
number (the `+N` in `pubspec.yaml`), so every release needs a higher one. The
feed script refuses a draft release or a build lower than the feed's latest.
Version 1.0.0 contains no updater, so those copies must be replaced by hand
once, with the first release that includes Sparkle.

### Windows

```
powershell -File scripts\publish_windows.ps1 -Publish   # builds, signs, uploads to the same draft release
gh release edit v<VERSION> --draft=false          # after looking at the draft
powershell -File scripts\publish_feed_windows.ps1 # then offer it to installed copies
```

The signing certificate comes from `WINDOWS_CODESIGN_PFX_BASE64` and `CERT_PASSWORD` when
those are set, otherwise from the Vaultwarden item `erelas-windows-codesign` (password field =
base64 of the `.pfx`, notes field = its password). `publish_windows.ps1` needs Flutter (via `fvm`), Inno Setup 6 and `signtool`,
and the same clean, pushed `main` as the macOS script; without `-Publish` it
only builds `build\publish\erelas-setup-<VERSION>.exe`. The feed step adds a
`sparkle:os="windows"` item to the same `docs/appcast.xml`, leaving the macOS
item alone. WinSparkle compares the item's `sparkle:version` with the exe's
ProductVersion, which Flutter writes as `<version>+<build>` (`1.1.1+3`), so the
item carries that exact string and the build number must still rise every
release. Both steps read their secrets through `bash` (and so need `bw serve` running and unlocked, unless
the two variables are set by hand), so Git Bash must come before any WSL `bash.exe` on `PATH`. The installer is signed with the DSA key in Vaultwarden (item
`orthanc-winsparkle-dsa`, the one Orthanc uses); its public half is
`dsa_pub.pem`, compiled into the exe by `windows/runner/Runner.rc`. The private
half is read only while signing and is gitignored. Tested with
`powershell -File scripts\test_publish_windows.ps1`. The update flow itself
(download, verify, swap) is WinSparkle's and has not yet been walked on a
Windows machine; the first Windows release is the occasion to do so.

The script refuses to run without `IDENTITY` or a working notary profile, on a
dirty tree, off `main`, with unpushed commits, or when `analyze` or the tests
fail. With `--publish` it also refuses when `gh` is not logged in, when the tag
already names another commit, or when the release exists and is not a draft at
the built commit. The checks are tested with `bash scripts/test_publish_macos.sh` and
`bash scripts/test_publish_feed_macos.sh`, and the feed writer with
`python3 -I -m unittest discover -s scripts -p 'test_update_appcast.py'`.
