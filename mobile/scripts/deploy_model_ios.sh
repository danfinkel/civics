#!/bin/bash
# Deploy GGUF model to iOS device via Xcode Device Manager
#
# Usage: ./scripts/deploy_model_ios.sh <device-id>
# Example: ./scripts/deploy_model_ios.sh 00008150-001A18223C40401C

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MODEL_PATH="$PROJECT_ROOT/assets/models/gemma-4-E2B-it-Q4_K_M.gguf"
DEVICE_ID="${1:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== CivicLens iOS Model Deploy ==="
echo ""

# Check device ID provided
if [ -z "$DEVICE_ID" ]; then
    echo -e "${RED}Error: Device ID required${NC}"
    echo "Usage: $0 <device-id>"
    echo ""
    echo "Available devices:"
    flutter devices
    exit 1
fi

# Check model exists
if [ ! -f "$MODEL_PATH" ]; then
    echo -e "${RED}Error: Model not found at $MODEL_PATH${NC}"
    echo "Download or copy model to assets/models/ first"
    exit 1
fi

MODEL_SIZE=$(ls -lh "$MODEL_PATH" | awk '{print $5}')
echo "Model: $MODEL_PATH"
echo "Size: $MODEL_SIZE"
echo "Device: $DEVICE_ID"
echo ""

# Check if Xcode is installed
if ! command -v xcrun &> /dev/null; then
    echo -e "${RED}Error: Xcode not found${NC}"
    echo "Install Xcode from App Store"
    exit 1
fi

# Get the app container path from device
echo -e "${YELLOW}Step 1: Finding CivicLens app on device...${NC}"

# Use ios-deploy or xcresult to get app path
# For now, we'll use a manual approach with instructions

echo ""
echo "=== Manual Steps Required ==="
echo ""
echo "Xcode Device Manager doesn't have a CLI for container download/upload."
echo ""
echo "Please follow these steps:"
echo ""
echo "1. Open Xcode"
echo "2. Window > Devices and Simulators (Cmd+Shift+2)"
echo "3. Select your iPhone from the list"
echo "4. Find 'CivicLens' under Installed Apps"
echo "5. Click the gear icon (⚙️) > 'Download Container...'"
echo "6. Save the .xcappdata file (e.g., to Desktop)"
echo "7. Run this script again with the container path:"
echo ""
echo "   $0 $DEVICE_ID /path/to/CivicLens.xcappdata"
echo ""
echo "Or manually:"
echo "   - Right-click .xcappdata > Show Package Contents"
echo "   - Navigate to AppData/Documents/"
echo "   - mkdir -p models"
echo "   - cp $MODEL_PATH AppData/Documents/models/"
echo "   - In Xcode: gear icon > 'Upload Container...'"
echo ""

# If container path provided as second arg, automate the copy
CONTAINER_PATH="${2:-}"

if [ -n "$CONTAINER_PATH" ]; then
    if [ ! -d "$CONTAINER_PATH" ]; then
        echo -e "${RED}Error: Container not found at $CONTAINER_PATH${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Step 2: Copying model to container...${NC}"

    MODELS_DIR="$CONTAINER_PATH/AppData/Documents/models"
    mkdir -p "$MODELS_DIR"

    echo "Copying $MODEL_SIZE model..."
    cp "$MODEL_PATH" "$MODELS_DIR/"

    echo -e "${GREEN}✓ Model copied to container${NC}"
    echo ""
    echo -e "${YELLOW}Step 3: Upload container to device${NC}"
    echo ""
    echo "In Xcode:"
    echo "1. Select your iPhone in Devices and Simulators"
    echo "2. Find CivicLens app"
    echo "3. Click gear icon (⚙️) > 'Upload Container...'"
    echo "4. Select: $CONTAINER_PATH"
    echo ""
    echo "This will take ~2-3 minutes for the 2.9GB model"
    echo ""
    echo -e "${GREEN}Container ready at: $CONTAINER_PATH${NC}"
fi

echo ""
echo "=== Alternative: Bundle in App (Slower build, no deploy needed) ==="
echo ""
echo "To include model in app bundle (not recommended for 2.9GB):"
echo "1. Copy model to ios/Runner/"
echo "2. Update pubspec.yaml to include as asset"
echo "3. Build and run"
echo ""
