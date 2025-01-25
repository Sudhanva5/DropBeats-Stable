#!/bin/bash

# Exit on error
set -e

# Check if app path is provided
if [ "$#" -ne 1 ]; then
    echo "❌ Usage: $0 <path/to/DropBeats.app>"
    exit 1
fi

APP_PATH="$1"

# Verify app exists
if [ ! -d "$APP_PATH" ]; then
    echo "❌ App not found at $APP_PATH"
    exit 1
fi

# Create distribution directory
DIST_DIR="dist"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

echo "📦 Creating distribution package..."

# Copy README if it exists in current directory
if [ -f "README.md" ]; then
    echo "📄 Including README.md..."
    cp "README.md" "$DIST_DIR/"
fi

echo "🔏 Self-signing the app..."
# Remove existing signature if any
codesign --remove-signature "$APP_PATH" || true
# Self-sign with ad-hoc signature
codesign --force --deep --sign - "$APP_PATH"

echo "📀 Creating DMG..."
# Create a temporary directory for DMG contents
DMG_DIR="$DIST_DIR/dmg_temp"
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"

# Copy the app to the DMG directory
cp -R "$APP_PATH" "$DMG_DIR/"

# Create a symbolic link to Applications folder
rm -f "$DMG_DIR/Applications"
ln -s /Applications "$DMG_DIR/Applications"

# Create DMG using hdiutil
TEMP_DMG="$DIST_DIR/temp.dmg"
FINAL_DMG="$DIST_DIR/DropBeat.dmg"

# Create temporary DMG
hdiutil create -volname "DropBeat Installer" -srcfolder "$DMG_DIR" -ov -format UDRW "$TEMP_DMG"

# Convert to compressed final DMG
hdiutil convert "$TEMP_DMG" -format UDZO -o "$FINAL_DMG"

# Clean up
rm -f "$TEMP_DMG"
rm -rf "$DMG_DIR"

echo "🤐 Creating ZIP for Gumroad..."
# Create a temporary directory for ZIP contents
ZIP_DIR="$DIST_DIR/zip_temp"
mkdir -p "$ZIP_DIR"

# Copy app and README to ZIP directory
cp -R "$APP_PATH" "$ZIP_DIR/"
if [ -f "README.md" ]; then
    cp "README.md" "$ZIP_DIR/"
fi

# Create ZIP file
cd "$DIST_DIR/zip_temp"
zip -r "../DropBeat.zip" .
cd ../..

# Clean up ZIP temp directory
rm -rf "$DIST_DIR/zip_temp"

# Print package sizes
echo "📊 Package Sizes:"
cd "$DIST_DIR"
ls -lh DropBeat.dmg DropBeat.zip
cd ..

echo "✅ Done! Distribution package created in $DIST_DIR/"
echo "   - DMG installer: $DIST_DIR/DropBeat.dmg"
echo "   - Gumroad ZIP:   $DIST_DIR/DropBeat.zip"
echo "   - README:        $DIST_DIR/README.md (if exists)" 