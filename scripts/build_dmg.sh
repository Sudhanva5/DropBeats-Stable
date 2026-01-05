#!/bin/bash

# Exit on error
set -e

echo "🏗️ Building DropBeat..."

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
xcodebuild \
    -project DropBeat.xcodeproj \
    -scheme DropBeat \
    -configuration Release \
    -derivedDataPath ../build/derived \
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

echo "📦 Bundling Python runtime into app..."
# Check if Python bundle exists
PYTHON_BUNDLE="build/python_bundle/python"
if [ -d "$PYTHON_BUNDLE" ]; then
    echo "✅ Found Python bundle, copying to app Resources..."
    mkdir -p "$APP_PATH/Contents/Resources"
    cp -r "$PYTHON_BUNDLE" "$APP_PATH/Contents/Resources/"
    echo "✅ Python bundle added to app ($(du -sh "$APP_PATH/Contents/Resources/python" | cut -f1))"
else
    echo "⚠️  No Python bundle found at $PYTHON_BUNDLE"
    echo "   Run ./scripts/bundle_python.sh first to create bundled Python"
    echo "   App will use system Python if available"
fi

echo "🔏 Self-signing the app..."
# Remove existing signature if any
codesign --remove-signature "$APP_PATH" || true
# Self-sign with ad-hoc signature
codesign --force --deep --sign - "$APP_PATH"

echo "📦 Creating DMG..."
# Create a temporary directory for DMG contents
DMG_DIR="build/dmg"
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"

# Copy the app to the DMG directory
cp -R "$APP_PATH" "$DMG_DIR/"

# Create a symbolic link to Applications folder
ln -s /Applications "$DMG_DIR/Applications"

# Create the DMG
create-dmg \
    --volname "DropBeat Installer" \
    --volicon "$APP_PATH/Contents/Resources/AppIcon.icns" \
    --window-pos 200 120 \
    --window-size 800 400 \
    --icon-size 100 \
    --icon "DropBeat.app" 200 190 \
    --hide-extension "DropBeat.app" \
    --app-drop-link 600 185 \
    "build/DropBeat.dmg" \
    "$DMG_DIR" || {
        echo "❌ Failed to create DMG"
        exit 1
    }

# Print DMG size
echo "📊 DMG Size:"
ls -lh build/DropBeat.dmg

echo "✅ Done! DMG created at build/DropBeat.dmg" 