#!/bin/bash
# Shape check for the Quick Look appex inside an assembled Twain.app: the
# pieces that must be present for macOS to load the extension at all. Catches
# build.sh regressions in CI without needing pluginkit or a GUI session.
set -euo pipefail

APP="${1:-.build/debug/Twain.app}"
APPEX="$APP/Contents/PlugIns/TwainQuickLook.appex"

fail() { echo "verify-bundle: $1" >&2; exit 1; }

[ -d "$APPEX" ] || fail "missing appex at $APPEX"
[ -x "$APPEX/Contents/MacOS/TwainQuickLook" ] || fail "missing appex executable"

PLIST="$APPEX/Contents/Info.plist"
[ "$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "$PLIST")" = "com.apple.quicklook.preview" ] \
    || fail "wrong NSExtensionPointIdentifier"
/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionAttributes:QLSupportedContentTypes' "$PLIST" | grep -q net.daringfireball.markdown \
    || fail "markdown UTI not in QLSupportedContentTypes"

# Prism resources must be in the appex itself (it is its own main bundle).
[ -d "$APPEX/Contents/Resources/textual_Textual.bundle" ] || fail "Textual resource bundle missing from appex"

# Twain enables Textual's `.math` extension, and SwiftUIMath loads its fonts via
# `Bundle.module`, which traps when the bundle is missing — both copies must ship.
for dir in "$APP/Contents/Resources" "$APPEX/Contents/Resources"; do
    [ -d "$dir/swiftui-math_SwiftUIMath.bundle/mathFonts.bundle" ] \
        || fail "SwiftUIMath bundle (math fonts) missing from $dir"
done

# The entry point swap: NSExtensionMain must be an imported symbol, or the
# appex would run the (empty) SPM main and exit instead of serving previews.
# grep must drain the pipe (no -q): under pipefail, grep -q exiting early
# makes llvm-nm die on the broken pipe and fails the check spuriously.
nm -u "$APPEX/Contents/MacOS/TwainQuickLook" | grep _NSExtensionMain >/dev/null || fail "binary does not import NSExtensionMain"

# Signature must validate and carry the sandbox entitlement — unsandboxed
# app extensions are not loaded.
codesign --verify --strict "$APPEX" || fail "appex signature invalid"
codesign -d --entitlements - "$APPEX" 2>&1 | grep com.apple.security.app-sandbox >/dev/null || fail "appex not sandboxed"

echo "verify-bundle: OK ($APPEX)"
