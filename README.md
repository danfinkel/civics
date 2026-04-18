<div align="center">

<img src="mobile/assets/branding/app_icon.png" alt="CivicLens" width="160" />

# CivicLens

**The check you do at home, before you go.**

Privacy-first civic document intelligence — powered by Gemma 4, running entirely on your phone.

[![Gemma 4 Good Hackathon](https://img.shields.io/badge/Gemma_4_Good-Hackathon_2026-5DB8A0?style=flat-square)](https://www.kaggle.com/competitions/gemma-4-good)
[![License: MIT](https://img.shields.io/badge/License-MIT-002444?style=flat-square)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-iOS%20%7C%20Android%20%7C%20Web-002444?style=flat-square)]()
[![On-device](https://img.shields.io/badge/Inference-on--device-5DB8A0?style=flat-square)]()

[Live web demo](https://DanFinkel-civiclens.hf.space) · [Vision doc](docs/planning/overview/civiclens_vision.md) · [Build plan](docs/planning/overview/civiclens_buildplan.md) · [Feasibility spike](spike/) · [Architecture](mobile/ARCHITECTURE.md)

</div>

---

## What it does

Every year, millions of Americans interact with government benefit systems that require them to submit documentary proof of who they are, where they live, and how much they earn. SNAP recertification. School enrollment. Housing assistance. Medicaid renewals. The documents are not hard to find. The instructions are not impossible to read. But the combination of unfamiliar bureaucratic language, tight deadlines, and multiple simultaneous requirements creates real failure rates for people who cannot afford to fail.

CivicLens is a mobile app that helps a resident answer one question before they leave the house: **"Do I have the right documents for what the agency is asking for?"**

It ships with two flows:

- **SNAP Document Assistant (Track A).** Point the camera at a DTA verification notice and the documents you have at home. CivicLens reads the notice, identifies which proof categories are being requested and the deadline, checks each uploaded document against those categories, and produces a plain-language action summary — what's covered, what's missing, and what to do next.
- **BPS Enrollment Assistant (Track B).** Point the camera at the documents you plan to bring to Boston Public Schools registration. CivicLens checks each one against the four BPS requirements (proof of age, two residency proofs from different categories, immunization record, grade indicator), flags the "two-category" residency rule, and tells the family what to bring and what to replace.

In both modes the model assists — it never auto-approves. Every output ships with a confidence level, and anything ambiguous is flagged for human review.

---

## Why it has to be on-device

The documents involved — pay stubs, birth certificates, state IDs, government notices — are among the most sensitive a person carries. Existing tools that require uploading these to a server ask residents to trust a third party with information they have good reason to protect. Privacy here is a constraint, not a feature.

Gemma 4's E2B variant makes this possible. A 4-billion-parameter multimodal model that reads a phone photo of a pay stub and returns structured field extraction — running entirely on-device, with zero network requests during analysis — is a qualitatively new capability.

<div align="center">

| `391ms` | `11.9s` | `15.3s` | `0` |
|:---:|:---:|:---:|:---:|
| OCR | AI inference | total pipeline | server calls during analysis |

*Measured on iPhone 14 Pro, 4-document Track B packet.*

</div>

**Privacy by architecture, not policy:**

- OCR runs locally via Apple ML Kit. No cloud call.
- AI inference runs locally via Gemma 4 E2B on `llama.cpp` with Metal GPU acceleration. No API key, no server, no third party.
- The network is used exactly once — for the 2.9 GB one-time model download over Wi-Fi. Every analysis after that is fully offline.
- Documents are processed in memory and discarded. Nothing is written to disk, stored, or transmitted.

---

## Evidence-driven development

CivicLens was not designed by assumption. Before writing a line of product code we ran a structured five-day feasibility spike, testing Gemma 4 E4B against 16 synthetic civic documents (pay stubs, leases, DTA notices, birth certificates, immunization records, utility bills, Spanish-language variants, and more) in both clean PDF and degraded phone-photo form. Every experiment was measured against formal pass/fail thresholds.

**What works reliably** (and shapes what the product does):

- **100%** document type classification accuracy across 16 document types on degraded phone photos, including Spanish-language documents.
- **85.9%** accuracy on BPS requirement mapping; **66.7%** on SNAP proof categories.
- **100%** JSON parseability with a retry wrapper.
- **Zero** false positives on critical safety checks — award letters were never accepted as income proof, informal notes never accepted as residency proof.

**What does not work reliably** (and shapes what the product refuses to do):

- Precise field extraction from complex tabular layouts (pay stubs with adjacent current/YTD columns) showed ~40% hallucination on specific numeric fields. → The product pre-fills and asks the resident to confirm, rather than treating model output as ground truth.
- The model does not reliably abstain on blurry images — it generates plausible-sounding content with high confidence. → Blur detection runs *before* any image reaches the model (Laplacian variance, tuned on real phone photos).
- Missing-item detection recall is 50–67% — the model is optimistically biased toward "likely satisfies with caveats." → Human-in-the-loop is a hard product requirement, and the action summary does the heavy lifting of telling residents what to double-check.

The full spike methodology, experiment logs, scoring tables, and decision memos live in [`spike/`](spike/). They are the evidence base for every architectural decision in the build.

---

## Architecture at a glance

```
Phone camera / file picker
        ↓
Image pre-processor       (resize ≤1024px, strip EXIF, normalize rotation)
        ↓
Blur detector             (Laplacian variance — retake flow if below threshold)
        ↓
Apple ML Kit OCR          (on-device, ~400ms)
        ↓
Gemma 4 E2B via llama.cpp (on-device, Metal GPU, ~12s for 4 documents)
        ↓
JSON parser + retry       (recovers bare key:value output)
        ↓
Confidence triage         (high / medium / low / uncertain)
        ↓
Results UI + action summary
```

Key decisions and the spike findings that drove them are documented in [`mobile/ARCHITECTURE.md`](mobile/ARCHITECTURE.md), along with the three non-obvious native-bridge challenges we debugged to ship on-device Gemma 4 (FFI struct drift across llama.cpp commits; Gemma 4 architecture support landing post-package-release; C struct ABI breaks causing silent stack corruption). If you are building anything similar, those notes will save you a week.

---

## Repository structure

```
civics/
├── mobile/                  Flutter app (iOS + Android) — primary deliverable
│   ├── lib/
│   │   ├── core/            Imaging, inference, OCR, models
│   │   ├── features/        Track A (SNAP), Track B (BPS), onboarding
│   │   └── shared/          Design system, widgets, utilities
│   ├── packages/
│   │   └── llama_cpp_dart/  Vendored + patched FFI bindings (see ARCHITECTURE.md)
│   ├── scripts/             Reproducible libllama.dylib build
│   ├── ARCHITECTURE.md      On-device inference stack + debugging war stories
│   └── PERFORMANCE.md       Device benchmarks and optimization notes
│
├── web_demo/                Gradio demo on Hugging Face Spaces (Gemma 4 E4B)
│
├── spike/                   Five-day feasibility study — the evidence base
│   ├── artifacts/           16 synthetic documents × {clean, degraded, blurry}
│   └── scripts/             Experiment runners, scoring, OCR tests
│
├── research/                Week-3 evaluation harness and prompt studies
│
├── docs/
│   ├── planning/overview/   Vision doc, 4-week build plan
│   ├── design/              CivicLens Institutional design system, Stitch specs
│   ├── sprint/              Per-week sprint notes
│   ├── video/               3-minute submission video script + slides
│   └── presentation/        Closing card, privacy card (HTML)
│
└── LICENSE                  MIT
```

---

## Running it

### Mobile app (iOS)

The mobile app runs Gemma 4 E2B on-device via `llama.cpp` with Metal GPU acceleration. It requires a physical iPhone 13 or newer — the `mediapipe_genai` / `llama.cpp` stack does not run in the simulator.

```bash
cd mobile
flutter pub get
# Build the native llama.cpp dylib (pinned commit d9a12c82f, Gemma 4–capable):
./scripts/build_llama_ios.sh
# Open in Xcode, sign with your developer account, Profile/Release to device:
open ios/Runner.xcworkspace
```

On first launch the app downloads the 2.9 GB Gemma 4 E2B GGUF over Wi-Fi. After that, every analysis is fully offline.

See [`mobile/scripts/README.md`](mobile/scripts/README.md) for the device-install + model-push workflow.

### Web demo (Hugging Face Spaces)

The web demo uses Gemma 4 E4B via Ollama for higher accuracy on degraded images. It mirrors the mobile flows for judges and reviewers who don't have an iPhone handy.

```bash
cd web_demo
ollama pull gemma4:e4b
pip install -r requirements.txt
python app.py          # http://localhost:7860
```

Live instance: **[DanFinkel-civiclens.hf.space](https://DanFinkel-civiclens.hf.space)**.

### Reproducing the spike

```bash
cd spike
uv sync                                     # or: pip install -e ..
python scripts/track_a_mobile_local.py      # runs Track A end-to-end
```

All synthetic documents and gold answers are checked in under [`spike/artifacts/`](spike/artifacts/).

---

## Design principles

These govern every product decision in the build:

1. **Privacy is a constraint, not a feature.** On-device inference is required. Any architectural decision that routes document content off the device needs explicit justification *and* explicit user consent.
2. **The model assists; the resident decides.** No output is presented as a final determination. Every assessment carries a confidence level. The action summary tells residents what to do, not what the agency will accept.
3. **Honest about limitations.** Uncertainty is surfaced, not hidden. An illegible document is flagged. An assessment with caveats shows its caveats. The product is more trustworthy for being honest about what it does not know.
4. **Plain language throughout.** The action summary is written for a resident who may be reading it under stress, possibly in their second language, on a small phone screen.
5. **Evidence-driven.** Product decisions are grounded in spike findings. When a new question about model capability comes up, the right response is to measure it, not assume it.

Design tokens and components are documented in [`docs/design/civiclens_design_specs.md`](docs/design/civiclens_design_specs.md).

---

## Known limitations

We hold ourselves to the same honesty bar we hold the model to:

- **Precise numeric extraction is unreliable** on complex tabular pay stubs. The product surfaces a pre-filled value and asks the resident to confirm — it does not claim to have read the number correctly.
- **The model cannot self-report illegibility.** Blur detection happens *before* the model sees the image. If a photo gets past blur detection but is still marginal, the output may look confident and be wrong. Confidence flags and the action summary are the backstop.
- **Missing-item recall is 50–67%.** The model is optimistically biased. The product never claims a packet is complete — only that "these documents appear to satisfy these requirements." Final determination is always made by the agency.
- **Coverage is deliberately narrow.** We built for Massachusetts SNAP (DTA) and Boston Public Schools enrollment because those are the processes we studied. Extending to other agencies requires per-agency requirements modeling, not just prompt changes.

Full limitations and the evidence behind them: see [`spike/`](spike/) and [`docs/planning/overview/civiclens_vision.md`](docs/planning/overview/civiclens_vision.md).

---

## Built with

- **[Gemma 4 E2B](https://ai.google.dev/gemma)** — on-device multimodal inference
- **[Gemma 4 E4B](https://ai.google.dev/gemma)** — web demo, higher-accuracy cloud variant
- **[llama.cpp](https://github.com/ggerganov/llama.cpp)** (pinned to `d9a12c82f`) — native inference engine
- **[Flutter](https://flutter.dev)** — cross-platform mobile UI
- **[Apple ML Kit](https://developers.google.com/ml-kit)** — on-device OCR
- **[Gradio](https://gradio.app)** + **[Hugging Face Spaces](https://huggingface.co/spaces)** — web demo
- **[Ollama](https://ollama.ai)** — E4B inference for the web demo

---

## License

[MIT](LICENSE) © 2026 Dan Finkel.

Built for the **[Gemma 4 Good Hackathon](https://www.kaggle.com/competitions/gemma-4-good)** (Kaggle, 2026) — Digital Equity & Inclusivity / Safety & Trust track.
