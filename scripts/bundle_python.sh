#!/bin/bash

# Bundle minimal Python runtime for DropBeat distribution
# This creates a standalone Python with only required dependencies

set -e

echo "🐍 Bundling Python for DropBeats..."

# Get absolute path to script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"

# Configuration
PYTHON_VERSION="3.11.7"
BUILD_DIR="$ROOT_DIR/build/python_bundle"
PYTHON_DIR="$BUILD_DIR/python"
BACKEND_DIR="$ROOT_DIR/Server/api"

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    PYTHON_ARCH="aarch64"
else
    PYTHON_ARCH="x86_64"
fi

echo "📦 Architecture: $ARCH ($PYTHON_ARCH)"

# Clean previous build
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Download standalone Python from python.org
echo "⬇️  Downloading Python ${PYTHON_VERSION}..."
cd "$BUILD_DIR"

if [ "$ARCH" = "arm64" ]; then
    # Apple Silicon
    PYTHON_URL="https://www.python.org/ftp/python/${PYTHON_VERSION}/python-${PYTHON_VERSION}-macos11.pkg"
else
    # Intel
    PYTHON_URL="https://www.python.org/ftp/python/${PYTHON_VERSION}/python-${PYTHON_VERSION}-macosx10.9.pkg"
fi

# Alternative: Use python-build-standalone (smaller, better for bundling)
STANDALONE_URL="https://github.com/indygreg/python-build-standalone/releases/download/20231002/cpython-3.11.6+20231002-${PYTHON_ARCH}-apple-darwin-install_only.tar.gz"

echo "📥 Downloading from: $STANDALONE_URL"
curl -L -o python.tar.gz "$STANDALONE_URL"

echo "📂 Extracting Python..."
tar -xzf python.tar.gz

# Verify Python works
echo "✅ Testing Python..."
"$PYTHON_DIR/bin/python3" --version

# Install required dependencies
echo "📦 Installing Python dependencies..."
"$PYTHON_DIR/bin/python3" -m pip install --upgrade pip

# Install only required packages
# yt-dlp is intentionally unpinned: YouTube breaks older versions within weeks,
# so every bundle should ship the newest release available at build time.
"$PYTHON_DIR/bin/pip3" install \
    uvicorn==0.25.0 \
    fastapi==0.109.0 \
    yt-dlp \
    ytmusicapi==1.12.2 \
    pydantic==2.5.3 \
    python-dotenv==1.0.0

echo "📌 Bundled extractor versions:"
"$PYTHON_DIR/bin/python3" -c "import yt_dlp, ytmusicapi; print(f'   yt-dlp     {yt_dlp.version.__version__}'); print(f'   ytmusicapi {ytmusicapi.__version__}')"

echo "🧹 Cleaning up unnecessary files..."

# Remove unnecessary files to reduce size
find "$PYTHON_DIR" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find "$PYTHON_DIR" -type d -name "*.dist-info" -exec rm -rf {} + 2>/dev/null || true
find "$PYTHON_DIR" -type f -name "*.pyc" -delete 2>/dev/null || true
find "$PYTHON_DIR" -type f -name "*.pyo" -delete 2>/dev/null || true
find "$PYTHON_DIR" -name "test" -type d -exec rm -rf {} + 2>/dev/null || true
find "$PYTHON_DIR" -name "tests" -type d -exec rm -rf {} + 2>/dev/null || true

# Remove tkinter and other GUI libraries (not needed for server)
rm -rf "$PYTHON_DIR/lib/python3.11/tkinter" 2>/dev/null || true
rm -rf "$PYTHON_DIR/lib/python3.11/idlelib" 2>/dev/null || true
rm -rf "$PYTHON_DIR/lib/python3.11/turtledemo" 2>/dev/null || true

# Create backend bundle directory
echo "📦 Bundling backend API..."
mkdir -p "$PYTHON_DIR/backend/api"
cp -r "$BACKEND_DIR"/* "$PYTHON_DIR/backend/api/"

# Strip bytecode AFTER copying the backend. The cleanup pass above runs before
# this copy, so any __pycache__ left in Server/api by a local dev run would
# otherwise be sealed into the app signature - and deleting it later then
# reports "a sealed resource is missing or invalid".
find "$PYTHON_DIR/backend" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find "$PYTHON_DIR/backend" -type f -name "*.pyc" -delete 2>/dev/null || true

# Create a test script to verify the bundle works
echo "🧪 Creating test script..."
cat > "$PYTHON_DIR/test_bundle.sh" << 'EOF'
#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR/backend/api"
"$SCRIPT_DIR/bin/python3" -m uvicorn main:app --host 127.0.0.1 --port 4002 --log-level info
EOF
chmod +x "$PYTHON_DIR/test_bundle.sh"

# Get bundle size
BUNDLE_SIZE=$(du -sh "$PYTHON_DIR" | cut -f1)
echo "📊 Bundle size: $BUNDLE_SIZE"

echo "✅ Python bundle created at: $PYTHON_DIR"
echo ""
echo "📋 Next steps:"
echo "1. Test the bundle: ./$PYTHON_DIR/test_bundle.sh"
echo "2. Copy to Xcode project: cp -r $PYTHON_DIR DropBeat/DropBeat/Resources/"
echo "3. Add to Xcode: Drag 'python' folder to Resources in Xcode"
echo "4. Build settings: Ensure 'python' folder is included in Copy Bundle Resources"
echo ""
echo "🎯 The app will automatically detect and use bundled Python"
