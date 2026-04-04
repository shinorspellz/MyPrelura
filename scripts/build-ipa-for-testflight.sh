#!/bin/bash

# Build and upload to TestFlight for Myprelura (staff app)
# Usage: ./scripts/build-ipa-for-testflight.sh [--upload]
#
# Credentials (same pattern as Prelura Swift):
#   1) scripts/testflight-credentials.json (gitignored)
#   2) Keychain: AC_PASSWORD for account "Myprelura" or "Prelura-swift" (shared team)

set -e

PROJECT_NAME="Myprelura"
SCHEME="Myprelura"
ARCHIVE_PATH="./build/${PROJECT_NAME}.xcarchive"
EXPORT_PATH="./build/export"
IPA_PATH="./build/ipa/${PROJECT_NAME}.ipa"
EXPORT_OPTIONS="./ExportOptions.plist"

UPLOAD=false
if [[ "$1" == "--upload" ]]; then
    UPLOAD=true
fi

echo "📦 Building IPA for TestFlight..."
echo "Bundle ID: com.myprelura.preloved"
echo "Team ID: 94QA2FVSW2"
echo ""

echo "🧹 Cleaning previous builds..."
rm -rf "./build/${PROJECT_NAME}.xcarchive"
rm -rf "${EXPORT_PATH}"
mkdir -p ./build/ipa

echo ""
echo "Step 1: Creating archive..."
xcodebuild archive \
    -project "${PROJECT_NAME}.xcodeproj" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -archivePath "${ARCHIVE_PATH}" \
    -destination 'generic/platform=iOS' \
    -allowProvisioningUpdates \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM=94QA2FVSW2 \
    PRODUCT_BUNDLE_IDENTIFIER=com.myprelura.preloved

if [ $? -ne 0 ]; then
    echo "❌ Archive failed."
    exit 1
fi

echo "✅ Archive created successfully!"

echo ""
echo "Step 2: Exporting IPA..."
xcodebuild -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_PATH}" \
    -exportOptionsPlist "${EXPORT_OPTIONS}" \
    -allowProvisioningUpdates

if [ $? -ne 0 ]; then
    echo "❌ Export failed."
    exit 1
fi

if [ -f "${EXPORT_PATH}/${PROJECT_NAME}.ipa" ]; then
    cp "${EXPORT_PATH}/${PROJECT_NAME}.ipa" "${IPA_PATH}"
    echo "✅ IPA exported successfully: ${IPA_PATH}"
else
    echo "❌ IPA file not found at ${EXPORT_PATH}/${PROJECT_NAME}.ipa"
    exit 1
fi

ENT_TMP="$(mktemp -d)"
unzip -q "${IPA_PATH}" -d "$ENT_TMP"
APP_IN_IPA="$(find "$ENT_TMP/Payload" -maxdepth 1 -name "*.app" | head -1)"
if [[ ! -d "$APP_IN_IPA" ]]; then
    echo "❌ Could not locate .app inside IPA for entitlement check."
    rm -rf "$ENT_TMP"
    exit 1
fi
if ! codesign -d --entitlements - "$APP_IN_IPA" 2>/dev/null | grep -q "aps-environment"; then
    rm -rf "$ENT_TMP"
    echo ""
    echo "❌ Exported IPA is missing the push entitlement (aps-environment)."
    echo "   Fix signing / capabilities for com.myprelura.preloved, then re-archive."
    exit 1
fi
rm -rf "$ENT_TMP"
echo "✅ Entitlements check: aps-environment present (push enabled in signed binary)."

if [ "$UPLOAD" = true ]; then
    echo ""
    echo "Step 3: Uploading to TestFlight..."

    CREDS_FILE="$(cd "$(dirname "$0")/.." && pwd)/scripts/testflight-credentials.json"
    CREDENTIALS=""
    if [ -f "$CREDS_FILE" ]; then
        CREDENTIALS=$(cat "$CREDS_FILE")
        echo "Using credentials from scripts/testflight-credentials.json"
    fi
    if [ -z "$CREDENTIALS" ]; then
        CREDENTIALS=$(security find-generic-password -s "AC_PASSWORD" -a "Myprelura" -w 2>/dev/null) || true
    fi
    if [ -z "$CREDENTIALS" ]; then
        CREDENTIALS=$(security find-generic-password -s "AC_PASSWORD" -a "Prelura-swift" -w 2>/dev/null) || true
        if [ -n "$CREDENTIALS" ]; then
            echo "Using keychain AC_PASSWORD for account Prelura-swift (same as Prelura Swift)"
        fi
    fi

    if [ -z "$CREDENTIALS" ]; then
        echo "❌ No credentials found (keychain or scripts/testflight-credentials.json)."
        echo "   Prelura Swift: run ./scripts/setup-testflight-keychain.sh in PreluraSwift (stores Prelura-swift), OR"
        echo "   Here: ./scripts/setup-testflight-keychain.sh OR scripts/testflight-credentials.json (see .example)"
        exit 1
    fi

    if command -v python3 &>/dev/null; then
        CREDENTIALS=$(printf '%s' "$CREDENTIALS" | python3 -c "
import sys, binascii, json
raw = sys.stdin.read().strip()
if not raw:
    sys.exit(0)
try:
    json.loads(raw)
    print(raw, end='')
    sys.exit(0)
except json.JSONDecodeError:
    pass
if len(raw) >= 4 and len(raw) % 2 == 0 and all(c in '0123456789abcdefABCDEF' for c in raw):
    try:
        dec = binascii.unhexlify(raw).decode('utf-8')
        json.loads(dec)
        print(dec, end='')
        sys.exit(0)
    except (binascii.Error, UnicodeDecodeError, json.JSONDecodeError):
        pass
print(raw, end='')
")
    fi

    if command -v python3 &>/dev/null; then
        METHOD=$(printf '%s' "$CREDENTIALS" | python3 -c "import sys, json; print(json.load(sys.stdin).get('method', ''))" 2>/dev/null)
    else
        METHOD=$(printf '%s' "$CREDENTIALS" | tr -d '\n' | grep -oE '\"method\"[[:space:]]*:[[:space:]]*\"[^\"]*\"' | head -1 | sed 's/.*: *\"\([^\"]*\)\".*/\1/')
    fi

    if [ -z "$METHOD" ]; then
        echo "❌ Credentials are not valid JSON with a \"method\" field."
        exit 1
    fi

    if [ "$METHOD" = "password" ]; then
        if command -v python3 &>/dev/null; then
            APPLE_ID=$(echo "$CREDENTIALS" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('apple_id', ''))" 2>/dev/null)
            APP_SPECIFIC_PASSWORD=$(echo "$CREDENTIALS" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('app_specific_password', ''))" 2>/dev/null)
        fi
        if [ -z "$APPLE_ID" ] || [ -z "$APP_SPECIFIC_PASSWORD" ]; then
            APPLE_ID=$(echo "$CREDENTIALS" | tr -d '\n' | grep -oE '"apple_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')
            APP_SPECIFIC_PASSWORD=$(echo "$CREDENTIALS" | tr -d '\n' | grep -oE '"app_specific_password"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')
        fi

        echo "Uploading with Apple ID authentication..."
        xcrun altool --upload-app \
            --type ios \
            --file "${IPA_PATH}" \
            --username "$APPLE_ID" \
            --password "$APP_SPECIFIC_PASSWORD" \
            2>&1 | tee /tmp/testflight_upload_myprelura.log

    elif [ "$METHOD" = "api_key" ]; then
        if command -v python3 &>/dev/null; then
            API_KEY_ID=$(printf '%s' "$CREDENTIALS" | python3 -c "import sys, json; print(json.load(sys.stdin).get('api_key_id', ''))" 2>/dev/null)
            ISSUER_ID=$(printf '%s' "$CREDENTIALS" | python3 -c "import sys, json; print(json.load(sys.stdin).get('issuer_id', ''))" 2>/dev/null)
        else
            API_KEY_ID=$(printf '%s' "$CREDENTIALS" | tr -d '\n' | grep -oE '\"api_key_id\"[[:space:]]*:[[:space:]]*\"[^\"]*\"' | head -1 | sed 's/.*: *\"\([^\"]*\)\".*/\1/')
            ISSUER_ID=$(printf '%s' "$CREDENTIALS" | tr -d '\n' | grep -oE '\"issuer_id\"[[:space:]]*:[[:space:]]*\"[^\"]*\"' | head -1 | sed 's/.*: *\"\([^\"]*\)\".*/\1/')
        fi

        echo "Uploading with API Key authentication..."
        xcrun altool --upload-app \
            --type ios \
            --file "${IPA_PATH}" \
            --apiKey "$API_KEY_ID" \
            --apiIssuer "$ISSUER_ID" \
            2>&1 | tee /tmp/testflight_upload_myprelura.log
    else
        echo "❌ Unknown authentication method: $METHOD"
        exit 1
    fi

    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        echo ""
        echo "✅ Upload successful!"
        echo "Check App Store Connect for processing status."
        echo "Upload log: /tmp/testflight_upload_myprelura.log"
    else
        echo ""
        echo "❌ Upload failed. Check log: /tmp/testflight_upload_myprelura.log"
        grep -i "error" /tmp/testflight_upload_myprelura.log | tail -10 || true
        exit 1
    fi
else
    echo ""
    echo "ℹ️  IPA ready at: ${IPA_PATH}"
    echo "To upload, run: $0 --upload"
fi
