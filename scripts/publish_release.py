#!/usr/bin/env python3
"""Publish a release to the update feed: promote the draft, then write both
platforms' items in ONE commit to main.

Usage:  python3 -I scripts/publish_release.py v1.2.0

Run once per release, after BOTH platform builds have uploaded to the draft
release v<version>. Each build signs its own artifact on its own machine and
leaves an update-<os>.json beside it (os, version, build, asset, signature,
length); this job needs no signing keys. It refuses, changing nothing, unless:
the working tree is clean; the tag is on origin and contained in origin/main;
the tag equals v<version> of pubspec.yaml at that tag; the release holds both
handoff files, each naming this version and build and an asset whose size on
the release equals the recorded length.

Only then does it promote the draft (a release that is already public is left
alone) and add the two feed items on a fresh checkout of origin/main, so the
caller's tree is never touched. The draft is promoted FIRST on purpose: a feed
that named a draft's asset URLs would send every installed app to a 404, while
a public release the feed does not list yet is harmless, and re-running fixes it. A lost push race is rebased; a conflicting
feed edit is aborted and reported, never forced. Re-running after a partial
failure is safe: the feed writer replaces an item of the same build.

Platforms: any with Python 3.9+, git and the gh CLI (standard library only).
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import update_appcast as appcast  # noqa: E402

REPO_SLUG = "LarryHsiao/erelas"
FEED = os.path.join("docs", "appcast.xml")
HANDOFFS = {appcast.MACOS: "update-macos.json", appcast.WINDOWS: "update-windows.json"}
MAX_PUSH_ATTEMPTS = 5


class ReleaseError(Exception):
    pass


@dataclass(frozen=True)
class Handoff:
    os: str
    version: str
    build: int
    asset: str
    signature: str
    length: int


def run(args, cwd=None):
    done = subprocess.run(args, cwd=cwd, capture_output=True, text=True)
    if done.returncode != 0:
        raise ReleaseError(f"{' '.join(args[:3])} failed: {done.stderr.strip()}")
    return done.stdout.strip()


def git(*args, cwd=None):
    return run(["git", *args], cwd=cwd)


class Gh:
    """The release, as the gh CLI sees it."""

    def __init__(self, slug=REPO_SLUG):
        self._repo = ["--repo", slug]

    def view(self, tag):
        text = run(["gh", "release", "view", tag, *self._repo, "--json", "isDraft,assets"])
        return json.loads(text)

    def download(self, tag, name, directory):
        run(["gh", "release", "download", tag, *self._repo, "-p", name,
             "-D", directory, "--clobber"])
        return os.path.join(directory, name)

    def promote(self, tag):
        run(["gh", "release", "edit", tag, *self._repo, "--draft=false"])


def tag_from_ref(ref):
    """TeamCity's %teamcity.build.branch% may be the full ref: refs/tags/v1.2.0."""
    return re.sub(r"^refs/tags/", "", ref)


def pubspec_version(text):
    found = re.search(r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)", text, re.MULTILINE)
    if not found:
        raise ReleaseError('pubspec has no "version: x.y.z+N" line')
    return found.group(1), int(found.group(2))


def parse_handoff(text, os_name, version, build, sizes, name):
    try:
        data = json.loads(text)
        found = Handoff(data["os"], data["version"], int(data["build"]),
                        data["asset"], data["signature"], int(data["length"]))
    except (ValueError, KeyError, TypeError) as error:
        raise ReleaseError(f"{name} is not a valid handoff: {error!r}")
    wanted = (os_name, version, build)
    if (found.os, found.version, found.build) != wanted:
        raise ReleaseError(f"{name} describes {(found.os, found.version, found.build)}, not {wanted}")
    if found.asset not in sizes:
        raise ReleaseError(f"{name} names {found.asset}, which the release does not hold")
    if sizes[found.asset] != found.length:
        raise ReleaseError(
            f"{found.asset} is {sizes[found.asset]} bytes on the release but was signed at {found.length}")
    return found


def require_ready(tag, repo_dir):
    if git("status", "--porcelain", cwd=repo_dir):
        raise ReleaseError("the working tree is not clean")
    git("fetch", "-q", "origin", "main", f"refs/tags/{tag}:refs/tags/{tag}", cwd=repo_dir)
    merged = subprocess.run(["git", "merge-base", "--is-ancestor", f"{tag}^{{commit}}", "origin/main"],
                            cwd=repo_dir).returncode == 0
    if not merged:
        raise ReleaseError(f"tag {tag} is not contained in origin/main")
    version, build = pubspec_version(git("show", f"{tag}:pubspec.yaml", cwd=repo_dir))
    if f"v{version}" != tag:
        raise ReleaseError(f"tag {tag} holds pubspec version {version}")
    return version, build


def read_handoffs(gh, tag, version, build):
    info = gh.view(tag)
    sizes = {a["name"]: a["size"] for a in info["assets"]}
    for name in HANDOFFS.values():
        if name not in sizes:
            raise ReleaseError(f"release {tag} has no {name} - is every build done?")
    work = tempfile.mkdtemp(prefix="erelas-handoff-")
    try:
        found = []
        for os_name, name in HANDOFFS.items():
            with open(gh.download(tag, name, work), encoding="utf-8-sig") as handoff:
                found.append(parse_handoff(handoff.read(), os_name, version, build, sizes, name))
        return info["isDraft"], found
    finally:
        shutil.rmtree(work, ignore_errors=True)


def add_items(feed, handoffs, tag, now):
    pub_date = now.strftime("%a, %d %b %Y %H:%M:%S +0000")
    for item in handoffs:
        common = dict(version=item.version, build=item.build, pub_date=pub_date,
                      url=f"https://github.com/{REPO_SLUG}/releases/download/{tag}/{item.asset}",
                      length=item.length)
        if item.os == appcast.WINDOWS:
            appcast.add_windows_item(feed, dsa_signature=item.signature, **common)
        else:
            appcast.add_item(feed, ed_signature=item.signature, **common)


def push_feed(cwd):
    """Pushes HEAD to main, rebasing over whatever landed there meanwhile (the
    data writer commits there too). A conflict is aborted, never forced."""
    reason = ""
    for _ in range(MAX_PUSH_ATTEMPTS):
        pushed = subprocess.run(["git", "push", "-q", "origin", "HEAD:main"], cwd=cwd,
                                capture_output=True, text=True)
        if pushed.returncode == 0:
            return
        reason = pushed.stderr.strip()
        git("fetch", "-q", "origin", "main", cwd=cwd)
        rebased = subprocess.run(["git", "rebase", "origin/main"], cwd=cwd, capture_output=True, text=True)
        if rebased.returncode != 0:
            subprocess.run(["git", "rebase", "--abort"], cwd=cwd)
            raise ReleaseError("the feed edit conflicts with origin/main - reconcile it by hand")
    raise ReleaseError(f"could not push the feed after {MAX_PUSH_ATTEMPTS} attempts: {reason}")


@contextmanager
def main_checkout(repo_dir):
    """A throwaway checkout of origin/main, so the caller's tree stays put."""
    path = tempfile.mkdtemp(prefix="erelas-feed-")
    try:
        git("worktree", "add", "-q", "--detach", path, "origin/main", cwd=repo_dir)
        yield path
    finally:
        subprocess.run(["git", "worktree", "remove", "--force", path], cwd=repo_dir, capture_output=True)
        shutil.rmtree(path, ignore_errors=True)
        subprocess.run(["git", "worktree", "prune"], cwd=repo_dir, capture_output=True)


def publish(tag, gh, repo_dir=".", now=None):
    version, build = require_ready(tag, repo_dir)
    is_draft, handoffs = read_handoffs(gh, tag, version, build)
    if is_draft:
        gh.promote(tag)
    with main_checkout(repo_dir) as checkout:
        try:
            add_items(os.path.join(checkout, FEED), handoffs, tag, now or datetime.now(timezone.utc))
        except appcast.AppcastError as error:
            raise ReleaseError(str(error))
        git("add", FEED, cwd=checkout)
        git("commit", "-q", "-m", f"Publish {tag} to the update feed", cwd=checkout)
        push_feed(checkout)


def main(argv):
    if len(argv) != 2:
        print(__doc__.splitlines()[0], file=sys.stderr)
        return 2
    try:
        tag = tag_from_ref(argv[1])
        publish(tag, Gh())
    except ReleaseError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print(f"==> {FEED} now lists {tag} for both platforms; Pages serves it in a minute or so")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
