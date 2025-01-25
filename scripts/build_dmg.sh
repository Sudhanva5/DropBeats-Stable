#!/bin/bash

# Exit on error
set -e

echo "🏗️ Building DropBeat..."

# Clean build directory
rm -rf build
mkdir -p build

# Navigate to the project directory
cd DropBeat

# Build the app
xcodebuild \
    -project DropBeat.xcodeproj \
    -scheme DropBeats \
    -configuration Release \
    -derivedDataPath ../build/derived \
    clean build || {
        echo "❌ Build failed"
        exit 1
    }

# Navigate back to root
cd ..

# Get the path to the built app
APP_PATH="build/derived/Build/Products/Release/DropBeats.app"

# Check if app was built
if [ ! -d "$APP_PATH" ]; then
    echo "❌ App not found at $APP_PATH"
    exit 1
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
    --icon "DropBeats.app" 200 190 \
    --hide-extension "DropBeats.app" \
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