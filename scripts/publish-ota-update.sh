#!/bin/bash
#
# Flixor OTA Update Publisher
#
# Builds and uploads an OTA update to the self-hosted server
#
# Usage:
#   ./scripts/publish-ota-update.sh [runtime_version] [release_notes]
#
# Environment:
#   FLIXOR_OTA_UPLOAD_KEY - Required upload authentication key
#
# Examples:
#   ./scripts/publish-ota-update.sh
#   ./scripts/publish-ota-update.sh "0.1.8" "Bug fixes and performance improvements"
#

set -e

# Configuration
OTA_SERVER="${FLIXOR_OTA_SERVER:-https://ota.flixor.xyz}"
UPLOAD_KEY="${FLIXOR_OTA_UPLOAD_KEY}"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MOBILE_DIR="$PROJECT_ROOT/apps/mobile"

# Validate upload key
if [ -z "$UPLOAD_KEY" ]; then
  echo "Error: FLIXOR_OTA_UPLOAD_KEY environment variable is not set"
  echo "Set it with: export FLIXOR_OTA_UPLOAD_KEY=<your-upload-key>"
  exit 1
fi

# Parse arguments
RUNTIME_VERSION="${1:-}"
RELEASE_NOTES="${2:-}"

# Get runtime version from app.json if not provided
if [ -z "$RUNTIME_VERSION" ]; then
  RUNTIME_VERSION=$(jq -r '.expo.runtimeVersion // .expo.version' "$MOBILE_DIR/app.json")
fi

# Get git commit info
COMMIT_HASH=$(git -C "$PROJECT_ROOT" rev-parse --short HEAD)
COMMIT_MSG=$(git -C "$PROJECT_ROOT" log -1 --pretty=%B | head -1)

# Use commit message as release notes if not provided
if [ -z "$RELEASE_NOTES" ]; then
  RELEASE_NOTES="$COMMIT_MSG"
fi

echo "======================================"
echo "Flixor OTA Update Publisher"
echo "======================================"
echo "Server: $OTA_SERVER"
echo "Runtime Version: $RUNTIME_VERSION"
echo "Commit: $COMMIT_HASH"
echo "Release Notes: $RELEASE_NOTES"
echo "======================================"

# Navigate to mobile directory
cd "$MOBILE_DIR"

# Clean previous build
echo ""
echo "[1/5] Cleaning previous build..."
rm -rf dist update.zip

# Export update bundle
echo ""
echo "[2/5] Building OTA bundle..."
npx expo export --platform ios --platform android --output-dir dist

# Create expoconfig.json (required by OTA server)
echo ""
echo "[3/5] Creating expo config..."
jq '.expo' "$MOBILE_DIR/app.json" > dist/expoconfig.json

# Create zip archive
echo ""
echo "[4/5] Creating update package..."
cd dist
zip -r ../update.zip . -x "*.DS_Store"
cd ..

# Get file size
UPDATE_SIZE=$(ls -lh update.zip | awk '{print $5}')
echo "Package size: $UPDATE_SIZE"

# Upload to OTA server
echo ""
echo "[5/5] Uploading to OTA server..."
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$OTA_SERVER/api/upload" \
  -F "file=@update.zip" \
  -F "runtimeVersion=$RUNTIME_VERSION" \
  -F "commitHash=$COMMIT_HASH" \
  -F "commitMessage=$COMMIT_MSG" \
  -F "releaseNotes=$RELEASE_NOTES" \
  -F "uploadKey=$UPLOAD_KEY")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
  echo ""
  echo "======================================"
  echo "SUCCESS! OTA update published"
  echo "======================================"
  echo "Runtime Version: $RUNTIME_VERSION"
  echo "Commit: $COMMIT_HASH"
  echo ""
  echo "Server Response:"
  echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
else
  echo ""
  echo "======================================"
  echo "FAILED! Upload returned HTTP $HTTP_CODE"
  echo "======================================"
  echo "$BODY"
  exit 1
fi

# Cleanup
rm -f update.zip

echo ""
echo "Done! Users will receive this update on next app launch."
