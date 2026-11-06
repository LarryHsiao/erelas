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
expected=0
actual="$(status_of require_tag_at_head v1.2.3)"
expect_equal "a tag that does not exist yet passes" "$expected" "$actual"

(cd "$REPO" && git tag v1.2.3 && git push -q origin v1.2.3)
expected=0
actual="$(status_of require_tag_at_head v1.2.3)"
expect_equal "a tag at HEAD passes" "$expected" "$actual"

(cd "$REPO" && git commit -q --allow-empty -m next && git push -q origin main)
expected=1
actual="$(status_of require_tag_at_head v1.2.3)"
expect_equal "a tag on an older commit is refused" "$expected" "$actual"

new_repo
(cd "$REPO" && git remote set-url origin "$SANDBOX/does-not-exist.git")
expected=1
actual="$(status_of require_tag_at_head v1.2.3)"
expect_equal "an unreachable origin is refused, not passed" "$expected" "$actual"

new_repo
(cd "$REPO" && printf 'name: erelas\nversion: 1.0\n' > pubspec.yaml)
expected=1
actual="$(status_of read_version)"
expect_equal "a version that is not x.y.z is refused" "$expected" "$actual"

exit "$FAILED"
