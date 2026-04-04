#!/bin/bash

# Keychain item for Myprelura TestFlight uploads (AC_PASSWORD / account "Myprelura").
# If you already use Prelura Swift’s keychain (account "Prelura-swift"), you do not need this;
# build-ipa-for-testflight.sh falls back to that account.
#
#   ./scripts/setup-testflight-keychain.sh password "your@appleid.com" "xxxx-xxxx-xxxx-xxxx"

set -e

echo "🔐 Setting up TestFlight keychain for Myprelura (account: Myprelura)..."
echo ""

KEYCHAIN_ACCOUNT="Myprelura"

if security find-generic-password -s "AC_PASSWORD" -a "$KEYCHAIN_ACCOUNT" &>/dev/null; then
    echo "⚠️  AC_PASSWORD for $KEYCHAIN_ACCOUNT already exists."
    read -p "Update it? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
    security delete-generic-password -s "AC_PASSWORD" -a "$KEYCHAIN_ACCOUNT" 2>/dev/null || true
fi

if [ -n "$APPLE_ID" ] && [ -n "$APP_SPECIFIC_PASSWORD" ]; then
    METHOD_CHOICE=1
elif [ -n "$API_KEY_ID" ] && [ -n "$ISSUER_ID" ] && [ -n "$API_KEY_FILE" ]; then
    METHOD_CHOICE=2
elif [ "$1" = "api" ] && [ -n "$2" ] && [ -n "$3" ] && [ -n "$4" ]; then
    METHOD_CHOICE=2
    API_KEY_ID="$2"
    ISSUER_ID="$3"
    KEY_FILE_PATH="$4"
elif [ "$1" = "password" ] && [ -n "$2" ] && [ -n "$3" ]; then
    METHOD_CHOICE=1
    APPLE_ID="$2"
    APP_SPECIFIC_PASSWORD="$3"
else
    echo "1. Apple ID + App-specific password"
    echo "2. API Key (.p8)"
    read -p "Choice (1 or 2): " -n 1 -r
    echo
    METHOD_CHOICE="$REPLY"
fi

if [[ $METHOD_CHOICE =~ ^[1]$ ]]; then
    if [ -z "$APPLE_ID" ]; then read -p "Apple ID: " APPLE_ID; fi
    if [ -z "$APP_SPECIFIC_PASSWORD" ]; then read -sp "App-specific password: " APP_SPECIFIC_PASSWORD; echo; fi
    CREDENTIALS=$(cat <<EOF
{
  "method": "password",
  "apple_id": "$APPLE_ID",
  "app_specific_password": "$APP_SPECIFIC_PASSWORD"
}
EOF
)
    echo "$CREDENTIALS" | security add-generic-password -s "AC_PASSWORD" -a "$KEYCHAIN_ACCOUNT" -w "$CREDENTIALS" -U
elif [[ $METHOD_CHOICE =~ ^[2]$ ]]; then
    if [ -z "$API_KEY_ID" ]; then read -p "API Key ID: " API_KEY_ID; fi
    if [ -z "$ISSUER_ID" ]; then read -p "Issuer ID: " ISSUER_ID; fi
    KEY_FILE_PATH="${KEY_FILE_PATH:-$API_KEY_FILE}"
    if [ -z "$KEY_FILE_PATH" ]; then read -p "Path to .p8: " KEY_FILE_PATH; fi
    if [ ! -f "$KEY_FILE_PATH" ]; then echo "❌ Not found: $KEY_FILE_PATH"; exit 1; fi
    mkdir -p ~/.appstoreconnect/private_keys
    cp "$KEY_FILE_PATH" ~/.appstoreconnect/private_keys/AuthKey_${API_KEY_ID}.p8
    chmod 600 ~/.appstoreconnect/private_keys/AuthKey_${API_KEY_ID}.p8
    CREDENTIALS=$(cat <<EOF
{
  "method": "api_key",
  "api_key_id": "$API_KEY_ID",
  "issuer_id": "$ISSUER_ID",
  "key_file": "~/.appstoreconnect/private_keys/AuthKey_${API_KEY_ID}.p8"
}
EOF
)
    echo "$CREDENTIALS" | security add-generic-password -s "AC_PASSWORD" -a "$KEYCHAIN_ACCOUNT" -w "$CREDENTIALS" -U
else
    echo "❌ Invalid choice"; exit 1
fi

echo "✅ Done. Run: ./scripts/build-ipa-for-testflight.sh --upload"
