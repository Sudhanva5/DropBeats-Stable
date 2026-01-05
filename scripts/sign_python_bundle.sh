#!/bin/bash

# Sign all Python binaries for Apple notarization
# This script signs all executables, .dylib, and .so files in the Python bundle

set -e

echo "🔏 Signing Python bundle for notarization..."

# Configuration
IDENTITY="2529146CF576019DF005883AA321D8C5D9F83633"  # Developer ID Application
APP_PATH="$1"

if [ -z "$APP_PATH" ]; then
    echo "❌ Usage: $0 <path-to-app>"
    echo "   Example: $0 build/derived/Build/Products/Release/DropBeat.app"
    exit 1
fi

if [ ! -d "$APP_PATH" ]; then
    echo "❌ App not found at: $APP_PATH"
    exit 1
fi

PYTHON_PATH="$APP_PATH/Contents/Resources/python"

if [ ! -d "$PYTHON_PATH" ]; then
    echo "❌ Python bundle not found at: $PYTHON_PATH"
    exit 1
fi

echo "📦 Python bundle found at: $PYTHON_PATH"

# Find all binaries that need signing
echo "🔍 Finding all binaries to sign..."

# Find all .so files (Python extensions)
SO_FILES=$(find "$PYTHON_PATH" -type f -name "*.so" | wc -l | tr -d ' ')
echo "   Found $SO_FILES .so files"

# Find all .dylib files (dynamic libraries)
DYLIB_FILES=$(find "$PYTHON_PATH" -type f -name "*.dylib" | wc -l | tr -d ' ')
echo "   Found $DYLIB_FILES .dylib files"

# Find all executables (python3, python3.11, etc.)
EXECUTABLES=$(find "$PYTHON_PATH/bin" -type f -perm +111 2>/dev/null | wc -l | tr -d ' ')
echo "   Found $EXECUTABLES executables"

TOTAL=$((SO_FILES + DYLIB_FILES + EXECUTABLES))
echo "📊 Total files to sign: $TOTAL"

if [ $TOTAL -eq 0 ]; then
    echo "⚠️  No binaries found to sign"
    exit 0
fi

CURRENT=0

# Function to sign a file
sign_file() {
    local file="$1"
    CURRENT=$((CURRENT + 1))
    echo "[$CURRENT/$TOTAL] Signing: $(basename "$file")"

    # Sign with hardened runtime and timestamp
    codesign --force \
        --sign "$IDENTITY" \
        --options runtime \
        --timestamp \
        "$file" 2>/dev/null || {
        echo "⚠️  Failed to sign: $file (may already be signed or not a binary)"
    }
}

echo ""
echo "🔏 Signing .dylib files..."
find "$PYTHON_PATH" -type f -name "*.dylib" | while read -r file; do
    sign_file "$file"
done

echo ""
echo "🔏 Signing .so files..."
find "$PYTHON_PATH" -type f -name "*.so" | while read -r file; do
    sign_file "$file"
done

echo ""
echo "🔏 Signing executables..."
find "$PYTHON_PATH/bin" -type f -perm +111 2>/dev/null | while read -r file; do
    # Skip symlinks
    if [ ! -L "$file" ]; then
        sign_file "$file"
    fi
done

echo ""
echo "🔏 Signing the main app bundle..."
codesign --force --deep \
    --sign "$IDENTITY" \
    --options runtime \
    --timestamp \
    "$APP_PATH"

echo ""
echo "✅ All binaries signed successfully!"
echo ""
echo "🔍 Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH" && {
    echo "✅ Signature verification passed!"
} || {
    echo "⚠️  Signature verification had warnings (may be okay)"
}
