#!/bin/bash

# Complete build, sign, notarize, and staple workflow for DropBeat
# Uses npm create-dmg and ImageMagick

set -e

echo "🚀 DropBeats - Complete Build & Notarization Workflow"
echo "=================================================="

# Configuration
DEVELOPER_ID="FEB42A675CAC538DD25EE6504B149F7F8FC78F61"  # Certificate hash to avoid ambiguity
APPLE_ID="team.ncpudp@gmail.com"
TEAM_ID="27KHWRZ25B"
BUNDLE_ID="com.sudhanva.DropBeat"

# notarytool credential profile, created with:
#   xcrun notarytool store-credentials "DropBeats" \
#       --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password <app-specific-password>
# This replaces --password "@keychain:AC_PASSWORD". That form resolved to
# something Apple rejected with "HTTP status code: 401. Invalid credentials"
# even though the AC_PASSWORD keychain item held the correct, working password
# (passing the same value via --password directly authenticated fine).
NOTARY_PROFILE="DropBeats"

# Step 1: Build the app
echo ""
echo "📦 Step 1: Building app with bundled Python..."
./scripts/build_dmg.sh

APP_PATH="build/derived/Build/Products/Release/DropBeat.app"
DMG_PATH="build/DropBeats.dmg"

# Step 2: Sign the app with Developer ID
echo ""
echo "🔏 Step 2: Signing app with Developer ID..."

# Remove old signature
codesign --remove-signature "$APP_PATH" 2>/dev/null || true

# Sign all Python binaries first
echo "📝 Signing Python bundle..."
./scripts/sign_python_bundle.sh "$APP_PATH"

# Sign the app bundle
echo "📝 Signing app bundle..."
codesign --force --deep \
    --options runtime \
    --sign "$DEVELOPER_ID" \
    --timestamp \
    "$APP_PATH"

# Verify signature
echo "✅ Verifying app signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

# Step 3: Notarize the app
echo ""
echo "📤 Step 3: Notarizing app..."

# Create a ZIP for notarization (faster upload than DMG)
APP_ZIP="build/DropBeats-app.zip"
rm -f "$APP_ZIP"
ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP"

echo "📤 Submitting app for notarization..."
APP_SUBMIT_OUTPUT=$(xcrun notarytool submit "$APP_ZIP" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait)

echo "$APP_SUBMIT_OUTPUT"

# Extract submission ID
APP_SUBMISSION_ID=$(echo "$APP_SUBMIT_OUTPUT" | grep "id:" | head -n 1 | awk '{print $2}')
echo "📋 App Submission ID: $APP_SUBMISSION_ID"

# Check if notarization succeeded
if echo "$APP_SUBMIT_OUTPUT" | grep -q "status: Accepted"; then
    echo "✅ App notarization ACCEPTED"

    # Staple the ticket to the app
    echo "📎 Stapling notarization ticket to app..."
    xcrun stapler staple "$APP_PATH"

    echo "✅ App stapled successfully"
else
    echo "❌ App notarization FAILED"
    echo "📋 Fetching notarization log..."
    xcrun notarytool log "$APP_SUBMISSION_ID" \
        --keychain-profile "$NOTARY_PROFILE"
    exit 1
fi

# Step 4: Recreate DMG with notarized app
echo ""
echo "📦 Step 4: Creating DMG with notarized app..."

rm -f "$DMG_PATH"

# Create DMG using npm create-dmg
echo "🎨 Using create-dmg (npm) with ImageMagick..."
create-dmg "$APP_PATH" build/ || true

# Rename the DMG
CREATED_DMG=$(find build -name "DropBeat *.dmg" -type f | head -n 1)
if [ -n "$CREATED_DMG" ]; then
    mv "$CREATED_DMG" "$DMG_PATH"
    echo "✅ DMG created at $DMG_PATH"
else
    echo "❌ Could not find created DMG"
    exit 1
fi

# Step 5: Sign the DMG
echo ""
echo "🔏 Step 5: Signing DMG..."

codesign --force \
    --sign "$DEVELOPER_ID" \
    --timestamp \
    "$DMG_PATH"

echo "✅ Verifying DMG signature..."
codesign --verify --verbose=2 "$DMG_PATH"

# Step 6: Notarize the DMG
echo ""
echo "📤 Step 6: Notarizing DMG..."

DMG_SUBMIT_OUTPUT=$(xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait)

echo "$DMG_SUBMIT_OUTPUT"

# Extract DMG submission ID
DMG_SUBMISSION_ID=$(echo "$DMG_SUBMIT_OUTPUT" | grep "id:" | head -n 1 | awk '{print $2}')
echo "📋 DMG Submission ID: $DMG_SUBMISSION_ID"

# Check if DMG notarization succeeded
if echo "$DMG_SUBMIT_OUTPUT" | grep -q "status: Accepted"; then
    echo "✅ DMG notarization ACCEPTED"

    # Staple the ticket to the DMG
    echo "📎 Stapling notarization ticket to DMG..."
    xcrun stapler staple "$DMG_PATH"

    echo "✅ DMG stapled successfully"
else
    echo "❌ DMG notarization FAILED"
    echo "📋 Fetching notarization log..."
    xcrun notarytool log "$DMG_SUBMISSION_ID" \
        --keychain-profile "$NOTARY_PROFILE"
    exit 1
fi

# Step 7: Verify everything
echo ""
echo "🔍 Step 7: Final verification..."

# Verify stapling on app
echo "📝 Verifying app stapling..."
xcrun stapler validate "$APP_PATH"

# Verify stapling on DMG
echo "📝 Verifying DMG stapling..."
xcrun stapler validate "$DMG_PATH"

# Verify Gatekeeper will accept it
echo "📝 Verifying Gatekeeper approval..."
spctl --assess --type execute --verbose=2 "$APP_PATH" || echo "⚠️  Gatekeeper check skipped (may fail on self-signed cert)"

# Step 8: Copy to Desktop with version number
echo ""
echo "📦 Step 8: Copying to Desktop..."

APP_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "unknown")
FINAL_DMG="$HOME/Desktop/DropBeats-v${APP_VERSION}-Notarized.dmg"
cp "$DMG_PATH" "$FINAL_DMG"

echo ""
echo "✅ =================================================="
echo "✅ BUILD AND NOTARIZATION COMPLETE!"
echo "✅ =================================================="
echo ""
echo "📊 Final DMG: $(ls -lh "$FINAL_DMG" | awk '{print $5}')"
echo "📂 Location: $FINAL_DMG"
echo ""
echo "🎉 Ready for Gumroad distribution!"
echo ""
echo "Notarization IDs:"
echo "  App:  $APP_SUBMISSION_ID"
echo "  DMG:  $DMG_SUBMISSION_ID"
