# Releasing

A release is a git tag. This page is the specification of the TeamCity side;
the scripts it calls and the one-time machine setup are in the README's
*Releasing* section.

## The pipeline

```
tag v1.2.0
 ├─ Erelas_ReleaseMac      test → build → sign → notarize → upload .dmg + update-macos.json      ┐
 └─ Erelas_ReleaseWindows  test → build → sign → upload installer + update-windows.json          ┘
                                          both succeed (snapshot dependency)
                                                          ↓
                       Erelas_Publish:  python3 -I scripts/publish_release.py v1.2.0
                       promote the draft → ONE commit with both feed items → push to main
```

Each release build checks, after uploading, that exactly one release exists for
the tag: if both builds created the draft in the same instant, GitHub can keep
two, and the build fails loudly so you can merge them by hand.

The feed changes once, at the end, and only after both builds have uploaded. If
either build fails, the draft release stays and nobody is offered the release;
fix, then tag a new version (or re-run the failed build and then `Erelas_Publish`).
A copy that has already updated does not roll back, so the tag is the point of
no return. To withdraw a release, revert the feed commit; Pages updates in
about a minute.

## TeamCity configuration to create

Model: Orthanc's `Orthanc_Deploy` and `Orthanc_DeployWindows`.

**VCS root** `Erelas` — `https://github.com/LarryHsiao/erelas`, branch
specification `+:refs/tags/v*` (so tags, and only tags, are builds).

| Config | Agent requirement | Steps | Trigger |
|---|---|---|---|
| `Erelas_ReleaseMac` | `exists tools.xcode.version` | `fvm flutter test`, then `scripts/publish_macos.sh --publish` | none of its own; runs as a snapshot dependency of `Erelas_Publish` |
| `Erelas_ReleaseWindows` | `teamcity.agent.jvm.os.name contains Windows` | `fvm flutter test`, then `powershell -File scripts\publish_windows.ps1 -Publish` | none of its own; runs as a snapshot dependency of `Erelas_Publish` |
| `Erelas_Publish` | any agent with Python 3.9+, git and `gh` | `python3 -I scripts/publish_release.py %teamcity.build.branch%` (the script strips a leading `refs/tags/`) | **the one VCS trigger**, branch filter `+:v*`; snapshot dependencies on both release configs, which TeamCity then runs first, in parallel, and the job starts only if both succeed |

The trigger sits on `Erelas_Publish` because a snapshot dependency pulls the
builds in behind the job that depends on them, not the other way round.

The release configs run `fvm flutter test` first, as Orthanc's do; the
scripts also run `analyze` and the tests themselves (macOS) or are covered by
the test step (Windows). `Erelas_Publish` cannot retrigger itself: its push goes
to `main`, and the VCS root watches tags only.

## Parameters

| Parameter | On | Notes |
|---|---|---|
| `env.GH_TOKEN` | all three configs | `repo` scope; creates and uploads to the release, promotes it, and (Publish) pushes the feed commit to `main` |
| `env.IDENTITY` | `Erelas_ReleaseMac` | SHA-1 of the Developer ID Application identity |
| `env.WINDOWS_CODESIGN_PFX_BASE64`, `env.CERT_PASSWORD` | `Erelas_ReleaseWindows` | or leave unset and let the script read the Vaultwarden item `erelas-windows-codesign` |

Held on the agents, not in TeamCity: the notary profile `erelas-notary` and the
Sparkle EdDSA key (Mac keychain), and the Vaultwarden access that supplies the
WinSparkle DSA key (Windows agent). No signing key is needed by
`Erelas_Publish`: it only reads the signatures the builds recorded.

`Erelas_Publish` pushes to `main`, and `git push` does not use `GH_TOKEN` (that
authenticates only `gh`). The agent therefore needs a push credential of its
own: run `gh auth setup-git` there, or use an https remote that carries the
token. It also needs a git identity (`user.name` and `user.email`), because it
makes a commit. If `main` is protected, allow that identity to bypass. A refused
push fails loudly, with git's own reason in the message; the draft is already
promoted by then, and re-running the job is safe.

## Before the first release through it

- Walk one update on each platform by hand: install the previous version, let
  it find the new one, confirm it installs. The tests cover the scripts, not
  Sparkle's or WinSparkle's download-and-swap.
- The macOS signing step and `ensure_draft` run against real `gh` and Sparkle
  only on a Mac; they have been unit-tested with stand-ins, not run for real.
