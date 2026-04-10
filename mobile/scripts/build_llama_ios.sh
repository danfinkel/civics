#!/bin/bash
# ============================================================================
# build_llama_ios.sh — Build llama.cpp for iOS arm64 with Gemma 4 support
# ============================================================================
#
# Produces a single self-contained libllama.dylib that includes:
#   llama, ggml (base/cpu/metal/blas), and mtmd (multimodal)
#
# CRITICAL: This script is pinned to a specific llama.cpp commit.
#           Do NOT change the commit hash without also updating the
#           Dart FFI struct definitions in llama_cpp_dart.
#           See ARCHITECTURE.md "Challenge 3" for why.
#
# Usage:
#   ./scripts/build_llama_ios.sh
#
# Output:
#   ios/Frameworks/libllama.dylib (signed, ready for Xcode embed)
#
# Prerequisites:
#   - Xcode with iOS SDK
#   - CMake
#   - Git
#   - Valid Apple Development signing identity
# ============================================================================

set -euo pipefail

# ── Pinned llama.cpp commit ────────────────────────────────────────────────
# This commit MUST match the FFI struct layouts in llama_cpp_dart 0.2.2
# (with our patches for use_direct_io, samplers/n_samplers, dry_run).
#
# If you need to update this commit:
#   1. Check `git diff OLD_COMMIT..NEW_COMMIT -- include/llama.h`
#   2. Look for ANY struct field additions, removals, or reordering
#   3. Patch the Dart FFI structs in llama_cpp.dart to match
#   4. Test on a real device — struct mismatches cause silent crashes
#
LLAMA_CPP_COMMIT="d9a12c82f0c81eea3ba54be5fb5250161993c450"
LLAMA_CPP_COMMIT_DATE="2026-04-08"
LLAMA_CPP_COMMIT_DESC="vocab: remove </s> eog token if gemma4 (#21492)"
# ───────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$PROJECT_ROOT/ios/Frameworks"
BUILD_DIR="/tmp/llama-ios-build"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  llama.cpp iOS Build (Gemma 4 E2B)                      ║${NC}"
echo -e "${CYAN}║  Commit: ${LLAMA_CPP_COMMIT:0:12}                           ║${NC}"
echo -e "${CYAN}║  Date:   ${LLAMA_CPP_COMMIT_DATE}                                  ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# ── Step 1: Clone or update llama.cpp ──────────────────────────────────────
echo -e "${YELLOW}[1/5] Preparing llama.cpp source...${NC}"

if [ -d "$BUILD_DIR/llama.cpp/.git" ]; then
    cd "$BUILD_DIR/llama.cpp"
    CURRENT_COMMIT=$(git rev-parse HEAD)
    if [ "$CURRENT_COMMIT" = "$LLAMA_CPP_COMMIT" ]; then
        echo "  Already at pinned commit"
    else
        echo "  Fetching and checking out pinned commit..."
        git fetch origin 2>/dev/null || true
        git checkout "$LLAMA_CPP_COMMIT" 2>/dev/null
    fi
else
    echo "  Cloning llama.cpp..."
    mkdir -p "$BUILD_DIR"
    git clone https://github.com/ggerganov/llama.cpp "$BUILD_DIR/llama.cpp" 2>/dev/null
    cd "$BUILD_DIR/llama.cpp"
    git checkout "$LLAMA_CPP_COMMIT" 2>/dev/null
fi

ACTUAL_COMMIT=$(git rev-parse HEAD)
if [ "$ACTUAL_COMMIT" != "$LLAMA_CPP_COMMIT" ]; then
    echo -e "${RED}ERROR: Failed to checkout pinned commit${NC}"
    echo "  Expected: $LLAMA_CPP_COMMIT"
    echo "  Got:      $ACTUAL_COMMIT"
    exit 1
fi
echo -e "  ${GREEN}✓ Pinned to $LLAMA_CPP_COMMIT${NC}"

# ── Step 2: Configure CMake for iOS arm64 ──────────────────────────────────
echo -e "${YELLOW}[2/5] Configuring CMake for iOS arm64...${NC}"

rm -rf build-ios
mkdir build-ios
cd build-ios

cmake .. \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DGGML_METAL=ON \
  -DLLAMA_CURL=OFF \
  -DLLAMA_BUILD_TESTS=OFF \
  -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_BUILD_TOOLS=ON \
  -DLLAMA_BUILD_SERVER=OFF \
  -DCMAKE_C_FLAGS="-fPIC" \
  -DCMAKE_CXX_FLAGS="-fPIC" \
  2>&1 | grep -E "^--|Configuring|Generating" || true

echo -e "  ${GREEN}✓ CMake configured${NC}"

# ── Step 3: Build static libraries ────────────────────────────────────────
echo -e "${YELLOW}[3/5] Building static libraries (this takes ~30s)...${NC}"

NCPU=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
cmake --build . --config Release --target mtmd -j"$NCPU" 2>&1 | tail -3

echo -e "  ${GREEN}✓ Static libraries built${NC}"

# ── Step 4: Link into single dylib ────────────────────────────────────────
echo -e "${YELLOW}[4/5] Linking combined libllama.dylib...${NC}"

IPHONEOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path)

clang++ -dynamiclib -arch arm64 \
  -isysroot "$IPHONEOS_SDK" \
  -mios-version-min=14.0 \
  -install_name @rpath/libllama.dylib \
  -o libllama.dylib \
  -Wl,-all_load \
  src/libllama.a \
  ggml/src/libggml-base.a \
  ggml/src/libggml-cpu.a \
  ggml/src/ggml-metal/libggml-metal.a \
  ggml/src/ggml-blas/libggml-blas.a \
  ggml/src/libggml.a \
  tools/mtmd/libmtmd.a \
  -framework Foundation -framework Metal -framework MetalKit \
  -framework Accelerate -lc++ \
  -sectcreate __DATA __ggml_metallib ggml/src/ggml-metal/autogenerated/ggml-metal-embed.metal \
  2>&1 | grep -v "ignoring duplicate" || true

DYLIB_SIZE=$(ls -lh libllama.dylib | awk '{print $5}')
echo -e "  ${GREEN}✓ libllama.dylib built ($DYLIB_SIZE)${NC}"

# Verify key symbols
LLAMA_SYMS=$(nm libllama.dylib | grep -c "T _llama_" || true)
GGML_SYMS=$(nm libllama.dylib | grep -c "T _ggml_" || true)
MTMD_SYMS=$(nm libllama.dylib | grep -c "T _mtmd_" || true)
GEMMA4=$(nm libllama.dylib | grep -c "gemma4" || true)

echo "  Symbols: ${LLAMA_SYMS} llama_, ${GGML_SYMS} ggml_, ${MTMD_SYMS} mtmd_"
if [ "$GEMMA4" -gt 0 ]; then
    echo -e "  ${GREEN}✓ Gemma 4 architecture support confirmed${NC}"
else
    echo -e "${RED}  ✗ WARNING: No Gemma 4 symbols found!${NC}"
fi

# Verify self-contained (no external deps beyond system frameworks)
EXTERNAL_DEPS=$(otool -L libllama.dylib | grep -v "@rpath\|/System/\|/usr/lib/" | tail -n +2 | wc -l | tr -d ' ')
if [ "$EXTERNAL_DEPS" -gt 0 ]; then
    echo -e "${RED}  ✗ WARNING: External dependencies detected:${NC}"
    otool -L libllama.dylib | grep -v "@rpath\|/System/\|/usr/lib/" | tail -n +2
fi

# ── Step 5: Copy and sign ─────────────────────────────────────────────────
echo -e "${YELLOW}[5/5] Installing to project...${NC}"

mkdir -p "$OUTPUT_DIR"
cp libllama.dylib "$OUTPUT_DIR/libllama.dylib"

# Sign with available Apple Development identity
SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | sed 's/.*"\(.*\)".*/\1/' || true)
if [ -n "$SIGNING_IDENTITY" ]; then
    codesign --force --sign "$SIGNING_IDENTITY" "$OUTPUT_DIR/libllama.dylib" 2>/dev/null
    echo -e "  ${GREEN}✓ Signed with: $SIGNING_IDENTITY${NC}"
else
    echo -e "${YELLOW}  ⚠ No signing identity found. Sign manually before deploying.${NC}"
fi

echo -e "  ${GREEN}✓ Installed to ios/Frameworks/libllama.dylib${NC}"

# ── Summary ───────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Build Complete                                         ║${NC}"
echo -e "${CYAN}╠══════════════════════════════════════════════════════════╣${NC}"
echo -e "${CYAN}║  Output:  ios/Frameworks/libllama.dylib ($DYLIB_SIZE)      ║${NC}"
echo -e "${CYAN}║  Commit:  ${LLAMA_CPP_COMMIT:0:12}                           ║${NC}"
echo -e "${CYAN}║  Gemma 4: Yes                                           ║${NC}"
echo -e "${CYAN}║  Metal:   Yes                                           ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Next: flutter clean && flutter pub get && flutter run --release -d <device>"
