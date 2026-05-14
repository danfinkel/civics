## The Problem

In Massachusetts, 40.9% of SNAP participants with young children lose benefits due to administrative failures — not because they became ineligible, but because the paperwork process failed them [1]. The average family that fails recertification loses $600 in benefits, and one in four stays off the program for over a year [2]. The documents they needed existed and the deadline was published. The gap was knowing whether what they had was what was needed — before they found out it wasn't.

This interpretation gap recurs across government services. Boston Public Schools registration requires two residency proofs from different document categories. Many families don't know the rule until a registration specialist tells them, after they've already made the trip.

The documents involved — pay stubs, birth certificates, government notices, state IDs — are private and sensitive. Cloud-based document AI requires uploading them to a server. For residents already navigating difficult interactions with government institutions, that's a meaningful additional trust barrier. 

*[1] Kowalczyk et al., JAMA Network Open, 2022 — n=70,799 Massachusetts SNAP participants*
*[2] Homonoff & Somerville, American Economic Journal: Economic Policy, 2021*

---

## Our Solution
 
CivicLens is a mobile application that helps residents prepare document packets for government benefit processes. A resident photographs their government notice, uploads supporting documents, and receives a plain-language assessment of whether what they have satisfies what is being asked. CivicLens processes everything on-device. Documents never leave the phone.

We developed two modes for demonstration:

**Track A** addresses SNAP recertification: it reads a verification notice, identifies the required proof category and response deadline, and assesses whether uploaded documents satisfy the requirement. 

**Track B** addresses Boston Public Schools enrollment: it checks a document packet against the four registration requirements and flags common errors like the two-lease residency mistake.

---

## Architecture

The full evaluation pipeline was measured, demonstrated and refined running on a mobile device.

**Camera/File Picker → Image Pre-processor → Blur Gate → ML Kit OCR  → Gemma 4 E2B via llama.cpp + Metal GPU  → JSON Retry Parser → Results UI**

Zero server calls are made during analysis. The Flutter application targets iOS and Android. On-device inference uses llama.cpp compiled from commit `d9a12c82f` — the first commit with full Gemma 4 architecture support — integrated via a vendored Dart FFI bridge. Getting this to run required resolving a silent memory corruption issue caused by ABI mismatches between the Dart FFI bindings and the native llama.cpp dylib, patching four fields across two structs (`use_direct_io`, `samplers`, `n_samplers`, `dry_run`). This is documented in full at `mobile/ARCHITECTURE.md`.

A web demo using Gemma 4 E4B via the HF Inference API is deployed at `https://DanFinkel-civiclens.hf.space`.

---

## How We Used Gemma 4

**Multimodal JPEG input, not PDF.** Gemma 4 testing revealed that high-DPI PDF renders saturate the models visual token budget on layout elements before reaching the body text residents need extracted.  For this prototype all production inference runs on JPEG input. Images are pre-processed to a maximum of 2048px — sufficient for text resolution, small enough to avoid token saturation.

**Semantic prompt design.** We ran controlled experiments comparing generic field names (`key_date`, `document_type`) against semantically precise field names aligned to the SNAP recertification notice's information architecture (`response_deadline`, `requested_category`, `consequence`). Generic prompts were sensitive and led to misattributing fields. Semantic prompts helped Gemma 4 E2B report fields with the correct labels. Originally we wondered if we needed a larger model such as E4B -- this effect helped us feel confident about our choice to rely on E2B and to focus design efforts on prompt design for accurate on-device inference.

**Deterministic inference at temperature=0.0**. All production and evaluation inference runs use temperature=0.0. Early experimentation suggested that greedy decoding produces more consistent structured JSON output than sampling-based generation for this task — field values that appeared across multiple runs were stable rather than varying by phrasing or format on each call. This is intuitive for a structured extraction task where the answer is either in the document or it isn't, and creative variation in output is a liability rather than an asset.

**Deliberate token budget management.** On-device inference with a 4,096-token context window requires explicit budget management at every layer. We engineered four nested controls: (1) image downscaling to 2048px before OCR; (2) per-document OCR character caps (`noticeMax=3,500 chars`, `totalMax=5,800 chars`); (3) a hard prompt clamp at 8,000 characters with structure-preserving truncation; and (4) a 2,048-token output budget providing a safety net against repetition loops. When OCR text is truncated, a `[text truncated for model limits]` marker signals the model to respond with `uncertain` rather than hallucinate.

---

## Challenges and What We Learned

**We were wrong about blur.** We anticipated blur as the primary failure mode for phone photography and built a Laplacian variance blur detector. A real-world experiment — extracting 26 image quality attributes from 34 real iPhone photos and ranking by Cohen's d against pass/fail labels — revealed that Laplacian variance ranked 22nd out of 26 features. It is not a meaningful predictor of LLM extraction failure. A large promiment field like deadline was extracted at 100% accuracy across clean, degraded, and blurry inputs — the model's visual salience for high-contrast bordered boxes made it blur-invariant on the fields residents need most.

The real failure modes were scene clutter with a small document, severe rotation, anomalous frame dimensions from cropping, and document too small in frame. Each corresponds to a specific resident behavior — photographing from too far away, holding the phone at an angle, accidentally cropping the document — not camera optics. We replaced the Laplacian detector with a four-rule gate calibrated on real photos and validated against 100 synthetic test cases.

**Generic prompts can trigger misattribution and/or hallunication.** Our initial spike used PDF renders as synthetic test inputs — a choice that introduced a confound. High-DPI PDFs triggered wholesale template substitution, where the model ignored document content entirely and returned fabricated coherent output. When we identified this as a rendering artifact rather than a prompt failure, we switched to JPEG inputs matching the phone-photo deployment context. On JPEG inputs, generic prompts produced a subtler failure: date misattribution and schema-field mismatch. Semantic prompts eliminated both. The PDF finding shaped our input pipeline design — the app routes residents to photograph documents rather than scan them.

**The llama.cpp integration required low-level debugging.** Running Gemma 4 E2B on iOS via llama.cpp meant working at the FFI boundary between Dart and native C. Between December 2025 and April 2026, llama.cpp introduced breaking changes to three C structs that silently corrupted memory when the Dart bridge used stale field layouts. The failure mode was non-deterministic — correct results occasionally, crashes or garbage output otherwise. Identifying the root cause required diffing struct layouts across commits and patching the FFI bridge manually. The vendored patch is the primary reason the mobile app runs reliably on physical devices.

---

## Results

Across the full test corpus: 100% deadline extraction accuracy on JPEG inputs with semantic prompts; 0% genuine hallucination on expected document types with semantic prompts; 15.3 second total pipeline on iPhone 17; zero server calls during analysis; 100% document classification accuracy across 16 synthetic document types including Spanish-language variants. The four-rule image quality detector achieves high accuracy across 100 synthetic test cases with no false positives on blur variants — confirming that our detector correctly ignores the failure mode the Laplacian detector was designed to catch, while catching the actual failure modes it missed.

Known gaps: bottom-crop detection (key fields cropped from frame) remains undetected by the pre-processing gate; rotation detection is noisy in the 20–45° range. Both are active development work.

---

## Choices We Feel Good About

**Prompt design over model scaling.** We were able to reduce misattribution and hallucination by tuning our product design to jpg images and focusing our prompts. We did not need to switch to a larger model like E4B. For on-device AI in resource-constrained settings, the smaller the model the more accessible the application will be, especially to lower-income individuals who may not own the latest and greatest devices. 

**On-device as trust architecture, not preference.** Privacy-by-architecture — a system that cannot transmit documents because there is no transmission mechanism — is meaningfully different from privacy-by-policy for residents who have rational reasons to distrust data-collecting intermediaries. The on-device pipeline latency is the answer to the privacy requirement, not a workaround for it.

**Experiment-driven design.** Running controlled experiments before, during and after product development led to an informed architecture grounded in measured evidence. The image quality gate, the semantic prompts, the token budget design, the human-in-loop results UI — each came from a specific measured failure, not an assumption. 

---

**Built on Gemma4 · On device · Open Source**