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
built commit. macOS only. There is no in-app update check yet.

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
```

The script refuses to run without `IDENTITY` or a working notary profile, on a
dirty tree, off `main`, with unpushed commits, or when `analyze` or the tests
fail. With `--publish` it also refuses when `gh` is not logged in, when the tag
already names another commit, or when the release exists and is not a draft at
the built commit. Its preflight checks are tested with `bash scripts/test_publish_macos.sh`.
