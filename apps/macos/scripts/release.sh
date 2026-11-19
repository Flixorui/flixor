#!/bin/zsh
# Flixor for macOS: build, sign with Developer ID, notarize, staple and package.
#
#   apps/macos/scripts/release.sh public   [options]   # for everyone: no Live TV
#   apps/macos/scripts/release.sh personal [options]   # for the owner: with Live TV
#   apps/macos/scripts/release.sh friends  [options]   # friends and family: public + bundled keys
#
# Options
#   --version X.Y.Z  Marketing version (default: MARKETING_VERSION in the project).
#   --build N        Build number (default: number of commits on HEAD).
#   --no-notarize    Sign only. Fine for a quick check on this Mac; other Macs warn.
#   --upload         public only: put the DMG on a draft GitHub release macos-vX.Y.Z.
#   --install        personal only: replace /Applications/FlixorMac.app (quits Flixor).
#
# Output: apps/macos/dist/<edition>/  (gitignored)
#   Flixor-<version>.dmg (public), Flixor-<version>-personal.dmg or
#   Flixor-<version>-friends.dmg, the stapled .app, a zip of it, SHA-256 sums and the
#   notary log.
#
# Editions
#   The personal edition compiles in FLIXOR_LIVE_TV through Config/Personal.xcconfig
#   (gitignored, owner's Mac only). The public edition overrides it away, whether or
#   not that file exists, and the script refuses to package a public build that still
#   contains Live TV code or the personal Info.plist's App Transport Security exception.
#   The friends edition is the public one plus the defaults in Config/Friends.xcconfig
#   (gitignored): a MyBluray key, a FlixPatrol API and Stremio add-ons. It is never
#   uploaded, because anyone with the app can read those values out of it.
#
# One-time setup (see the steps printed by --help)
#   1. A "Developer ID Application" certificate in the login keychain.
#   2. Notarization credentials stored for notarytool under the profile name
#      "flixor-notary" (or set FLIXOR_NOTARY_PROFILE):
#        xcrun notarytool store-credentials flixor-notary \
#          --key ~/Downloads/AuthKey_XXXXXXXXXX.p8 --key-id XXXXXXXXXX --issuer <issuer-uuid>
#   3. For --upload: the GitHub CLI logged in (gh auth status).
#
# Environment
#   FLIXOR_SIGN_ID          Signing identity (default: the Developer ID Application one).
#   FLIXOR_NOTARY_PROFILE   notarytool keychain profile (default: flixor-notary).

set -euo pipefail
setopt null_glob

SCRIPT=${0:A}
# In a zsh function $0 is the function's name, hence SCRIPT.
usage() { sed -n '2,39p' "$SCRIPT" | sed 's/^# \{0,1\}//'; }

MACOS_DIR=${SCRIPT:h:h}
REPO_DIR=${MACOS_DIR:h:h}
PROJECT=$MACOS_DIR/FlixorMac.xcodeproj
CONFIG_DIR=$MACOS_DIR/FlixorMac/Config
ENTITLEMENTS=$MACOS_DIR/FlixorMac/FlixorMac.entitlements
NOTARY_PROFILE=${FLIXOR_NOTARY_PROFILE:-flixor-notary}

EDITION=""
VERSION=""
BUILD=""
NOTARIZE=1
UPLOAD=0
INSTALL=0

while (( $# )); do
  case $1 in
    public|personal|friends) EDITION=$1 ;;
    --version) VERSION=$2; shift ;;
    --build) BUILD=$2; shift ;;
    --no-notarize) NOTARIZE=0 ;;
    --upload) UPLOAD=1 ;;
    --install) INSTALL=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

step() { print -P "\n%B==> $1%b"; }
fail() { print -P "%F{red}error:%f $1" >&2; exit 1; }
warn() { print -P "%F{yellow}warning:%f $1" >&2; }

[[ -n $EDITION ]] || { usage >&2; exit 2; }
[[ $EDITION != public && $UPLOAD == 1 ]] && fail "--upload is for the public edition only. The $EDITION edition carries keys and never goes on GitHub."
[[ $EDITION != personal && $INSTALL == 1 ]] && fail "--install is for the personal edition only."
[[ $UPLOAD == 1 && $NOTARIZE == 0 ]] && fail "--upload needs a notarized build (drop --no-notarize)."

# ---------------------------------------------------------------- checks
step "Checking the setup"

command -v xcodebuild >/dev/null || fail "Xcode command line tools not found."

if [[ -z ${FLIXOR_SIGN_ID:-} ]]; then
  # First match only, without "| head" (which can break the pipe under pipefail).
  ids=(${(f)"$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p')"})
  FLIXOR_SIGN_ID=${ids[1]:-}
fi
[[ -n $FLIXOR_SIGN_ID ]] || fail "No \"Developer ID Application\" certificate in the keychain. See setup step 1."
[[ $(security find-identity -v -p codesigning) == *"\"$FLIXOR_SIGN_ID\""* ]] || fail "Signing identity not found: $FLIXOR_SIGN_ID"
TEAM_ID=$(print -r -- $FLIXOR_SIGN_ID | sed -n 's/.*(\([A-Z0-9]*\))$/\1/p')
echo "Signing as: $FLIXOR_SIGN_ID"

if (( NOTARIZE )); then
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
    || fail "No notarytool credentials under the profile \"$NOTARY_PROFILE\". See setup step 2."
  echo "Notarizing with profile: $NOTARY_PROFILE"
fi

if (( UPLOAD )); then
  command -v gh >/dev/null || fail "GitHub CLI (gh) not installed."
  gh auth status >/dev/null 2>&1 || fail "GitHub CLI not logged in (gh auth login)."
fi

if [[ $EDITION == personal ]]; then
  [[ -f $CONFIG_DIR/Personal.xcconfig ]] || fail "Config/Personal.xcconfig is missing: copy Personal.example.xcconfig to build the personal edition."
fi
if [[ $EDITION == friends ]]; then
  [[ -f $CONFIG_DIR/Friends.xcconfig ]] || fail "Config/Friends.xcconfig is missing: copy Friends.example.xcconfig and fill it in."
fi
[[ -f $CONFIG_DIR/Secrets.xcconfig ]] || warn "Config/Secrets.xcconfig is missing: the build will have no TMDB/Trakt keys."

if [[ -n $(git -C "$REPO_DIR" status --porcelain -- apps/macos shared) ]]; then
  warn "apps/macos or shared has uncommitted changes; they go into this build."
fi

if [[ -z $VERSION ]]; then
  versions=(${(f)"$(sed -n 's/.*MARKETING_VERSION = \([0-9.]*\);/\1/p' "$PROJECT/project.pbxproj")"})
  VERSION=${versions[1]:-}
fi
VERSION_RE='^[0-9]+(\.[0-9]+){1,2}$'
[[ $VERSION =~ $VERSION_RE ]] || fail "Bad version: '$VERSION'"
[[ -n $BUILD ]] || BUILD=$(git -C "$REPO_DIR" rev-list --count HEAD)
COMMIT=$(git -C "$REPO_DIR" rev-parse --short HEAD)
echo "Edition: $EDITION   Version: $VERSION ($BUILD)   Commit: $COMMIT"

SUFFIX=""; [[ $EDITION != public ]] && SUFFIX="-$EDITION"
NAME="Flixor-$VERSION$SUFFIX"
DIST=$MACOS_DIR/dist/$EDITION
WORK=$(mktemp -d "${TMPDIR:-/tmp}/flixor-release.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$DIST"
LOG=$DIST/$NAME-build.log

# ---------------------------------------------------------------- build
step "Building the $EDITION edition (Release, Apple Silicon)"

# Settings passed with -xcconfig override the project and Flixor.xcconfig.
OVERRIDES=$WORK/edition.xcconfig
if [[ $EDITION != personal ]]; then
  cat > "$OVERRIDES" <<'EOF'
// Public and friends editions: no Live TV, the plain Info.plist (no App Transport Security exception).
SWIFT_ACTIVE_COMPILATION_CONDITIONS =
FLIXOR_INFOPLIST_FILE = FlixorMac/Info.plist
EOF
  if [[ $EDITION == friends ]]; then
    print "#include \"$CONFIG_DIR/Friends.xcconfig\"" >> "$OVERRIDES"
  fi
else
  print "// Personal edition: Config/Personal.xcconfig (included by Flixor.xcconfig) applies." > "$OVERRIDES"
fi

xcodebuild build \
  -project "$PROJECT" -scheme FlixorMac -configuration Release \
  -derivedDataPath "$WORK/DerivedData" \
  -destination 'platform=macOS,arch=arm64' \
  -xcconfig "$OVERRIDES" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO \
  > "$LOG" 2>&1 || { grep -E "error:" "$LOG" | sort -u | head -20 >&2; fail "Build failed. Full log: $LOG"; }
echo "Build log: $LOG"

BUILT=$WORK/DerivedData/Build/Products/Release/FlixorMac.app
[[ -d $BUILT ]] || fail "Built app not found."

# ---------------------------------------------------------------- edition gate
step "Checking the edition"
BIN=$BUILT/Contents/MacOS/FlixorMac
# grep -c reads all of strings' output: grep -q would stop early and, under pipefail,
# turn a match into a failure.
LIVETV_COUNT=$(strings -a "$BIN" | grep -c "LiveTV" || true)
HAS_LIVETV=0; (( LIVETV_COUNT > 0 )) && HAS_LIVETV=1
HAS_ATS=0; /usr/libexec/PlistBuddy -c "Print :NSAppTransportSecurity:NSAllowsArbitraryLoads" "$BUILT/Contents/Info.plist" >/dev/null 2>&1 && HAS_ATS=1
PLIST=$BUILT/Contents/Info.plist
bundled() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null || true; }
BUNDLED_KEYS=(FlixorBundledMyBlurayKey FlixorBundledFlixPatrolURL FlixorBundledFlixPatrolKey FlixorBundledStremioAddons)
if [[ $EDITION != personal ]]; then
  (( HAS_LIVETV == 0 )) || fail "The $EDITION build contains Live TV code. Not packaging it."
  (( HAS_ATS == 0 )) || fail "The $EDITION build has the personal App Transport Security exception. Not packaging it."
  echo "No Live TV code, no ATS exception."
fi
if [[ $EDITION == friends ]]; then
  # Values are checked, never printed.
  for k in $BUNDLED_KEYS; do
    v=$(bundled $k)
    [[ -n $v && $v != *'$('* ]] || fail "$k is empty in the friends build: check Config/Friends.xcconfig."
  done
  [[ $(bundled FlixorBundledFlixPatrolURL) == https://* ]] || fail "The FlixPatrol URL lost its https:// (write it as https:/\$()/host in the xcconfig)."
  ADDONS=(${=$(bundled FlixorBundledStremioAddons)})
  for a in $ADDONS; do
    [[ $a == https://*manifest.json ]] || fail "A Stremio add-on URL is malformed (write https:/\$()/host in the xcconfig)."
  done
  echo "Bundled: MyBluray key, FlixPatrol API, ${#ADDONS} Stremio add-ons."
elif [[ $EDITION == public ]]; then
  for k in $BUNDLED_KEYS; do
    [[ -z $(bundled $k) ]] || fail "The public build carries $k. Not packaging it."
  done
fi
if [[ $EDITION == personal ]]; then
  (( HAS_LIVETV == 1 )) || fail "The personal build has no Live TV code: is FLIXOR_LIVE_TV set in Personal.xcconfig?"
  echo "Live TV included."
fi
PLIST_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$BUILT/Contents/Info.plist")
[[ $PLIST_VERSION == $VERSION ]] || fail "Info.plist version is $PLIST_VERSION, expected $VERSION."

# ---------------------------------------------------------------- sign
step "Signing with Developer ID (hardened runtime, secure timestamp)"
APP=$DIST/Flixor.app
rm -rf "$APP" "$DIST/$NAME".{dmg,zip} "$DIST/$NAME"-notary*.json
ditto "$BUILT" "$APP"

sign() { codesign --force --timestamp --options runtime -s "$FLIXOR_SIGN_ID" "$@" 2>&1 | grep -v "replacing existing signature" || true; }

# Inside out: nested code first, the app last (with its entitlements).
for f in "$APP"/Contents/Frameworks/*.framework "$APP"/Contents/Frameworks/*.dylib \
         "$APP"/Contents/PlugIns/* "$APP"/Contents/Library/LoginItems/*; do
  sign "$f"
done
sign --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -2
[[ $(codesign -d -r- "$APP" 2>&1) == *"$TEAM_ID"* ]] || fail "The app's signature doesn't name team $TEAM_ID."

# ---------------------------------------------------------------- package
step "Making the DMG"
STAGE=$WORK/dmg
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Flixor.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Flixor $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DIST/$NAME.dmg" 2>&1 \
  | grep -v -e "is deprecated" -e "^created:" || true
[[ -f $DIST/$NAME.dmg ]] || fail "DMG not created."
codesign --force --timestamp -s "$FLIXOR_SIGN_ID" "$DIST/$NAME.dmg"
echo "$DIST/$NAME.dmg"

# ---------------------------------------------------------------- notarize
if (( NOTARIZE )); then
  step "Notarizing (usually a few minutes)"
  RESULT=$DIST/$NAME-notary.json
  xcrun notarytool submit "$DIST/$NAME.dmg" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$RESULT" || true
  STATUS=$(plutil -extract status raw -o - "$RESULT" 2>/dev/null || echo "unknown")
  SUBMISSION=$(plutil -extract id raw -o - "$RESULT" 2>/dev/null || echo "")
  if [[ -n $SUBMISSION ]]; then
    xcrun notarytool log "$SUBMISSION" --keychain-profile "$NOTARY_PROFILE" "$DIST/$NAME-notary-log.json" >/dev/null 2>&1 || true
  fi
  [[ $STATUS == Accepted ]] || fail "Notarization status: $STATUS. Details: $DIST/$NAME-notary-log.json"
  echo "Accepted ($SUBMISSION)"

  step "Stapling"
  # The DMG's submission covers the app inside it, so both get a ticket.
  xcrun stapler staple -q "$DIST/$NAME.dmg"
  xcrun stapler staple -q "$APP"
  spctl -a -t open --context context:primary-signature "$DIST/$NAME.dmg" && echo "DMG: accepted by Gatekeeper"
  spctl -a -t exec "$APP" && echo "App: accepted by Gatekeeper"
else
  warn "Not notarized: Gatekeeper on other Macs will block it."
fi

ditto -c -k --keepParent "$APP" "$DIST/$NAME.zip"
( cd "$DIST" && shasum -a 256 "$NAME.dmg" "$NAME.zip" > "$NAME.sha256" )

# ---------------------------------------------------------------- upload
if (( UPLOAD )); then
  step "Uploading to a draft GitHub release"
  TAG=macos-v$VERSION
  if gh release view "$TAG" --repo "$(git -C "$REPO_DIR" remote get-url origin)" >/dev/null 2>&1; then
    gh release upload "$TAG" "$DIST/$NAME.dmg" "$DIST/$NAME.sha256" --clobber
    echo "Updated the assets of release $TAG"
  else
    gh release create "$TAG" "$DIST/$NAME.dmg" "$DIST/$NAME.sha256" \
      --draft --target "$(git -C "$REPO_DIR" rev-parse HEAD)" \
      --title "Flixor for macOS $VERSION" \
      --notes "Flixor for macOS $VERSION (build $BUILD, $COMMIT). Apple Silicon, macOS 13 or later. Signed and notarized by Apple: open the DMG and drag Flixor to Applications."
    echo "Draft release $TAG created: review and publish it on GitHub."
  fi
fi

# ---------------------------------------------------------------- install
if (( INSTALL )); then
  step "Installing to /Applications"
  osascript -e 'tell application id "com.flixor.mac" to quit' >/dev/null 2>&1 || true
  for i in {1..20}; do pgrep -x FlixorMac >/dev/null || break; sleep 0.5; done
  pgrep -x FlixorMac >/dev/null && fail "Flixor is still running."
  if [[ -d /Applications/FlixorMac.app ]]; then
    BACKUP=${TMPDIR:-/tmp}/flixor-installed-backup-$(date +%Y%m%d-%H%M%S)
    ditto /Applications/FlixorMac.app "$BACKUP/FlixorMac.app"
    echo "Previous app backed up to $BACKUP"
  fi
  rm -rf /Applications/FlixorMac.app
  ditto "$APP" /Applications/FlixorMac.app
  touch /Applications/FlixorMac.app
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/FlixorMac.app
  echo "Installed."
fi

step "Done"
ls -1 "$DIST" | grep -E "^($NAME|Flixor\.app)"
