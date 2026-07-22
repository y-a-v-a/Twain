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

# The entry point swap: NSExtensionMain must be an imported symbol, or the
# appex would run the (empty) SPM main and exit instead of serving previews.
nm -u "$APPEX/Contents/MacOS/TwainQuickLook" | grep -q _NSExtensionMain || fail "binary does not import NSExtensionMain"

# Signature must validate and carry the sandbox entitlement — unsandboxed
# app extensions are not loaded.
codesign --verify --strict "$APPEX" || fail "appex signature invalid"
codesign -d --entitlements - "$APPEX" 2>&1 | grep -q com.apple.security.app-sandbox || fail "appex not sandboxed"

echo "verify-bundle: OK ($APPEX)"
