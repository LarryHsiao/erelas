#!/usr/bin/env bash
#
# Erelas — build, sign and notarize the macOS DMG, optionally publish it to
# GitHub Releases. Shaped after Orthanc's publish script, without its
# `git reset --hard` feed step.
#
# Usage:
#   IDENTITY=<hash> scripts/publish_macos.sh             # build, sign, notarize
#   IDENTITY=<hash> scripts/publish_macos.sh --publish   # also upload to the
#                                                        # DRAFT GitHub release
#
# --publish signs the DMG for Sparkle and uploads it, with update-macos.json,
# to the draft release v<VERSION>. It never makes a release public and never
# touches the update feed: scripts/publish_release.py does both, once the
# Windows build has uploaded as well. TeamCity runs this on a tag build, so the
# tag is the release decision.
#
# Refuses to run unless the tree is clean and `flutter analyze` and `flutter
# test` pass; without --publish it also wants main, fully pushed, and with
# --publish it wants HEAD to carry the tag v<VERSION>, contained in origin/main.
#
# Platforms: macOS only (codesign, notarytool, hdiutil). Windows is not
# supported here.
#
# Environment:
#   IDENTITY  required for an interactive run: the SHA-1 of the "Developer ID Application" signing
#             identity. This Mac holds two certificates under one name, so a
#             name is ambiguous; list them with
#             `security find-identity -v -p codesigning`.
#   NOTARY_PROFILE  notarytool keychain profile (default: erelas-notary). Set
#             it up once, so the password is typed at a prompt and never sits
#             in a process list:
#               xcrun notarytool store-credentials erelas-notary \
#                 --apple-id <Apple ID> --team-id 2SX9WGZ5F8
#   FLUTTER   the Flutter command (default: "fvm flutter")
#   DART      the Dart command that runs Sparkle's signing tool (default:
#             "fvm dart")
#
# Headless signing (TeamCity): when DEVELOPER_ID_CERT_BASE64 is set, IDENTITY and
# the notary profile are not used. Set instead DEVELOPER_ID_CERT_BASE64 and
# DEVELOPER_ID_CERT_PASSWORD (the Developer ID Application .p12),
# NOTARY_API_KEY_BASE64 and NOTARY_API_KEY_ID (an App Store Connect API key, with
# NOTARY_API_ISSUER_ID for a team key) and KEYCHAIN_PASSWORD (any value, for the
# throwaway keychain that holds the certificate for this run). Orthanc's CI
# script works the same way.
set -euo pipefail

APP_NAME="erelas"
RELEASE_BRANCH="main"
FLUTTER="${FLUTTER:-fvm flutter}"
DART="${DART:-fvm dart}"
KEYCHAIN_ARGS=()
NOTARY_PROFILE="${NOTARY_PROFILE:-erelas-notary}"
OUTPUT_DIR="build/publish"
ENTITLEMENTS="macos/Runner/Release.entitlements"

# Stops the run, or the subshell a check is called in, with a named reason.
fail() {
  echo "error: $*" >&2
  exit 1
}

# The marketing version from pubspec.yaml: "1.0.0+1" -> "1.0.0".
read_version() {
  local version
  version=$(grep -E '^version:' pubspec.yaml | head -1 \
    | sed -E 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/') || true
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || fail "pubspec.yaml version is not x.y.z[+build]"
  echo "$version"
}

# The build number from pubspec.yaml: "1.0.0+7" -> "7". Sparkle compares it.
read_build() {
  local build
  build=$(grep -E '^version:' pubspec.yaml | head -1 \
    | sed -E 's/^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\+([0-9]+).*/\1/') || true
  [[ "$build" =~ ^[0-9]+$ ]] || fail "pubspec.yaml version has no +build number"
  echo "$build"
}

require_clean_tree() {
  [ -z "$(git status --porcelain)" ] \
    || fail "working tree is dirty - commit or stash first"
}

require_branch() { # branch
  local current
  current=$(git rev-parse --abbrev-ref HEAD)
  [ "$current" = "$1" ] || fail "on '$current', releases are cut from '$1'"
}

# HEAD must equal origin's branch, so the tag and the build are one commit.
require_pushed() { # branch
  git fetch -q origin "$1"
  [ "$(git rev-parse HEAD)" = "$(git rev-parse "origin/$1")" ] \
    || fail "HEAD is not origin/$1 - push (or pull) first"
}

# The release is decided by a tag: it must be on origin at the commit being
# built, and main must contain it, so what ships is what was merged. The remote
# is asked directly, so an unreachable origin fails the check instead of
# passing it.
require_release_tag() { # tag
  local refs sha
  refs=$(git ls-remote origin "refs/tags/$1" "refs/tags/$1^{}") \
    || fail "could not ask origin about tag $1"
  [ -n "$refs" ] || fail "tag $1 is not on origin - push the tag to release"
  sha=$(printf '%s\n' "$refs" | awk '
    $2 ~ /\^\{\}$/ { peeled = $1 }
    $2 !~ /\^\{\}$/ { plain = $1 }
    END { print (peeled != "" ? peeled : plain) }')
  [ "$sha" = "$(git rev-parse HEAD)" ] || fail "tag $1 is not at HEAD"
  git fetch -q origin main || fail "could not fetch origin/main"
  git merge-base --is-ancestor HEAD origin/main \
    || fail "tag $1 is not contained in origin/main"
}

# Publishing needs an authenticated gh; find out before a long build.
require_gh() {
  gh auth status >/dev/null 2>&1 || fail "gh is missing or not logged in"
}

require_green_checks() {
  echo "==> flutter analyze"
  $FLUTTER analyze || fail "analyze failed"
  echo "==> flutter test"
  $FLUTTER test || fail "tests failed"
}

require_identity() {
  [ -n "${IDENTITY:-}" ] || fail \
    "IDENTITY is not set - list identities with: security find-identity -v -p codesigning"
}

# Asks Apple to check the stored credentials now, before a long build.
require_notary_profile() {
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
    || fail "notarytool profile '$NOTARY_PROFILE' is missing or rejected - see the header"
}

# Headless signing: a certificate and a notary API key arrive as environment
# variables, and a throwaway keychain holds the certificate for this run.
CI_VARS=(DEVELOPER_ID_CERT_BASE64 DEVELOPER_ID_CERT_PASSWORD NOTARY_API_KEY_BASE64
  NOTARY_API_KEY_ID KEYCHAIN_PASSWORD)
NOTARY_ISSUER_UUID='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
CI_WORK=""

is_ci_signing() { [ -n "${DEVELOPER_ID_CERT_BASE64:-}" ]; }

require_ci_env() {
  local name
  for name in "${CI_VARS[@]}"; do
    [ -n "${!name:-}" ] || fail "$name is not set (headless signing needs: ${CI_VARS[*]})"
  done
}

require_signing_credentials() {
  if is_ci_signing; then
    require_ci_env
  else
    require_identity
    require_notary_profile
  fi
}

# One notarytool argument per line. An issuer is a UUID only for a team API key;
# an individual key takes none, and notarytool rejects anything else, so it is
# passed only when it looks like one.
notary_auth_args() { # key-file
  if ! is_ci_signing; then
    printf '%s\n' --keychain-profile "$NOTARY_PROFILE"
    return 0
  fi
  printf '%s\n' --key "$1" --key-id "$NOTARY_API_KEY_ID"
  if [[ "${NOTARY_API_ISSUER_ID:-}" =~ $NOTARY_ISSUER_UUID ]]; then
    printf '%s\n' --issuer "$NOTARY_API_ISSUER_ID"
  fi
}

cleanup_ci_signing() {
  if [ -n "${KEYCHAIN_PATH:-}" ]; then
    security delete-keychain "$KEYCHAIN_PATH" 2>/dev/null || true
  fi
  if [ -n "$CI_WORK" ]; then
    rm -rf "$CI_WORK"
  fi
}

import_ci_certificate() {
  KEYCHAIN_PATH="$CI_WORK/build.keychain-db"
  printf '%s' "$DEVELOPER_ID_CERT_BASE64" | base64 --decode > "$CI_WORK/cert.p12"
  security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
  security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
  security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
  security import "$CI_WORK/cert.p12" -k "$KEYCHAIN_PATH" \
    -P "$DEVELOPER_ID_CERT_PASSWORD" -T /usr/bin/codesign
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
    -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null
}

# codesign finds the identity only through the user's keychain search list.
add_ci_keychain_to_search_list() {
  local existing
  existing=$(security list-keychains -d user | tr -d '"' | xargs)
  # shellcheck disable=SC2086
  security list-keychains -d user -s "$KEYCHAIN_PATH" $existing
}

find_ci_identity() {
  IDENTITY=$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" \
    | grep "Developer ID Application" | head -1 | awk '{print $2}') || true
  [ -n "$IDENTITY" ] || fail "no Developer ID Application identity in the build keychain"
}

setup_ci_signing() {
  CI_WORK=$(mktemp -d)
  trap cleanup_ci_signing EXIT
  printf '%s' "$NOTARY_API_KEY_BASE64" | base64 --decode > "$CI_WORK/notary.p8"
  NOTARY_KEY_PATH="$CI_WORK/notary.p8"
  import_ci_certificate
  add_ci_keychain_to_search_list
  find_ci_identity
  KEYCHAIN_ARGS=(--keychain "$KEYCHAIN_PATH")
  echo "==> Headless signing with a temporary keychain"
}

setup_signing() {
  if is_ci_signing; then
    setup_ci_signing
  fi
}

preflight() {
  require_signing_credentials
  require_clean_tree
  if [ "$PUBLISH" -eq 1 ]; then
    require_gh
    require_release_tag "v$VERSION"
  else
    require_branch "$RELEASE_BRANCH"
    require_pushed "$RELEASE_BRANCH"
  fi
  require_green_checks
}

build_release() {
  echo "==> Building macOS release"
  $FLUTTER pub get
  $FLUTTER build macos --release
  APP_PATH="build/macos/Build/Products/Release/$APP_NAME.app"
  [ -d "$APP_PATH" ] || fail "built app not found at $APP_PATH"
}

# Signs every nested bundle and loose executable once, deepest first, then
# the app itself. `--deep` is avoided: it re-signs nested code with the app's
# own entitlements and breaks their signatures.
sign_app() {
  [ -f "$ENTITLEMENTS" ] || fail "entitlements not found at $ENTITLEMENTS"
  local frameworks="$APP_PATH/Contents/Frameworks"
  echo "==> Code-signing nested code and $APP_PATH"
  if [ -d "$frameworks" ]; then
    find "$frameworks" -depth \( -type f -perm -u+x -o -name "*.dylib" \
      -o -name "*.framework" -o -name "*.xpc" -o -name "*.app" \) -print0 \
      | xargs -0 -I{} codesign --force --options runtime --timestamp \
        ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} --sign "$IDENTITY" "{}"
  fi
  codesign --force --options runtime --timestamp ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} \
    --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP_PATH"
  codesign --verify --strict --verbose=2 "$APP_PATH"
}

# A DMG holding the app and an Applications link, itself signed.
build_dmg() {
  mkdir -p "$OUTPUT_DIR"
  DMG_PATH="$OUTPUT_DIR/$APP_NAME.dmg"
  local stage="$OUTPUT_DIR/dmg-stage"
  rm -rf "$stage" "$DMG_PATH"
  mkdir -p "$stage"
  cp -R "$APP_PATH" "$stage/"
  ln -sfn /Applications "$stage/Applications"
  echo "==> Building $DMG_PATH"
  hdiutil create -volname "$APP_NAME" -srcfolder "$stage" -ov \
    -format UDZO "$DMG_PATH"
  rm -rf "$stage"
  codesign --force --timestamp ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} --sign "$IDENTITY" "$DMG_PATH"
  codesign --verify --strict --verbose=2 "$DMG_PATH"
}

# Notarization takes minutes. `--wait` can exit 0 on an Invalid result, so the
# printed status decides, not the exit code.
notarize_dmg() {
  local log line args
  args=()
  while IFS= read -r line; do
    args+=("$line")
  done < <(notary_auth_args "${NOTARY_KEY_PATH:-}")
  log=$(mktemp)
  echo "==> Submitting to Apple notary service (this can take several minutes)"
  xcrun notarytool submit "$DMG_PATH" "${args[@]}" --wait 2>&1 | tee "$log"
  grep -q "status: Accepted" "$log" || fail "notarization was not accepted"
  rm -f "$log"
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
}

# Reads sign_update's output on stdin and prints the Sparkle signature, or fails.
signature_from() {
  local text value
  text=$(cat)
  value=$(echo "$text" | sed -nE 's/.*sparkle:edSignature="([^"]+)".*/\1/p')
  [ -n "$value" ] || fail "no signature in sign_update output: $text"
  echo "$value"
}

# What scripts/publish_release.py reads to write this platform's feed item.
handoff_json() { # version build asset signature length
  printf '{"os":"macos","version":"%s","build":%s,"asset":"%s","signature":"%s","length":%s}\n' \
    "$1" "$2" "$3" "$4" "$5"
}

# Signs the built DMG with Sparkle's key (in this Mac's keychain) and writes
# update-macos.json beside it.
write_handoff() {
  local signature size
  signature=$($DART run auto_updater:sign_update "$DMG_PATH" | signature_from)
  size=$(wc -c < "$DMG_PATH" | tr -d ' ')
  HANDOFF_PATH="$OUTPUT_DIR/update-macos.json"
  handoff_json "$VERSION" "$(read_build)" "$(basename "$DMG_PATH")" "$signature" "$size" \
    > "$HANDOFF_PATH"
}

release_is_draft() { # tag
  [ "$(gh release view "$1" --json isDraft --jq .isDraft 2>/dev/null)" = "true" ]
}

# The tag exists already (it triggered this build). The release is created as a
# draft unless the Windows build got there first; a failed create is fine when
# the draft is there afterwards. A public release is never touched.
ensure_draft() { # tag
  local state
  if state=$(gh release view "$1" --json isDraft --jq .isDraft 2>/dev/null); then
    [ "$state" = "true" ] || fail "release $1 is already public - bump the version"
    return 0
  fi
  echo "==> Creating draft release $1"
  gh release create "$1" --draft --verify-tag --title "$1" --generate-notes \
    || release_is_draft "$1" || fail "could not create the draft release $1"
}

# Two builds creating the draft in the same instant can each make one, splitting
# the assets; stop loudly rather than leave that for the feed job to find.
assert_single_release() { # tag
  local count
  count=$(gh release list --limit 100 --json tagName \
    --jq "[.[] | select(.tagName == \"$1\")] | length")
  [ "$count" = "1" ] || fail "expected exactly one release for $1, found $count - merge them by hand"
}

# Uploads the DMG and its update handoff to the draft release for this version.
# Promoting the draft and writing the feed is publish_release.py's job, once
# both platforms have uploaded.
publish_release() {
  local tag="v$VERSION"
  ensure_draft "$tag"
  write_handoff
  gh release upload "$tag" "$DMG_PATH" "$HANDOFF_PATH" --clobber
  assert_single_release "$tag"
  gh release view "$tag" --json isDraft,url,assets \
    --jq '"==> \(.url)  draft=\(.isDraft)  assets=\([.assets[].name] | join(","))"'
}

parse_args() {
  PUBLISH=0
  for arg in "$@"; do
    case "$arg" in
      --publish) PUBLISH=1 ;;
      *) fail "unknown argument '$arg'" ;;
    esac
  done
}

main() {
  cd "$(git rev-parse --show-toplevel)"
  parse_args "$@"
  VERSION=$(read_version)
  echo "==> Version: $VERSION"
  preflight
  setup_signing
  build_release
  sign_app
  build_dmg
  notarize_dmg
  echo "==> Signed, notarized and stapled DMG: $DMG_PATH"
  if [ "$PUBLISH" -eq 1 ]; then
    publish_release
  else
    echo "==> Skipping publish (pass --publish to upload a draft release)"
  fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
