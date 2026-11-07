#!/usr/bin/env bash
#
# Tests for the preflight checks in publish_macos.sh. Each case builds a
# throwaway origin and clone, so nothing touches the real repository.
#
# Usage: bash scripts/test_publish_macos.sh
# Platforms: macOS and Linux (needs bash and git).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=publish_macos.sh
source "$HERE/publish_macos.sh"
set +e # the sourced script turns -e on; each case reads its own status

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

# Runs a check in a subshell inside $REPO and prints its exit status.
status_of() {
  (cd "$REPO" && "$@" >/dev/null 2>&1)
  echo $?
}

new_repo() { # builds $REPO: a clone of a fresh origin, on main, pushed
  rm -rf "$SANDBOX/origin.git" "$SANDBOX/clone"
  git init -q --bare -b main "$SANDBOX/origin.git"
  git clone -q "$SANDBOX/origin.git" "$SANDBOX/clone" 2>/dev/null
  REPO="$SANDBOX/clone"
  (
    cd "$REPO"
    git config user.email test@example.com
    git config user.name Test
    git config commit.gpgsign false
    git config tag.gpgsign false
    git checkout -q -b main
    printf 'name: erelas\nversion: 1.2.3+45\n' > pubspec.yaml
    git add pubspec.yaml
    git commit -q -m init
    git push -q -u origin main
  )
}

new_repo
expected="1.2.3"
actual="$(cd "$REPO" && read_version)"
expect_equal "version drops the build number" "$expected" "$actual"

expected=0
actual="$(status_of require_clean_tree)"
expect_equal "a clean tree passes" "$expected" "$actual"

echo dirt >> "$REPO/pubspec.yaml"
expected=1
actual="$(status_of require_clean_tree)"
expect_equal "a dirty tree is refused" "$expected" "$actual"

new_repo
expected=0
actual="$(status_of require_branch main)"
expect_equal "being on main passes" "$expected" "$actual"

(cd "$REPO" && git checkout -q -b feature)
expected=1
actual="$(status_of require_branch main)"
expect_equal "another branch is refused" "$expected" "$actual"

new_repo
expected=0
actual="$(status_of require_pushed main)"
expect_equal "a pushed head passes" "$expected" "$actual"

(cd "$REPO" && git commit -q --allow-empty -m local)
expected=1
actual="$(status_of require_pushed main)"
expect_equal "an unpushed commit is refused" "$expected" "$actual"

expected=1
actual="$(IDENTITY= status_of require_identity)"
expect_equal "an unset IDENTITY is refused" "$expected" "$actual"

expected=0
actual="$(IDENTITY=ABC123 status_of require_identity)"
expect_equal "a set IDENTITY passes" "$expected" "$actual"

new_repo
expected=1
actual="$(status_of require_release_tag v1.2.3)"
expect_equal "a tag that is not on origin is refused" "$expected" "$actual"

(cd "$REPO" && git tag v1.2.3 && git push -q origin v1.2.3)
expected=0
actual="$(status_of require_release_tag v1.2.3)"
expect_equal "a tag at HEAD that main contains passes" "$expected" "$actual"

(cd "$REPO" && git commit -q --allow-empty -m next && git push -q origin main)
expected=1
actual="$(status_of require_release_tag v1.2.3)"
expect_equal "a tag on an older commit is refused" "$expected" "$actual"

new_repo
(cd "$REPO" && git switch -q -c side && git commit -q --allow-empty -m side \
  && git tag v9.9.9 && git push -q origin v9.9.9)
expected=1
actual="$(status_of require_release_tag v9.9.9)"
expect_equal "a tag that main does not contain is refused" "$expected" "$actual"

new_repo
(cd "$REPO" && git remote set-url origin "$SANDBOX/does-not-exist.git")
expected=1
actual="$(status_of require_release_tag v1.2.3)"
expect_equal "an unreachable origin is refused, not passed" "$expected" "$actual"

new_repo
(cd "$REPO" && printf 'name: erelas\nversion: 1.0\n' > pubspec.yaml)
expected=1
actual="$(status_of read_version)"
expect_equal "a version that is not x.y.z is refused" "$expected" "$actual"

new_repo
expected="45"
actual="$(cd "$REPO" && read_build)"
expect_equal "the build number is read" "$expected" "$actual"

expected="ABC=="
actual="$(printf 'sparkle:edSignature="ABC==" length="9"' | signature_from)"
expect_equal "the signature is taken from sign_update output" "$expected" "$actual"

expected=1
actual="$( (echo nothing | signature_from) >/dev/null 2>&1; echo $? )"
expect_equal "output without a signature is refused" "$expected" "$actual"

expected='{"os":"macos","version":"1.2.3","build":45,"asset":"erelas.dmg","signature":"SIG==","length":1000}'
actual="$(handoff_json 1.2.3 45 erelas.dmg SIG== 1000)"
expect_equal "the handoff carries what publish_release.py reads" "$expected" "$actual"

# ensure_draft, with gh stubbed by a function (it shadows the real binary).
GH_LOG="$SANDBOX/gh.log"
gh() {
  case "$1 $2" in
    "release view")
      case "$GH_STATE" in
        draft) echo true ;;
        public) echo false ;;
        race) [ -f "$SANDBOX/created" ] && echo true || return 1 ;;
        *) return 1 ;;
      esac ;;
    "release list") echo "$GH_COUNT" ;;
    "release create")
      echo create >> "$GH_LOG"
      if [ "$GH_STATE" = race ]; then touch "$SANDBOX/created"; return 1; fi ;;
  esac
}

run_ensure_draft() { # state -> prints "<status>:<create calls>"
  rm -f "$GH_LOG" "$SANDBOX/created"
  GH_STATE="$1"
  (ensure_draft v1.2.3 >/dev/null 2>&1)
  local status=$?
  echo "$status:$([ -f "$GH_LOG" ] && grep -c create "$GH_LOG" || echo 0)"
}

expected="0:0"
actual="$(run_ensure_draft draft)"
expect_equal "an existing draft is reused, not recreated" "$expected" "$actual"

expected="0:1"
actual="$(run_ensure_draft missing)"
expect_equal "a missing release is created as a draft" "$expected" "$actual"

expected="1:0"
actual="$(run_ensure_draft public)"
expect_equal "a public release is refused" "$expected" "$actual"

expected="0:1"
actual="$(run_ensure_draft race)"
expect_equal "a create lost to the other platform's build is accepted" "$expected" "$actual"

run_single_release() { # count -> prints the status
  GH_COUNT="$1"
  (assert_single_release v1.2.3 >/dev/null 2>&1)
  echo $?
}

expected=0
actual="$(run_single_release 1)"
expect_equal "exactly one release for the tag passes" "$expected" "$actual"

expected=1
actual="$(run_single_release 2)"
expect_equal "two releases for one tag are refused" "$expected" "$actual"

expected=1
actual="$(run_single_release 0)"
expect_equal "no release for the tag is refused" "$expected" "$actual"

exit "$FAILED"
