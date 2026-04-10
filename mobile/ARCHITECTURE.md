# CivicLens Mobile: On-Device Inference Architecture

## Overview

CivicLens runs Gemma 4 E2B (2.9GB, Q4_K_M quantization) on-device via `llama.cpp`,
bridged to Flutter/Dart through the `llama_cpp_dart` package's FFI bindings. The model
performs document analysis for the B1 scenario: OCR text from 4 documents is sent to the
LLM, which returns a satisfaction count.

## Stack

```
Flutter UI (Dart)
    ↓
llama_cpp_dart 0.2.2 (vendored in mobile/packages/, patched FFI bindings)
    ↓
libllama.dylib (custom-built, single combined dynamic library)
    ↓
llama.cpp (C/C++ inference engine, commit d9a12c82f)
    ↓
Metal GPU (Apple Neural Engine / GPU on iPhone)
```

## The llama.cpp Native Library

We ship a **single self-contained `libllama.dylib`** that combines all llama.cpp
components into one dynamic library:

- `libllama.a` — core LLM inference
- `libggml-base.a` — tensor operations
- `libggml-cpu.a` — CPU compute backend
- `libggml-metal.a` — Metal GPU backend (Apple Silicon)
- `libggml-blas.a` — BLAS acceleration
- `libggml.a` — backend registry
- `libmtmd.a` — multimodal support (required by llama_cpp_dart 0.2.x)

Metal shaders are embedded in the dylib via `-sectcreate __DATA __ggml_metallib`.

**Build script:** `scripts/build_llama_ios.sh`

## Critical: Pinned Commit Hash

```
llama.cpp commit: d9a12c82f0c81eea3ba54be5fb5250161993c450
Date: 2026-04-08
Tag: vocab: remove </s> eog token if gemma4 (#21492)
```

**DO NOT update this commit without also updating the FFI bindings.**

The `llama_cpp_dart` 0.2.2 package has auto-generated Dart FFI struct definitions that
must exactly match the C struct layouts in `llama.h`. Changing the llama.cpp commit will
likely change struct layouts and cause memory corruption / crashes. See "Challenges
Overcome" below for the full story.

## Isolate Architecture

Model loading and inference run in a **background Dart isolate** to avoid blocking the
main thread. This is critical on iOS because:

1. The iOS watchdog kills apps that block the main thread for >20 seconds
2. Loading a 2.9GB model via mmap takes 10-30 seconds
3. Individual inference calls can take 5-60 seconds

```
Main Isolate (UI thread)        Background Isolate
    │                                │
    ├─ spawn isolate ───────────────→│
    │                                ├─ Llama.libraryPath = ...
    │                                ├─ Llama(modelPath, ...)
    │                                │  (loads 2.9GB model)
    │←── {status: 'ready', port} ────┤
    │                                │
    ├─── {cmd: 'chat', prompt} ─────→│
    │                                ├─ llama.setPrompt(prompt)
    │                                ├─ llama.getNext() loop
    │←── {result: '4'} ─────────────┤
```

## Model Parameters

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| `nGpuLayers` | 99 | Offload all layers to Metal GPU |
| `useMemorymap` | true | mmap the 2.9GB file instead of reading into RAM |
| `useMemoryLock` | false | Don't pin in RAM (iOS manages memory pressure) |
| `nCtx` | 2048 | Sufficient context for document analysis |
| `nBatch` | 512 | Batch size for prompt processing |
| `greedy` | true | Deterministic sampling for consistent results |

## Model Delivery

The 2.9GB model is **not bundled in the app binary**. It's downloaded over WiFi from a
local HTTP server on first launch. This keeps the app binary at ~68MB.

The `Info.plist` includes `NSAppTransportSecurity` exceptions for local networking.

---

## Challenges Overcome

These are the three critical issues we debugged to get Gemma 4 E2B running on-device.
Each one caused the app to crash or fail silently, with no useful error messages.

### Challenge 1: llama.cpp API Version Mismatch (Memory Corruption)

**Symptom:** App crashed immediately after showing "30% loading" status. No error
message — just a hard crash to the home screen.

**Root cause:** The `llama_cpp_dart` package version 0.0.9 (resolved from `^0.0.5` in
pubspec.yaml) contained FFI bindings generated from llama.cpp commit `42ae10bb`
(mid-2025). But our `libllama.dylib` was built from the latest llama.cpp HEAD. Between
those two commits, the C struct layouts (`llama_model_params`, `llama_context_params`,
etc.) changed — fields were added, reordered, and resized.

When Dart FFI writes a struct field at offset N (based on the old layout) but the C
library reads it at a different offset (new layout), you get **silent memory corruption**.
The model loading function received garbage values for its parameters, causing a segfault
deep inside llama.cpp with no recoverable error.

**Fix:** Upgraded `llama_cpp_dart` from `0.0.9` to `0.2.2`, which uses bindings generated
from a much newer llama.cpp commit (`4ffc47cb`). This eliminated the struct layout
mismatch for the core API.

### Challenge 2: Missing Gemma 4 Architecture Support

**Symptom:** After fixing Challenge 1, the app no longer crashed — but showed "Failed to
initialize model. Could not load model at .../gemma-4-E2B-it-Q4_K_M.gguf".

**Root cause:** The `llama_cpp_dart` 0.2.2 package was built against llama.cpp commit
`4ffc47cb` from **December 28, 2025**. Gemma 4 architecture support was added to
llama.cpp on **April 2, 2026** — 3 months later. The GGUF file declares architecture
`gemma4`, which the old llama.cpp simply doesn't recognize. It returns `nullptr` from
`llama_load_model_from_file()`.

**Fix:** Rebuilt `libllama.dylib` from commit `d9a12c82f` (April 8, 2026) which includes
all Gemma 4 architecture support and fixes.

### Challenge 3: C Struct ABI Break in FFI Bridge (The Hard One)

**Symptom:** After rebuilding with the Gemma 4-capable llama.cpp, the app went back to
**hard crashing** — worse than Challenge 2 where it at least showed an error.

**Root cause:** Between commit `4ffc47cb` (Dec 2025, what the Dart FFI bindings expect)
and commit `d9a12c82f` (Apr 2026, what the dylib was built from), three C structs gained
new fields:

**`llama_model_params`** — added `use_direct_io` (bool) between `use_mmap` and
`use_mlock`:
```c
// Old layout (Dec 2025):
bool vocab_only;
bool use_mmap;
bool use_mlock;      // ← Dart FFI writes use_mlock here
bool check_tensors;

// New layout (Apr 2026):
bool vocab_only;
bool use_mmap;
bool use_direct_io;  // ← NEW: Dart FFI writes use_mlock here (WRONG!)
bool use_mlock;      // ← Dart FFI writes check_tensors here (WRONG!)
bool check_tensors;
```

**`llama_context_params`** — added `samplers` (pointer) and `n_samplers` (size_t) at
the end of the struct. This changes the struct's total size. When
`llama_context_default_params()` returns the struct by value, the C function writes more
bytes than the Dart FFI expects, causing a **stack buffer overflow**.

**`llama_model_quantize_params`** — added `dry_run` (bool) between `keep_split` and
`imatrix`.

**Fix:** Surgically patched the auto-generated Dart FFI struct definitions in
`llama_cpp_dart-0.2.2/lib/src/llama_cpp.dart` (21,545 lines) to add the missing fields
in the correct positions:

1. Added `@ffi.Bool() external bool use_direct_io;` after `use_mmap` in
   `llama_model_params`
2. Added `external ffi.Pointer<ffi.Void> samplers;` and
   `@ffi.Size() external int n_samplers;` at end of `llama_context_params`
3. Added `@ffi.Bool() external bool dry_run;` after `keep_split` in
   `llama_model_quantize_params`
4. Updated `model_params.dart` to set `use_direct_io = false` explicitly

After these 4 field additions across 2 files, the Dart FFI struct layouts matched the new
C struct layouts exactly, and inference succeeded on the first try.

### Key Lesson

When bridging native C libraries through FFI, **the generated bindings are a snapshot of
the C header at generation time**. Any struct layout change — even adding a single bool —
shifts all subsequent field offsets and causes silent memory corruption. The crash
manifests deep in the native code with no Dart-level stack trace, making it extremely
difficult to diagnose.

The solution is to **pin the native library commit** and treat the FFI bindings + native
library as an atomic pair. Never update one without the other.

### Vendored Package

To make the FFI patches reproducible, `llama_cpp_dart` is **vendored** into the repo at
`mobile/packages/llama_cpp_dart/` with the struct patches committed to git. The
`pubspec.yaml` uses a `path:` dependency:

```yaml
llama_cpp_dart:
  path: ./packages/llama_cpp_dart
```

This means:
- `flutter pub get` from a clean clone works without manual patching
- CI environments get the correct FFI bindings automatically
- The patches are version-controlled and code-reviewable

---

## File Map

```
mobile/
├── ios/
│   └── Frameworks/
│       └── libllama.dylib          # Custom-built, Gemma 4-capable
├── lib/
│   └── core/
│       └── inference/
│           ├── llama_client.dart    # Isolate-based llama.cpp client
│           ├── inference.dart       # Inference abstraction layer
│           ├── inference_service.dart
│           └── ocr_service.dart     # Google ML Kit OCR
├── packages/
│   └── llama_cpp_dart/             # Vendored + patched FFI bindings
│       └── lib/src/
│           ├── llama_cpp.dart       # Patched: use_direct_io, samplers, dry_run
│           └── model_params.dart    # Patched: use_direct_io = false
├── scripts/
│   └── build_llama_ios.sh          # Reproducible dylib build (pinned commit)
└── ARCHITECTURE.md                 # This file
```
