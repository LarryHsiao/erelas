#!/usr/bin/env bash
#
# Tests for the git and parsing parts of publish_feed_macos.sh, in throwaway
# repos. Usage: bash scripts/test_publish_feed_macos.sh
# Platforms: macOS and Linux (needs bash and git).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=publish_feed_macos.sh
source "$HERE/publish_feed_macos.sh"
set +e # the sourced scripts turn -e on; each case reads its own status

FAILED=0
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

expect_equal() { # name expected actual
  if [ "$2" = "$3" ]; then
    echo "ok   - $1"
  else
    echo "FAIL - $1: expected '$2', got '$3'"
    FAILED=1
  fi
}

new_repo() { # builds $SANDBOX/clone (and $SANDBOX/other) on a fresh origin
  rm -rf "$SANDBOX/origin.git" "$SANDBOX/clone" "$SANDBOX/other"
  git init -q --bare -b main "$SANDBOX/origin.git"
  git clone -q "$SANDBOX/origin.git" "$SANDBOX/clone" 2>/dev/null
  (
    cd "$SANDBOX/clone"
    git config user.email test@example.com
    git config user.name Test
    git checkout -q -b main
    mkdir -p docs
    echo "base" > docs/appcast.xml
    echo "keep" > docs/today.json
    git add docs
    git commit -q -m init
    git push -q -u origin main
  )
  git clone -q "$SANDBOX/origin.git" "$SANDBOX/other" 2>/dev/null
  (cd "$SANDBOX/other" && git config user.email t@e.com && git config user.name T)
}

PUBSPEC=$'name: erelas\nversion: 1.1.0+7\n'
expected=7
actual="$(printf '%s' "$PUBSPEC" | build_number_from)"
expect_equal "the build number is the part after the plus" "$expected" "$actual"

expected=1.1.0
actual="$(printf '%s' "$PUBSPEC" | version_from)"
expect_equal "the version drops the build" "$expected" "$actual"

SIGNED='sparkle:edSignature="AbC+/=="  length="21454275"'
expected="AbC+/=="
actual="$(printf '%s' "$SIGNED" | signature_from)"
expect_equal "the signature is read from sign_update's output" "$expected" "$actual"

expected=21454275
actual="$(printf '%s' "$SIGNED" | length_from)"
expect_equal "the length is read from sign_update's output" "$expected" "$actual"

expected=1
actual="$(printf '%s' 'something unexpected' | signature_from >/dev/null 2>&1; echo $?)"
expect_equal "output without a signature is refused" "$expected" "$actual"

expected="AbC+/== 21454275"
actual="$(printf '%s' "$SIGNED" | sign_fields)"
expect_equal "both fields come out together" "$expected" "$actual"

expected="1:"
out="$(printf '%s' 'no sig here' | sign_fields 2>/dev/null)"; status=$?
actual="$status:$out"
expect_equal "output without a signature yields no fields at all" "$expected" "$actual"

expected=1
(printf '%s' 'sparkle:edSignature="X"' | sign_fields >/dev/null 2>&1); actual=$?
expect_equal "a signature without a length is refused" "$expected" "$actual"

new_repo
(cd "$SANDBOX/clone" && echo feed >> docs/appcast.xml && git commit -qam feed)
(cd "$SANDBOX/clone" && push_feed >/dev/null 2>&1)
expected="$(cd "$SANDBOX/clone" && git rev-parse HEAD)"
actual="$(git --git-dir="$SANDBOX/origin.git" rev-parse main)"
expect_equal "a plain push lands on origin" "$expected" "$actual"

new_repo
(cd "$SANDBOX/other" && echo data > docs/today.json && git commit -qam data && git push -q origin main)
(cd "$SANDBOX/clone" && echo feed >> docs/appcast.xml && git commit -qam feed)
(cd "$SANDBOX/clone" && push_feed >/dev/null 2>&1)
expected="feed"
actual="$(git --git-dir="$SANDBOX/origin.git" log -1 --format=%s main)"
expect_equal "a lost race is rebased and pushed" "$expected" "$actual"
expected="data"
actual="$(git --git-dir="$SANDBOX/origin.git" show main:docs/today.json | tr -d '\n')"
expect_equal "the other side's commit survives the race" "$expected" "$actual"

new_repo
(cd "$SANDBOX/other" && echo theirs >> docs/appcast.xml && git commit -qam theirs && git push -q origin main)
(cd "$SANDBOX/clone" && echo ours >> docs/appcast.xml && git commit -qam ours)
(cd "$SANDBOX/clone" && push_feed >/dev/null 2>&1)
expected=1
(cd "$SANDBOX/clone" && push_feed >/dev/null 2>&1); actual=$?
expect_equal "a conflicting feed edit fails the push" "$expected" "$actual"
expected=""
actual="$(cd "$SANDBOX/clone" && git status --porcelain)"
expect_equal "a failed rebase is aborted, leaving the tree clean" "$expected" "$actual"

# The temporary directory outlives main() and is removed when the script ends,
# without the exit trap tripping over a variable that went out of scope.
child='source "$1"; run() { make_workdir; echo "$WORKDIR"; }; run'
errors="$SANDBOX/trap-errors"
dir="$(bash -c "$child" _ "$HERE/publish_feed_macos.sh" 2>"$errors")"
expected="gone,silent"
actual="$([ -d "$dir" ] && echo present || echo gone),$([ -s "$errors" ] && echo noisy || echo silent)"
expect_equal "the workdir is removed at exit and the trap is silent" "$expected" "$actual"

exit "$FAILED"
