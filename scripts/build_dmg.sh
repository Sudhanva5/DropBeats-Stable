#!/bin/bash

# Exit on error
set -e

echo "🏗️ Building DropBeats..."

# Clean build directory (preserve python_bundle if it exists)
if [ -d "build/python_bundle" ]; then
    echo "💾 Preserving Python bundle..."
    mv build/python_bundle /tmp/dropbeat_python_bundle_temp
fi

rm -rf build
mkdir -p build

if [ -d "/tmp/dropbeat_python_bundle_temp" ]; then
    echo "📦 Restoring Python bundle..."
    mv /tmp/dropbeat_python_bundle_temp build/python_bundle
fi

# Navigate to the project directory
cd DropBeat

# Build the app
# Code signing is disabled for this step on purpose. The project pins
# DEVELOPMENT_TEAM = KX9B67F8HJ with automatic signing, and no certificate for
# that team exists on this machine, so Xcode fails with "No signing certificate
# Mac Development found". It does not matter: build_and_notarize.sh strips
# whatever signature this produces and re-signs with the Developer ID for team
# 27KHWRZ25B, which is the signature that actually ships.
xcodebuild \
    -project DropBeat.xcodeproj \
    -scheme DropBeat \
    -configuration Release \
    -derivedDataPath ../build/derived \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    clean build || {
        echo "❌ Build failed"
        exit 1
    }

# Navigate back to root
cd ..

# Get the path to the built app
APP_PATH="build/derived/Build/Products/Release/DropBeat.app"

# Check if app was built
if [ ! -d "$APP_PATH" ]; then
    echo "❌ App not found at $APP_PATH"
    exit 1
fi

echo "📦 Bundling Python runtime and backend API into app..."
mkdir -p "$APP_PATH/Contents/Resources"

# Bundle Python runtime
PYTHON_BUNDLE="build/python_bundle/python"
if [ -d "$PYTHON_BUNDLE" ]; then
    echo "✅ Found Python bundle, copying to app Resources..."
    cp -r "$PYTHON_BUNDLE" "$APP_PATH/Contents/Resources/"
    echo "✅ Python bundle added to app ($(du -sh "$APP_PATH/Contents/Resources/python" | cut -f1))"
else
    echo "⚠️  No Python bundle found at $PYTHON_BUNDLE"
    echo "   Run ./scripts/bundle_python.sh first to create bundled Python"
    echo "   App will use system Python if available"
fi

# Bundle backend API files
BACKEND_API="Server/api"
if [ -d "$BACKEND_API" ]; then
    echo "✅ Found backend API, copying to app Resources..."
    mkdir -p "$APP_PATH/Contents/Resources/backend"
    cp -r "$BACKEND_API" "$APP_PATH/Contents/Resources/backend/"
    # Remove unnecessary files from bundled backend
    rm -rf "$APP_PATH/Contents/Resources/backend/api/__pycache__"
    rm -rf "$APP_PATH/Contents/Resources/backend/api/.env"
    echo "✅ Backend API added to app ($(du -sh "$APP_PATH/Contents/Resources/backend" | cut -f1))"
else
    echo "❌ Backend API not found at $BACKEND_API"
    exit 1
fi

echo "🔏 Self-signing the app..."
# Remove existing signature if any
codesign --remove-signature "$APP_PATH" || true
# Self-sign with ad-hoc signature
codesign --force --deep --sign - "$APP_PATH"

echo "📦 Creating DMG with create-dmg (npm)..."
# Use npm version of create-dmg (simpler, more reliable)
# It automatically creates the DMG with proper layout

DMG_OUTPUT="build/DropBeats.dmg"
rm -f "$DMG_OUTPUT"

# Create DMG using npm create-dmg (skip signing, we'll sign later in build_and_notarize.sh)
create-dmg "$APP_PATH" build/ --overwrite --no-code-sign || {
    echo "❌ Failed to create DMG"
    exit 1
}

# Rename the DMG to our desired name
CREATED_DMG=$(find build -name "DropBeat *.dmg" -type f | head -n 1)
if [ -n "$CREATED_DMG" ]; then
    mv "$CREATED_DMG" "$DMG_OUTPUT"
    echo "✅ DMG created at $DMG_OUTPUT"
else
    echo "❌ Could not find created DMG"
    exit 1
fi

# Print DMG size
echo "📊 DMG Size:"
ls -lh "$DMG_OUTPUT"

echo "✅ Done! DMG created at build/DropBeats.dmg" 