"""Tests for publish_release.py. Run: python3 -I -m unittest discover -s scripts

Platforms: any with Python 3.9+ and git (standard library only). The GitHub
side is a fake; the git side is real, in throwaway repositories.
"""
import json
import os
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

import publish_release as release
import update_appcast as appcast

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
TAG = "v1.2.0"
PUBSPEC = "name: erelas\nversion: 1.2.0+5\n"
MAC_ASSET, WIN_ASSET = "erelas.dmg", "erelas-setup-1.2.0.exe"
MAC_HANDOFF, WIN_HANDOFF = "update-macos.json", "update-windows.json"


def git(*args, cwd):
    done = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    if done.returncode != 0:
        raise AssertionError(f"git {args} failed: {done.stderr}")
    return done.stdout.strip()


def handoff(os_name, asset, length, version="1.2.0", build=5, signature="SIG=="):
    return json.dumps({
        "os": os_name, "version": version, "build": build,
        "asset": asset, "signature": signature, "length": length,
    })


class FakeGh:
    """A release with the given assets: name -> (size, text of the file)."""

    def __init__(self, assets, draft=True):
        self.assets = assets
        self.draft = draft
        self.promoted = []

    def view(self, tag):
        return {"isDraft": self.draft,
                "assets": [{"name": n, "size": s} for n, (s, _) in self.assets.items()]}

    def download(self, tag, name, directory):
        path = os.path.join(directory, name)
        with open(path, "w") as out:
            out.write(self.assets[name][1])
        return path

    def promote(self, tag):
        self.promoted.append(tag)
        self.draft = False


def full_release(**changes):
    assets = {
        MAC_ASSET: (1000, ""), WIN_ASSET: (2000, ""),
        MAC_HANDOFF: (1, handoff("macos", MAC_ASSET, 1000)),
        WIN_HANDOFF: (1, handoff("windows", WIN_ASSET, 2000)),
    }
    assets.update(changes)
    return assets


class RepoCase(unittest.TestCase):
    """A bare origin and a clone holding main at v1.2.0, with an old feed."""

    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.origin = os.path.join(self.dir.name, "origin.git")
        self.work = os.path.join(self.dir.name, "work")
        git("init", "--bare", "-b", "main", self.origin, cwd=self.dir.name)
        git("init", "-b", "main", self.work, cwd=self.dir.name)
        for key, value in [("user.email", "t@example.com"), ("user.name", "T"),
                           ("commit.gpgsign", "false"), ("tag.gpgsign", "false")]:
            git("config", key, value, cwd=self.work)
        git("remote", "add", "origin", self.origin, cwd=self.work)
        self.write("pubspec.yaml", PUBSPEC)
        self.seed_feed()
        self.commit("release 1.2.0")
        git("tag", TAG, cwd=self.work)
        git("push", "-q", "origin", "main", TAG, cwd=self.work)

    def write(self, name, text):
        path = os.path.join(self.work, name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as out:
            out.write(text)

    def seed_feed(self):
        feed = os.path.join(self.work, "docs", "appcast.xml")
        os.makedirs(os.path.dirname(feed), exist_ok=True)
        appcast.add_item(feed, version="1.1.1", build=4, pub_date="Fri, 06 Nov 2026 12:00:00 +0000",
                         url="https://example.com/old.dmg", length=1, ed_signature="OLD==")

    def commit(self, message):
        git("add", "-A", cwd=self.work)
        git("commit", "-q", "-m", message, cwd=self.work)

    def origin_main(self):
        return git("rev-parse", "main", cwd=self.origin)

    def origin_commits(self):
        return int(git("rev-list", "--count", "main", cwd=self.origin))

    def origin_feed_items(self):
        text = git("show", "main:docs/appcast.xml", cwd=self.origin)
        return ET.fromstring(text).findall("./channel/item")

    def publish(self, gh):
        release.publish(TAG, gh, repo_dir=self.work)


class HandoffTest(unittest.TestCase):
    sizes = {MAC_ASSET: 1000}

    def parse(self, text, os_name="macos", version="1.2.0", build=5):
        return release.parse_handoff(text, os_name, version, build, self.sizes, MAC_HANDOFF)

    def test_a_matching_handoff_is_read(self):
        expected = release.Handoff("macos", "1.2.0", 5, MAC_ASSET, "SIG==", 1000)
        actual = self.parse(handoff("macos", MAC_ASSET, 1000))
        self.assertEqual(actual, expected)

    def test_a_handoff_for_the_other_platform_is_refused(self):
        with self.assertRaises(release.ReleaseError):
            self.parse(handoff("windows", MAC_ASSET, 1000))

    def test_a_handoff_for_another_version_is_refused(self):
        with self.assertRaises(release.ReleaseError):
            self.parse(handoff("macos", MAC_ASSET, 1000, version="1.1.9"))

    def test_a_handoff_for_another_build_is_refused(self):
        with self.assertRaises(release.ReleaseError):
            self.parse(handoff("macos", MAC_ASSET, 1000, build=4))

    def test_a_missing_asset_is_refused(self):
        with self.assertRaises(release.ReleaseError):
            self.parse(handoff("macos", "gone.dmg", 1000))

    def test_a_size_that_differs_from_the_asset_is_refused(self):
        with self.assertRaises(release.ReleaseError):
            self.parse(handoff("macos", MAC_ASSET, 999))

    def test_text_that_is_not_a_handoff_is_a_named_error(self):
        with self.assertRaises(release.ReleaseError):
            self.parse("not json")

    def test_a_handoff_missing_a_field_is_a_named_error(self):
        with self.assertRaises(release.ReleaseError):
            self.parse(json.dumps({"os": "macos"}))


class PublishTest(RepoCase):
    def test_both_items_land_in_one_commit_and_the_draft_is_promoted(self):
        gh = FakeGh(full_release())
        before = self.origin_commits()
        self.publish(gh)
        expected = {"promoted": [TAG], "commits": before + 1, "items": 3}
        actual = {"promoted": gh.promoted, "commits": self.origin_commits(),
                  "items": len(self.origin_feed_items())}
        self.assertEqual(actual, expected)

    def test_the_items_carry_each_platforms_signature_and_version(self):
        self.publish(FakeGh(full_release()))
        enclosures = {i.find("enclosure").get(f"{{{SPARKLE}}}os"): i.find("enclosure")
                      for i in self.origin_feed_items()
                      if f"/{TAG}/" in i.find("enclosure").get("url")}
        expected = {"win": ("1.2.0+5", "SIG=="), "mac": ("SIG==", "1000")}
        actual = {
            "win": (enclosures["windows"].get(f"{{{SPARKLE}}}version"),
                    enclosures["windows"].get(f"{{{SPARKLE}}}dsaSignature")),
            "mac": (enclosures["macos"].get(f"{{{SPARKLE}}}edSignature"),
                    enclosures["macos"].get("length")),
        }
        self.assertEqual(actual, expected)

    def test_the_callers_repo_keeps_no_stale_worktree(self):
        self.publish(FakeGh(full_release()))
        expected = 1
        actual = len(git("worktree", "list", cwd=self.work).splitlines())
        self.assertEqual(actual, expected)

    def test_the_urls_point_at_the_release_assets(self):
        self.publish(FakeGh(full_release()))
        urls = {i.find("enclosure").get("url") for i in self.origin_feed_items()}
        expected = {
            f"https://github.com/LarryHsiao/erelas/releases/download/{TAG}/{MAC_ASSET}",
            f"https://github.com/LarryHsiao/erelas/releases/download/{TAG}/{WIN_ASSET}",
            "https://example.com/old.dmg",
        }
        self.assertEqual(urls, expected)

    def assert_nothing_changed(self, gh, before):
        expected = {"promoted": [], "main": before}
        actual = {"promoted": gh.promoted, "main": self.origin_main()}
        self.assertEqual(actual, expected)

    def test_a_missing_handoff_changes_nothing(self):
        assets = full_release()
        del assets[WIN_HANDOFF]
        gh, before = FakeGh(assets), self.origin_main()
        with self.assertRaises(release.ReleaseError):
            self.publish(gh)
        self.assert_nothing_changed(gh, before)

    def test_a_size_mismatch_changes_nothing(self):
        gh, before = FakeGh(full_release(**{WIN_ASSET: (1, "")})), self.origin_main()
        with self.assertRaises(release.ReleaseError):
            self.publish(gh)
        self.assert_nothing_changed(gh, before)

    def test_a_tag_outside_main_is_refused(self):
        git("switch", "-q", "-c", "side", cwd=self.work)
        self.write("pubspec.yaml", "name: erelas\nversion: 1.3.0+6\n")
        self.commit("side")
        git("tag", "v1.3.0", cwd=self.work)
        git("push", "-q", "origin", "v1.3.0", cwd=self.work)
        gh, before = FakeGh(full_release()), self.origin_main()
        with self.assertRaises(release.ReleaseError):
            release.publish("v1.3.0", gh, repo_dir=self.work)
        self.assert_nothing_changed(gh, before)

    def test_a_tag_that_disagrees_with_the_pubspec_is_refused(self):
        git("tag", "v9.9.9", TAG, cwd=self.work)
        git("push", "-q", "origin", "v9.9.9", cwd=self.work)
        gh, before = FakeGh(full_release()), self.origin_main()
        with self.assertRaises(release.ReleaseError):
            release.publish("v9.9.9", gh, repo_dir=self.work)
        self.assert_nothing_changed(gh, before)

    def test_a_dirty_tree_is_refused(self):
        self.write("stray.txt", "x")
        gh, before = FakeGh(full_release()), self.origin_main()
        with self.assertRaises(release.ReleaseError):
            self.publish(gh)
        self.assert_nothing_changed(gh, before)

    def test_an_already_public_release_still_gets_its_feed_items(self):
        gh = FakeGh(full_release(), draft=False)
        self.publish(gh)
        expected = {"promoted": [], "items": 3}
        actual = {"promoted": gh.promoted, "items": len(self.origin_feed_items())}
        self.assertEqual(actual, expected)


class TagFromRefTest(unittest.TestCase):
    def test_a_full_ref_is_reduced_to_the_tag(self):
        expected = "v1.2.0"
        actual = release.tag_from_ref("refs/tags/v1.2.0")
        self.assertEqual(actual, expected)

    def test_a_bare_tag_is_left_alone(self):
        expected = "v1.2.0"
        actual = release.tag_from_ref("v1.2.0")
        self.assertEqual(actual, expected)


class PushFeedTest(RepoCase):
    def clone_and_advance(self, file_name, text):
        other = os.path.join(self.dir.name, "other")
        git("clone", "-q", self.origin, other, cwd=self.dir.name)
        for key, value in [("user.email", "o@example.com"), ("user.name", "O"),
                           ("commit.gpgsign", "false")]:
            git("config", key, value, cwd=other)
        with open(os.path.join(other, file_name), "w") as out:
            out.write(text)
        git("add", "-A", cwd=other)
        git("commit", "-q", "-m", "other side", cwd=other)
        git("push", "-q", "origin", "main", cwd=other)

    def test_a_lost_race_is_rebased_and_pushed(self):
        self.clone_and_advance("docs/today.json", "{}")
        self.write("docs/note.txt", "feed")
        self.commit("feed")
        release.push_feed(self.work)
        files = git("ls-tree", "-r", "--name-only", "main", cwd=self.origin).split()
        expected = True
        actual = "docs/today.json" in files and "docs/note.txt" in files
        self.assertEqual(actual, expected)

    def test_a_refused_push_names_the_reason(self):
        hook = os.path.join(self.origin, "hooks", "pre-receive")
        with open(hook, "w", newline="\n") as out:
            out.write("#!/bin/sh\necho 'denied by test' >&2\nexit 1\n")
        os.chmod(hook, 0o755)
        self.write("docs/note.txt", "feed")
        self.commit("feed")
        with self.assertRaises(release.ReleaseError) as caught:
            release.push_feed(self.work)
        expected = True
        actual = "denied by test" in str(caught.exception)
        self.assertEqual(actual, expected)

    def test_a_conflicting_edit_is_aborted_and_named(self):
        self.clone_and_advance("docs/appcast.xml", "<other/>")
        self.write("docs/appcast.xml", "<mine/>")
        self.commit("feed")
        with self.assertRaises(release.ReleaseError):
            release.push_feed(self.work)
        expected = ""
        actual = git("status", "--porcelain", cwd=self.work)
        self.assertEqual(actual, expected)


if __name__ == "__main__":
    unittest.main()
