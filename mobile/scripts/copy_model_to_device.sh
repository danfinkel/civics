#!/bin/bash
# Copy model to iOS device for testing
#
# Usage:
#   1. Run app on device first (to create app container)
#   2. ./scripts/copy_model_to_device.sh
#   3. Check console output for app documents path

set -e

MODEL_PATH="/Users/danfinkel/github/civics/mobile/assets/models/gemma-4-E2B-it-Q4_K_M.gguf"

echo "=== Copy Model to iOS Device ==="
echo "Model: $MODEL_PATH"
echo ""
echo "To copy the model to your iPhone:"
echo ""
echo "Option 1: Use Xcode Device Manager"
echo "  1. Open Xcode"
echo "  2. Window > Devices and Simulators"
echo "  3. Select your device"
echo "  4. Find CivicLens app"
echo "  5. Click gear icon > Download Container"
echo "  6. Copy model to Documents/models/"
echo "  7. Upload container back to device"
echo ""
echo "Option 2: Use flutter run with custom path"
echo "  1. Modify code to load from bundle path temporarily"
echo "  2. Include model in app bundle (not recommended for 2.9GB)"
echo ""
echo "Option 3: Use app to download at runtime"
echo "  1. Start app"
echo "  2. Use ModelManager.downloadModel()"
echo "  3. Host model on local server during development"
echo ""
echo "Recommended for testing: Option 1"
echo ""
echo "Model size: $(ls -lh "$MODEL_PATH" | awk '{print $5}')"
