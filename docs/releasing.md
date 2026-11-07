# Releasing

A release is a git tag. This page describes the TeamCity side; the scripts it
calls and the one-time machine setup are in the README's *Releasing* section.

## The pipeline

```
tag v1.2.0
 ├─ Erelas_ReleaseMac      build → sign → notarize → upload .dmg + update-macos.json      ┐
 └─ Erelas_ReleaseWindows  test → build → sign → upload installer + update-windows.json   ┘
                                          both succeed (snapshot dependency)
                                                          ↓
                       Erelas_Publish:  python3 -I scripts/publish_release.py v1.2.0
                       promote the draft → ONE commit with both feed items → push to main
```

Each release build checks, after uploading, that exactly one release exists for
the tag: if both builds created the draft in the same instant, GitHub can keep
two, and the build fails loudly so you can merge them by hand.

The feed changes once, at the end, and only after both builds have uploaded. If
either build fails, `Erelas_Publish` is cancelled, the draft release stays, and
nobody is offered the release; fix, then tag a new version (or re-run the failed
build and then `Erelas_Publish`). A copy that has already updated does not roll
back, so the tag is the point of no return. To withdraw a release, revert the
feed commit; Pages updates in about a minute.

## The TeamCity project

Project `Erelas` (under the root project), with:

**VCS root** `Erelas_HttpsGithubComLarryHsiaoErelasRefsTagsV` — Git,
`https://github.com/LarryHsiao/erelas`, anonymous (the repository is public),
default branch `refs/heads/main`, branch specification `+:refs/tags/*`, so tags,
and only tags, are builds.

| Config | Agent requirement | Steps | Trigger |
|---|---|---|---|
| `Erelas_ReleaseMac` | `exists tools.xcode.version` | `scripts/publish_macos.sh --publish` (it runs `analyze` and the tests itself) | none of its own; runs as a snapshot dependency of `Erelas_Publish` |
| `Erelas_ReleaseWindows` | `teamcity.agent.jvm.os.name contains Windows` | `fvm flutter analyze` and `fvm flutter test`, then `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\publish_windows.ps1 -Publish` | none of its own; runs as a snapshot dependency of `Erelas_Publish` |
| `Erelas_Publish` | `teamcity.agent.jvm.os.name contains Mac` | give git the build's token and an identity, then `python3 -I scripts/publish_release.py "%teamcity.build.branch%"` (the script strips a leading `refs/tags/`) | **the one VCS trigger**, branch filter `+:v*`; snapshot dependencies on both release configs |

The trigger sits on `Erelas_Publish` because a snapshot dependency pulls the
builds in behind the job that depends on them, not the other way round. The
dependencies are set to cancel `Erelas_Publish` if either build fails or fails
to start, to run on any agent, and to use the same tag revision. `Erelas_Publish`
cannot retrigger itself: its push goes to `main`, and the VCS root watches tags
only.

`Erelas_Publish` runs on the Mac agent because `python3`, `git` and `gh` are
known to work there. `Erelas_ReleaseWindows` needs the Windows agent to be
connected; while it is offline the release waits in the queue.

## Parameters

Stored as password-type values, copied from Orthanc's deploy configs (the
Developer ID certificate and the notary API key are the team's, not the app's):

| Parameter | On | Notes |
|---|---|---|
| `env.GH_TOKEN` | the project, so all three configs | `repo` scope; creates and uploads to the release, promotes it, and (Publish) pushes the feed commit to `main` |
| `env.DEVELOPER_ID_CERT_BASE64`, `env.DEVELOPER_ID_CERT_PASSWORD` | `Erelas_ReleaseMac` | the Developer ID Application `.p12` |
| `env.NOTARY_API_KEY_BASE64`, `env.NOTARY_API_KEY_ID`, `env.NOTARY_API_ISSUER_ID` | `Erelas_ReleaseMac` | an App Store Connect API key |
| `env.KEYCHAIN_PASSWORD` | `Erelas_ReleaseMac` | any value; protects the throwaway keychain made for each run |
| `env.WINDOWS_CODESIGN_PFX_BASE64`, `env.CERT_PASSWORD` | `Erelas_ReleaseWindows` | or leave unset and let the script read the Vaultwarden item `erelas-windows-codesign` |

Because `DEVELOPER_ID_CERT_BASE64` is set, `publish_macos.sh` signs headlessly:
it builds a temporary keychain, takes the signing identity from it, and
notarizes with the API key, so neither `IDENTITY` nor the `erelas-notary`
profile is needed on the agent. Orthanc's CI script works the same way.

Held on the agents, not in TeamCity: the Sparkle EdDSA key (the Mac agent's
keychain, the same key Orthanc signs with) and the Vaultwarden access that
supplies the WinSparkle DSA key (the Windows agent). No signing key is needed by
`Erelas_Publish`: it only reads the signatures the builds recorded.

`Erelas_Publish` pushes to `main`, and `git push` does not use `GH_TOKEN` (that
authenticates only `gh`), so its step supplies the token to git itself. On the
Mac agent git already holds a saved GitHub login for a different account, which
answers git's credential question first and is refused (`403 Permission ... denied
to larryhsiao-jubo`, as the first run of 1.1.2 showed). The step therefore clears
git's helper list for that checkout (`credential.helper ''`) and adds an inline
helper that returns `x-access-token` and `$GH_TOKEN`; nothing is written to disk.
It also sets a git identity (`Larry Hsiao <bleakeraser1997@gmail.com>`, the one
the earlier feed commits carry), because it makes a commit. If `main` is
protected, allow that identity to bypass. A refused push fails loudly, with git's
own reason in the message; the draft is already promoted by then, and re-running
the job is safe.

To re-run only the publish job for a tag, queue `Erelas_Publish` on the tag's
branch and let TeamCity reuse the existing release builds; it will briefly list
them as queued, and they resolve to the earlier successful builds. Note that
TeamCity's build list shows only the default branch unless the locator carries
`branch:default:any`, so a tag build is invisible without it.

## Before the first release through it

- Walk one update on each platform by hand: install the previous version, let
  it find the new one, confirm it installs. The tests cover the scripts, not
  Sparkle's or WinSparkle's download-and-swap.
- Only the pure parts of the macOS headless signing are unit-tested: the check
  that every variable is set, and the choice of `notarytool` arguments. The
  keychain, `codesign`, `notarytool` and Sparkle-signing steps have never been
  run, and `ensure_draft` has been tested against a stand-in for `gh`, not the
  real one. The first tag is their first real run, so make it a release you can
  afford to redo, such as 1.1.2.
- The tag must be on a commit that already contains these scripts, so merge
  them to `main` before tagging.
