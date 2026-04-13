# CivicLens — Week 3 Status: Track A “notice-first” preview (first test)

**Report for:** Project management  
**Sprint:** Week 3 (April 2026)  
**Scope:** Lightweight background read of the government notice after upload so Step 2 can show **context** (what the notice seems to ask for, deadline when present) **without blocking** supporting-document uploads.  
**Overall status:** **Green** — shipped in `mobile/` and covered by parser tests. **Yellow** — human QA on real notices/devices still recommended before calling it “done” for launch narrative.

---

## Executive summary

We landed a **minimum-friction “notice-first” hint** on Track A (SNAP document check):

- As soon as the resident uploads their **government notice**, the app kicks off a **background** pass: **OCR (notice only)** → **short on-device LLM prompt** → small JSON (`requested_categories`, `deadline`, `hint`).
- **Step 2 does not wait** for that pass: users can add supporting photos immediately while a **“Reading your notice…”** state shows under **Your Documents**.
- **Failures degrade quietly**: neutral guidance copy replaces the card if OCR/LLM/parse fails or the model returns no usable fields — **no hard block** on the flow.

**PM takeaway:** This is a solid **first test** of “smart context before full analysis.” It improves orientation without changing the primary CTA (**Check my documents**) or the full Track A pipeline. Next validation is **real-device QA** on varied notice quality and memory behavior now that the model may load **when the notice is set**, not only on the final check.

---

## What shipped (this increment)

| Area | Location | Purpose |
|------|----------|---------|
| Preview model | `mobile/lib/core/models/track_a_notice_preview.dart` | DTO for categories, deadline, hint; `hasAnySignal` for UI. |
| Prompt | `mobile/lib/core/inference/prompt_templates.dart` — `trackANoticePreviewOnly()` | Tight JSON-only instruction for a **small** completion. |
| Parser | `mobile/lib/core/inference/response_parser.dart` — `parseTrackANoticePreview()` | Reuses existing Gemma JSON repair/retry patterns where applicable. |
| Inference API | `mobile/lib/core/inference/inference_service.dart` — `analyzeTrackANoticePreview()` | Notice-only OCR, clamped prompt, **~380 max tokens**; optional diagnostics via `kInferenceDiagnostics`. |
| Module export | `mobile/lib/core/inference/inference.dart` | Exports `TrackANoticePreview` for consumers. |
| Controller | `mobile/lib/features/track_a/track_a_controller.dart` — `prefetchNoticePreview()` | Initializes inference if needed; returns `null` on failure (quiet degrade). |
| UI | `mobile/lib/features/track_a/track_a_screen.dart` | `_scheduleNoticePreview()` after capture; hint card under **Your Documents**; stale results dropped by notice `id`; cleared on retake / clear / start over. |
| Tests | `mobile/test/response_parser_test.dart` | Parser coverage for flat JSON + markdown fence. |

---

## Product behavior (resident-facing)

1. **Step 1 → Step 2:** After notice upload, user sees the notice thumbnail and supporting slots as today.
2. **Hint card:** Shows a spinner + “Reading your notice…” while the preview runs; then either **categories (chips)**, **deadline**, **short hint**, or **generic** copy if nothing reliable was extracted.
3. **Blur flow:** Retake clears the notice and cancels preview UI state; “Use anyway” keeps the same notice id so an in-flight preview remains valid.
4. **Full analysis unchanged:** **Check my documents** still runs the existing Track A OCR + LLM path over notice + supporting docs.

---

## Tradeoffs and risks

| Topic | Note |
|------|------|
| **Earlier model load** | Preview may trigger **Llama init** when the first notice is saved (not only on final analyze). Improves responsiveness for the hint; watch **RAM / jetsam** on low-end devices in QA. |
| **OCR / model variance** | Bad photos or garbled JSON still yield the **neutral** card — by design, not a bug. |
| **Not legal advice** | Copy and model output remain **informational**; full disclaimer posture matches existing Track A results. |

---

## Suggested PM / QA follow-ups

| Priority | Action |
|----------|--------|
| **P1** | Smoke on **physical device**: notice-only upload → confirm hint appears, supporting uploads still work mid-load, retake/clear behavior. |
| **P2** | Spot-check **blurry** and **multi-page** notices; confirm neutral path is acceptable. |
| **P3** | If thermal/memory issues appear, consider **deferring** preview start until post-blur dialog or first frame after Step 2 (engineering tweak only). |

---

## Appendix — run tests locally

```bash
cd mobile && flutter test test/response_parser_test.dart
```

---

## Related docs (optional)

- Week 3 human QA checklist: `docs/sprint/week3_human_qa.md` (update if you want an explicit row for “notice preview card”).
