#!/bin/bash
# Notarizes a signed Twain.app or .dmg with Apple and staples the ticket to it, so
# Gatekeeper accepts it even offline.
#
#   NOTARY_KEY_PATH=AuthKey_XXXX.p8 NOTARY_KEY_ID=XXXX NOTARY_ISSUER_ID=<uuid> ./notarize.sh <path>
#
# Credentials are an App Store Connect API key (Users and Access → Integrations → Keys).
# An .app is submitted as a zip (notarytool doesn't take bundles) and the ticket is
# stapled to the bundle itself.
set -euo pipefail

TARGET="${1:?Usage: $0 <path to .app or .dmg>}"
: "${NOTARY_KEY_PATH:?}" "${NOTARY_KEY_ID:?}" "${NOTARY_ISSUER_ID:?}"

SUBMISSION="$TARGET"
if [[ "$TARGET" == *.app ]]; then
    SUBMISSION="$(mktemp -d)/$(basename "$TARGET" .app).zip"
    ditto -c -k --norsrc --noextattr --noqtn --keepParent "$TARGET" "$SUBMISSION"
fi

echo "Submitting $(basename "$SUBMISSION") for notarization..."
RESULT=$(xcrun notarytool submit "$SUBMISSION" \
    --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" \
    --wait --output-format json)
STATUS=$(echo "$RESULT" | plutil -extract status raw -)
ID=$(echo "$RESULT" | plutil -extract id raw -)

# `submit --wait` exits 0 for a rejected submission too; the status is the real verdict.
if [ "$STATUS" != "Accepted" ]; then
    echo "Notarization $STATUS (submission $ID). Log:" >&2
    xcrun notarytool log "$ID" \
        --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" >&2 || true
    exit 1
fi

xcrun stapler staple "$TARGET"
echo "Notarized and stapled: $TARGET"
