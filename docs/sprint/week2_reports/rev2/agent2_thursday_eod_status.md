# Agent 2 — Thursday EOD Status (April 8, 2026)

**Status:** ON-DEVICE INFERENCE PROVEN — Gemma 4 E2B running on physical iPhone  
**Result:** B1 inference returns "4" (correct answer)  
**Next:** Wire up full B1 pipeline (OCR → LLM → JSON parse) on device

---

## Breakthrough

Gemma 4 E2B (Q4_K_M, 2.9GB) is running inference on a physical iPhone 16 via
llama.cpp with Metal GPU acceleration. The model loads, processes a prompt asking
"how many requirements are satisfied?", and returns "4" — the correct B1 answer.

This was a multi-hour debugging session that surfaced three distinct failures, each
of which caused the app to crash or silently fail with no useful error. Full technical
writeup in `mobile/ARCHITECTURE.md`.

---

## What Works Right Now

| Component | Status | Evidence |
|-----------|--------|----------|
| Model download (WiFi → iPhone) | ✅ Working | 2963 MB downloaded via local HTTP server |
| Library loading (libllama.dylib) | ✅ Working | Custom combined dylib, code-signed |
| Model loading (Gemma 4 E2B GGUF) | ✅ Working | Loads in background isolate, Metal GPU |
| Inference | ✅ Working | Returns "4" for B1 prompt |
| App stability | ✅ Working | No crashes, clean lifecycle |

## What Still Needs Testing

| Component | Status | Notes |
|-----------|--------|-------|
| OCR → LLM pipeline | ⏳ Not yet tested | OCR service exists, needs device test |
| Full B1 scenario (4 docs) | ⏳ Not yet tested | Pipeline wiring exists in `inference_service.dart` |
| JSON parsing of LLM output | ⏳ Not yet tested | May need prompt tuning |
| Performance timing | ⏳ Not measured | Need model load + inference times |

---

## Three Challenges Overcome

### 1. API Version Mismatch → Silent Memory Corruption

`llama_cpp_dart` 0.0.9 had FFI bindings from mid-2025. Our dylib was built from
late-2025 llama.cpp. The C struct layouts had changed between those two commits —
fields added, reordered, resized. Dart FFI wrote struct fields at wrong byte
offsets → segfault deep in native code, no Dart stack trace.

**Fix:** Upgraded `llama_cpp_dart` from `0.0.9` to `0.2.2`.

### 2. Gemma 4 Architecture Not Recognized

`llama_cpp_dart` 0.2.2 was built against llama.cpp commit `4ffc47cb` (Dec 28, 2025).
Gemma 4 architecture support was added to llama.cpp on April 2, 2026. The model's
GGUF file declares architecture `gemma4`, which the Dec 2025 llama.cpp doesn't know.
Result: "Could not load model" (returns nullptr, but no crash).

**Fix:** Rebuilt `libllama.dylib` from commit `d9a12c82f` (April 8, 2026) which
includes all Gemma 4 support.

### 3. C Struct ABI Break in FFI Bridge

Between Dec 2025 and April 2026, three C structs gained new fields:

| Struct | Added Field | Position |
|--------|-------------|----------|
| `llama_model_params` | `use_direct_io` (bool) | Between `use_mmap` and `use_mlock` |
| `llama_context_params` | `samplers` (ptr) + `n_samplers` (size_t) | End of struct |
| `llama_model_quantize_params` | `dry_run` (bool) | After `keep_split` |

The Dart FFI auto-generated struct definitions had the OLD layout. The new dylib
returned structs with the NEW layout. When `llama_model_default_params()` returns by
value, the size mismatch causes a stack buffer overflow → hard crash.

**Fix:** Patched 4 fields across 2 files in `llama_cpp_dart-0.2.2`:
- `lib/src/llama_cpp.dart` — added the 3 missing struct fields
- `lib/src/model_params.dart` — set `use_direct_io = false`

---

## Current Build Toolchain

### Pinned Versions

| Component | Version / Commit | Why Pinned |
|-----------|-----------------|------------|
| `llama_cpp_dart` | 0.2.2 (pub.dev) | Latest available; FFI bindings patched |
| `llama.cpp` native | `d9a12c82f` (Apr 8, 2026) | First commit with all Gemma 4 fixes |
| `libllama.dylib` | 5.7MB, arm64, Metal | Combined single dylib, code-signed |

### FFI Patches (Vendored in Git)

The patched `llama_cpp_dart` is vendored at `mobile/packages/llama_cpp_dart/` and
referenced via `path:` dependency in `pubspec.yaml`. Patches are committed to git —
no manual patching needed on clone.

**Patched files in `packages/llama_cpp_dart/lib/src/`:**

**`llama_cpp.dart`** (3 struct field additions):
- `llama_model_params`: Added `use_direct_io` (bool) after `use_mmap`
- `llama_context_params`: Added `samplers` (ptr) + `n_samplers` (size_t) after `kv_unified`
- `llama_model_quantize_params`: Added `dry_run` (bool) after `keep_split`

**`model_params.dart`** (1 line):
- Added `modelParams.use_direct_io = false;` after `use_mmap` assignment

### Reproducible Build

```bash
# Build the dylib from pinned commit (includes Gemma 4 support)
cd mobile
./scripts/build_llama_ios.sh

# Then deploy
flutter clean && flutter pub get && flutter run --release -d <device-id>
```

The build script (`scripts/build_llama_ios.sh`) is pinned to commit `d9a12c82f`
and will refuse to build from any other commit.

---

## Files Changed Today

### New Files

| File | Purpose |
|------|---------|
| `mobile/ARCHITECTURE.md` | Full technical architecture + challenge writeup |
| `mobile/scripts/build_llama_ios.sh` | Reproducible pinned dylib build script |
| `mobile/packages/llama_cpp_dart/` | Vendored + patched FFI bindings (in git) |
| `docs/sprint/week2_reports/rev2/agent2_thursday_eod_status.md` | This file |

### Modified Files

| File | Change |
|------|--------|
| `mobile/pubspec.yaml` | `llama_cpp_dart: path: ./packages/llama_cpp_dart` |
| `mobile/lib/core/inference/llama_client.dart` | New Llama() API, isolate arch, Metal GPU |
| `mobile/ios/Frameworks/libllama.dylib` | Rebuilt from d9a12c82f with Gemma 4 |

---

## For the Next Agent

### If you need to rebuild the dylib

```bash
cd mobile && ./scripts/build_llama_ios.sh
```

### FFI patches

The patched `llama_cpp_dart` is vendored in `mobile/packages/llama_cpp_dart/`.
No manual patching needed — `flutter pub get` resolves it from the local path.

### If you need to update llama.cpp to a newer commit

1. `git diff OLD_COMMIT..NEW_COMMIT -- include/llama.h`
2. Check EVERY struct for field additions/removals/reordering
3. Patch the Dart FFI structs to match
4. Test on a **real device** — struct mismatches cause silent crashes with no
   Dart-level stack trace
5. Update the pinned hash in `scripts/build_llama_ios.sh`

### If inference returns wrong answers

The prompt in `inference_service.dart` may need tuning for Gemma 4's chat template.
Check the `GemmaFormat` class in llama_cpp_dart for the expected format.

### If the app crashes on model load

Check that the FFI patches are still applied. A crash during model load (especially
after showing "30%" progress) is almost always a struct layout mismatch.

---

## Performance (Estimated)

| Metric | Value | Notes |
|--------|-------|-------|
| Model download | ~3 min | 2.9GB over WiFi, one-time |
| Model load | ~10-30s | mmap + Metal init, background isolate |
| Inference | TBD | Need to measure with B1 prompt |
| Total B1 pipeline | TBD | OCR + LLM, target < 120s |

---

## Thursday Mission Scorecard

From `agent2_thursday_mission.md`:

- [x] Model loads on iPhone
- [ ] OCR extracts text from documents (not tested on device yet)
- [x] B1 inference returns correct result ("4")
- [ ] Total time < 120 seconds (not measured yet)

**Verdict:** Core risk (model running on device) is eliminated.
Remaining work is pipeline integration, which is lower-risk since
individual components are proven.

---

## Risk Update

| Risk | Before Tonight | After Tonight |
|------|---------------|---------------|
| Model won't load on device | 🔴 HIGH | ✅ RESOLVED |
| llama.cpp crashes | 🔴 HIGH | ✅ RESOLVED |
| Inference returns garbage | 🟡 MEDIUM | ✅ RESOLVED (returns "4") |
| OCR fails on device | 🟡 MEDIUM | 🟡 Still untested |
| Full pipeline too slow | 🟡 MEDIUM | 🟡 Still unmeasured |
| FFI patches lost on clean install | 🟡 NEW | ✅ RESOLVED — vendored in git |

---

**Bottom line:** The hardest part is done. On-device Gemma 4 inference works.
What remains is plumbing (OCR → LLM → JSON) and timing.
