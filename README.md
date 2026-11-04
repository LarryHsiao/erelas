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
