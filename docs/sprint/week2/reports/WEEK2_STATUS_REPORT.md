# CivicLens — Week 2 Status Report

**Date:** Friday, April 10, 2026  
**Sprint:** Week 2 (April 7–11, 2026) — Track B MVP  
**Status:** ✅ **GREEN — On-Device Demo Validated**

---

## Executive Summary

Week 2 objective was to deliver **Track B (School Enrollment) end-to-end on mobile** with on-device inference. **Mission accomplished.**

The CivicLens app now runs **complete document analysis entirely on a physical iPhone** — OCR extracts text from 4 documents, Gemma 4 E2B (2.9GB model) reasons about BPS requirements, and returns structured JSON results. **No document data leaves the device.**

**Demo validation:** 4 documents analyzed in **15.3 seconds** with 4/4 requirements satisfied, correct document matching, and evidence-based reasoning.

---

## Deliverables Status

| Deliverable | Owner | Status | Evidence |
|-------------|-------|--------|----------|
| **On-device OCR** | Agent 2 | ✅ Complete | 391ms for 4 documents (ML Kit) |
| **On-device LLM inference** | Agent 2 | ✅ Complete | Gemma 4 E2B running on iPhone 16 via llama.cpp |
| **OCR → LLM → JSON pipeline** | Agent 2 | ✅ Complete | B1 scenario returns valid JSON |
| **Track B UI integration** | Agent 1 | ✅ Complete | Progress indicators, Packet Status screen |
| **Physical iPhone testing** | Agent 1 | ✅ Complete | 4/4 requirements satisfied on device |
| **HF Spaces deployment** | Agent 3 | ✅ Complete | https://DanFinkel-civiclens.hf.space |
| **Demo recording ready** | Agent 4 | 🟡 Ready | App on device, script prepared |

---

## Technical Achievements

### 1. On-Device Inference Proven (Agent 2)

**Breakthrough:** Gemma 4 E2B (2.9GB) runs inference on iPhone with Metal GPU acceleration.

**Performance:**
| Metric | Measured | Target | Status |
|--------|----------|--------|--------|
| OCR (4 docs) | 391ms | <30s | ✅ 77x under target |
| LLM inference | 11.9s | <90s | ✅ 7.5x under target |
| **Total pipeline** | **15.3s** | **<120s** | **✅ 8x under target** |

**Key technical wins:**
- Resolved FFI struct ABI mismatches between Dart and native llama.cpp
- Implemented Gemma chat template for correct prompt formatting
- Vendored llama_cpp_dart with patches for reproducible builds
- Model loads in background isolate with Metal GPU offloading

### 2. UI Integration Complete (Agent 1)

**Shipped:**
- Progress indicators showing OCR phase → LLM phase with percentage
- Packet Status screen with requirement rows, confidence signals, evidence
- Blur detection workflow fixed ("Use anyway" keeps photo)
- Response parser hardened for real model output (handles JSON edge cases)
- Splash screen aligned to Stitch design system

**Validation:**
- Unit tests: blur detection, image pipeline, response parser
- Device testing: Full Track B flow with real captures, 4/4 satisfied result

### 3. Infrastructure Ready (Agent 3)

**HF Spaces:** Cloud fallback API deployed and tested
- URL: https://DanFinkel-civiclens.hf.space
- Endpoints: /health, /analyze, /analyze/form
- CORS enabled for mobile app access

**Role:** Backup demo option (not used — on-device is primary)

### 4. Demo Preparation (Agent 4)

**Ready:**
- 3-minute video script with timing breakdown
- B1 and B4 scenario walkthroughs documented
- Recording setup guide for iOS/Android
- Presentation slide specifications

**Next:** Screen recording session with working app

---

## Privacy-First Architecture Validated

```
iPhone (on-device, no network)
┌─────────────────────────────────────────┐
│  CivicLens App                          │
│  ┌──────────┐   ┌────────────────────┐  │
│  │ ML Kit   │──▶│ llama.cpp          │  │
│  │ OCR      │   │ Gemma 4 E2B        │  │
│  │ (391ms)  │   │ Metal GPU          │  │
│  └──────────┘   │ (11.9s)            │  │
│                 └────────────────────┘  │
│                          │              │
│                     JSON Results        │
└─────────────────────────────────────────┘
```

**Privacy guarantees:**
- ✅ OCR: Google ML Kit (on-device, no cloud)
- ✅ LLM: llama.cpp with local Gemma model (no API calls)
- ✅ Documents: Never leave the device
- ✅ Network: Only used for initial model download (one-time)

---

## Risks Resolved

| Risk (Thursday) | Status (Friday) | Resolution |
|-----------------|-----------------|------------|
| Model won't load on device | ✅ Resolved | FFI struct alignment fixed |
| Inference returns garbage | ✅ Resolved | Gemma chat template implemented |
| OCR fails on device | ✅ Resolved | ML Kit working (391ms for 4 docs) |
| Pipeline too slow (>120s) | ✅ Resolved | 15.3s total (8x under target) |
| JSON parsing unreliable | ✅ Resolved | Parser hardened for real output |
| UI integration breaks | ✅ Resolved | Progress callbacks wired, tested |

**No remaining blockers.**

---

## Week 2 Exit Criteria

| Criteria | Required | Actual | Status |
|----------|----------|--------|--------|
| Track B end-to-end on mobile | Yes | 4/4 satisfied, 15.3s | ✅ Met |
| On-device inference | Yes | OCR + LLM on iPhone | ✅ Met |
| Physical device tested | Yes | iPhone 16 validated | ✅ Met |
| Demo ready for recording | Yes | App on device, script ready | ✅ Met |
| < 120s total time | Target | 15.3s | ✅ Exceeded |

**Verdict: Week 2 objectives achieved.**

---

## Next Steps (Week 3)

| Priority | Task | Owner |
|----------|------|-------|
| P0 | Screen recording captured | Agent 4 |
| P0 | Video editing (3 min final) | Agent 4 |
| P1 | Track A (SNAP) integration | Agent 1 + 2 |
| P1 | B4 scenario (duplicate warning) | Agent 1 |
| P2 | Android build | Agent 2 |
| P2 | Performance optimizations | Agent 2 |
| P3 | Kaggle writeup draft | All |

---

## Budget / Resources

| Resource | Used | Notes |
|----------|------|-------|
| Agent time | 4 agents × 5 days | Within sprint plan |
| HF Spaces | CPU tier | Sufficient for fallback API |
| Compute | Local builds | No cloud costs for inference |
| External deps | llama.cpp, ML Kit | Open source, no licensing issues |

---

## Stakeholder Communication

**For investors / partners:**
- Privacy-first architecture proven on real hardware
- 15-second analysis for 4 documents (competitive with cloud APIs)
- Demo video ready by end of Week 3

**For technical review:**
- Full architecture documentation in `mobile/ARCHITECTURE.md`
- Reproducible build scripts vendored in repo
- FFI patches documented for future maintenance

**For program management:**
- Week 2 scope delivered on schedule
- No scope creep, no blockers
- Team velocity sustainable for Week 3

---

## Sign-Off

| Agent | Signature | Status |
|-------|-----------|--------|
| Agent 1 (Mobile) | ✅ | Track B UI integrated, device tested |
| Agent 2 (Inference) | ✅ | On-device pipeline proven, 15.3s |
| Agent 3 (Web) | ✅ | HF Spaces deployed, backup ready |
| Agent 4 (Design/Video) | ✅ | Script ready, awaiting recording |

**Overall Week 2 Status: GREEN — Ready for Week 3**

---

**Report prepared:** April 10, 2026  
**Next update:** Upon completion of demo recording (Week 3)
