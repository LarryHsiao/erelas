#!/usr/bin/env bash
#
# Erelas — publish a released version to the Sparkle update feed
# (docs/appcast.xml, served by GitHub Pages). Run it AFTER the release is
# public: the feed points at the release's real download URL, and it signs the
# very file users download, not the local build.
#
# Usage:
#   scripts/publish_feed_macos.sh [vX.Y.Z]   # default: v<version in pubspec>
#
# Refuses unless the tree is clean, on main, level with origin/main, the tag
# exists on origin and is contained in main, and the release is not a draft.
# Never resets or force-pushes; a lost push race is rebased, a conflicting feed
# edit is aborted and reported.
#
# Platforms: macOS only (it uses Sparkle's signing tool from the Pods build).
# Environment: DART (default "fvm dart") runs Sparkle's signing tool.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=publish_macos.sh
source "$HERE/publish_macos.sh"

FEED="docs/appcast.xml"
REPO_SLUG="LarryHsiao/erelas"
MAX_PUSH_ATTEMPTS=5
DART="${DART:-fvm dart}"

# Both read pubspec text on stdin: "version: 1.1.0+7".
version_from() {
  grep -E '^version:' | head -1 \
    | sed -E 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/'
}

build_number_from() {
  grep -E '^version:' | head -1 \
    | sed -E 's/^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\+([0-9]+).*/\1/'
}

require_tag_in_main() { # tag
  git fetch -q origin main "refs/tags/$1:refs/tags/$1" \
    || fail "could not fetch main and tag $1 from origin (is the tag there, and the same locally?)"
  git merge-base --is-ancestor "$1^{commit}" origin/main \
    || fail "tag $1 is not contained in origin/main"
}

require_public_release() { # tag
  local draft
  draft=$(gh release view "$1" --json isDraft --jq .isDraft) \
    || fail "no GitHub release $1"
  [ "$draft" = "false" ] || fail "release $1 is still a draft - promote it first"
}

# Pushes the feed commit, rebasing over whatever landed on main meanwhile (the
# data writer commits there too). A conflict is aborted, never forced.
push_feed() {
  local attempt
  for attempt in $(seq 1 "$MAX_PUSH_ATTEMPTS"); do
    git push origin HEAD:main && return 0
    echo "==> push lost a race (attempt $attempt/$MAX_PUSH_ATTEMPTS), rebasing"
    git fetch -q origin main
    if ! git rebase origin/main; then
      git rebase --abort
      fail "feed edit conflicts with origin/main - reconcile $FEED by hand (drop the local feed commit with: git reset --keep origin/main)"
    fi
  done
  fail "could not push the feed after $MAX_PUSH_ATTEMPTS attempts"
}

# Both read sign_update's output on stdin and fail if it carries no value.
signature_from() {
  local text value
  text=$(cat)
  value=$(echo "$text" | sed -nE 's/.*sparkle:edSignature="([^"]+)".*/\1/p')
  [ -n "$value" ] || fail "no signature in sign_update output: $text"
  echo "$value"
}

length_from() {
  local text value
  text=$(cat)
  value=$(echo "$text" | sed -nE 's/.*length="([0-9]+)".*/\1/p')
  [ -n "$value" ] || fail "no length in sign_update output: $text"
  echo "$value"
}

# Reads sign_update's output on stdin and prints "<signature> <length>", or
# nothing and a failure. The two values are assigned on their own so a missing
# one stops the run instead of printing a half-empty line.
sign_fields() {
  local text signature length
  text=$(cat)
  signature=$(printf '%s' "$text" | signature_from) || exit 1
  length=$(printf '%s' "$text" | length_from) || exit 1
  echo "$signature $length"
}

# Downloads the public asset and signs it: prints "<signature> <length>".
sign_public_dmg() { # tag workdir
  gh release download "$1" -p "$APP_NAME.dmg" -D "$2" --clobber
  $DART run auto_updater:sign_update "$2/$APP_NAME.dmg" | sign_fields
}

add_feed_item() { # tag version build signature length
  python3 -I "$HERE/update_appcast.py" --appcast "$FEED" \
    --version "$2" --build "$3" \
    --pub-date "$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')" \
    --url "https://github.com/$REPO_SLUG/releases/download/$1/$APP_NAME.dmg" \
    --length "$5" --ed-signature "$4"
}

main() {
  cd "$(git rev-parse --show-toplevel)"
  local tag="${1:-v$(read_version)}" version build workdir signature length
  require_clean_tree
  require_branch "$RELEASE_BRANCH"
  require_pushed "$RELEASE_BRANCH"
  require_tag_in_main "$tag"
  require_public_release "$tag"
  version=$(git show "$tag:pubspec.yaml" | version_from)
  build=$(git show "$tag:pubspec.yaml" | build_number_from)
  [ "v$version" = "$tag" ] || fail "tag $tag holds pubspec version $version"
  workdir=$(mktemp -d)
  trap 'rm -rf "$workdir"' EXIT
  read -r signature length < <(sign_public_dmg "$tag" "$workdir")
  [ -n "$signature" ] && [ -n "$length" ] || fail "release $tag was not signed"
  add_feed_item "$tag" "$version" "$build" "$signature" "$length"
  git add "$FEED"
  git commit -m "Publish $tag to the update feed"
  push_feed
  echo "==> $FEED now lists $tag (build $build); Pages serves it in a minute or so"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
