#!/bin/bash
# Builds build/Harbor.app with SwiftPM.
# Usage: scripts/build.sh [--release] [--install]
#   --release  sign with your Developer ID for distribution, and notarize if NOTARY_PROFILE is set
#   --install  copy the app to ~/Applications and launch it
#
# Release builds read these environment variables:
#   VERSION         the version, e.g. 1.2.0 (default: the tag on HEAD, without its leading "v")
#   BUILD_NUMBER    the build number (default: the number of commits on HEAD)
#   SIGN_IDENTITY   the signing identity (default: the first "Developer ID Application" in the keychain)
#   NOTARY_PROFILE  a notarytool keychain profile; without it the app is signed but not notarized
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/build/Harbor.app"

RELEASE=false
INSTALL=false
for arg in "$@"; do
    case "$arg" in
        --release) RELEASE=true ;;
        --install) INSTALL=true ;;
        *) echo "Unknown option: $arg" >&2; exit 64 ;;
    esac
done

fail() { echo "error: $*" >&2; exit 1; }

# Check the release settings before compiling, so a missing one fails fast.
if $RELEASE; then
    VERSION="${VERSION:-$(git describe --tags --exact-match 2>/dev/null || true)}"
    VERSION="${VERSION#v}"
    BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || true)}"
    SIGN_IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ { print $2; exit }')}"
    [[ -n "$VERSION" ]] || fail "no version: tag HEAD (e.g. git tag v1.0.0) or set VERSION"
    [[ -n "$BUILD_NUMBER" ]] || fail "no build number: commit first or set BUILD_NUMBER"
    [[ -n "$SIGN_IDENTITY" ]] || fail "no Developer ID Application certificate in the keychain; set SIGN_IDENTITY"
fi

# Use Xcode's toolchain if the active developer directory is still the Command Line Tools
# (`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` makes this unnecessary).
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p)" == *CommandLineTools* && -d /Applications/Xcode.app ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

echo "• Compile"
swift build -c release
BIN="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
echo "• Bundle"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN/Harbor" "$APP/Contents/MacOS/Harbor"
cp "$BIN/HarborStub" "$APP/Contents/Helpers/HarborStub"
cp Resources/Info.plist "$APP/Contents/Info.plist"
"$BIN/HarborStub" --render-icon "$APP/Contents/Resources/AppIcon.icns" sailboat.fill 3A9BF5 tile

if $RELEASE; then
    echo "• Sign $VERSION ($BUILD_NUMBER) as $SIGN_IDENTITY"
    # Info.plist is sealed by the signature, so the version has to be set first.
    /usr/libexec/PlistBuddy \
        -c "Set :CFBundleShortVersionString $VERSION" \
        -c "Set :CFBundleVersion $BUILD_NUMBER" \
        "$APP/Contents/Info.plist"
    # Inside out: the app's signature records the helper's, so the helper is signed first.
    # Notarization requires the hardened runtime (--options runtime) and a secure timestamp.
    codesign --force --options runtime --timestamp --identifier com.griffhurt.harbor.stub \
        --sign "$SIGN_IDENTITY" "$APP/Contents/Helpers/HarborStub"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
    codesign --verify --strict --deep "$APP"

    ZIP="$ROOT/build/Harbor-$VERSION.zip"
    if [[ -n "${NOTARY_PROFILE:-}" ]]; then
        echo "• Notarize"
        ditto -c -k --keepParent "$APP" "$ZIP"
        xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
        # Fails if Apple rejected the app (see `xcrun notarytool log <id>`), since there's no ticket.
        xcrun stapler staple "$APP"
    else
        echo "  Not notarizing (NOTARY_PROFILE isn't set), so other Macs will still block the app."
    fi
    # Zip again so the download includes the stapled ticket.
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Packaged $ZIP"
else
    codesign --force --sign - "$APP/Contents/Helpers/HarborStub"
    codesign --force --sign - "$APP"
fi
echo "Built $APP"

if $INSTALL; then
    DEST="$HOME/Applications/Harbor.app"
    pkill -x Harbor 2>/dev/null || true
    while pgrep -x Harbor >/dev/null; do sleep 0.2; done
    mkdir -p "$HOME/Applications"
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    open "$DEST"
    echo "Installed and launched $DEST"
fi
