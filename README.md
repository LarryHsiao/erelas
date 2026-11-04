# Erelas

Keeps the TAIEX close in view: a desktop bar on macOS and Windows, an ongoing
notification on Android, a widget on iOS — one Flutter codebase.

- `writer/` — scheduled GitHub Action that fetches TWSE's daily index closes and
  publishes `docs/today.json` on GitHub Pages. Contract: `docs/today-contract.md`.
- `lib/`, `macos/` — the macOS client (step 1: plain window showing the close).

Source of the numbers: TWSE OpenAPI (open government data). Every client shows
"Source: TWSE".

```
python3 -I -m unittest discover -s writer   # writer tests
fvm flutter test                            # client tests (Flutter 3.47.9, see .fvmrc)
```
