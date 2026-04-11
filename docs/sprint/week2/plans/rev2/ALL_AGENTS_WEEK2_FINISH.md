# Week 2 Finish Plan: On-Device or Bust

**Date:** April 7, 2026  
**Goal:** On-device inference working on physical iPhone by Friday  
**Non-negotiable:** Documents never leave the phone

---

## The Reality

Agent 2's llama.cpp PoC is text-only. CivicLens needs multimodal (images + text).

**Two paths forward:**

| Path | Effort | Confidence | Decision |
|------|--------|------------|----------|
| A: Full vision in llama.cpp | 2-3 days | Medium | Too risky for Friday |
| B: OCR + text inference | 1 day | High | **Selected** |

**Path B: OCR Pipeline**
```
Document Image → OCR (on-device) → Extracted Text → llama.cpp → JSON Results
```

This keeps everything on-device. Privacy preserved.

---

## Agent 2: Critical Path

### Today (EOD Deadline)

**Must deliver by end of day:**

1. **Build llama.cpp for iOS** — working `libllama.dylib`
2. **Convert Gemma E2B to GGUF** — `gemma-4-2b-it-e2b.gguf` ready
3. **Test basic inference** — "Hello world" response from model

**If not done by EOD:** Escalate immediately with specific blocker.

### Tomorrow

1. **Integrate OCR** — Use `google_mlkit_text_recognition` (on-device)
2. **Build pipeline:**
   ```dart
   Future<String> extractTextFromImage(Uint8List image) async {
     final inputImage = InputImage.fromBytes(bytes: image);
     final textRecognizer = TextRecognizer();
     final recognizedText = await textRecognizer.processImage(inputImage);
     return recognizedText.text;
   }
   ```
3. **Prompt engineering:** Feed OCR text to Gemma instead of raw image

### Wednesday

1. **End-to-end test** — Image → OCR → llama.cpp → Results
2. **Performance tuning** — Target <60 seconds total
3. **Hand off to Agent 1**

### Thursday-Friday

1. **Joint debugging** with Agent 1
2. **Physical device testing**
3. **Demo polish**

---

## Agent 1: Parallel Track

### Today/Tomorrow

**While Agent 2 builds:**

1. **Integrate OCR library**
   ```yaml
   dependencies:
     google_mlkit_text_recognition: ^0.13.0
   ```

2. **Update Track B flow:**
   ```dart
   // New flow
   1. User captures document
   2. Run OCR on-device → extracted text
   3. Send text (not image) to llama.cpp
   4. Display results
   ```

3. **UI updates:**
   - Show "Reading document..." during OCR
   - Then "Analyzing..." during inference
   - Progress indicators for both steps

### Wednesday

1. **Integrate Agent 2's llama.cpp build**
2. **Test end-to-end**

### Thursday-Friday

1. **B1-B8 scenario testing**
2. **Physical iPhone testing**
3. **Demo prep**

---

## Agent 3: Support Role

**HF Spaces is backup only.** Primary focus: support Agents 1-2.

### Tasks:

1. **Test OCR accuracy** — Run spike documents through ML Kit OCR
2. **Document results** — Which documents OCR well?
3. **Prompt tuning** — Help craft text-only prompts if needed

**OCR Test Results Needed:**

| Document | OCR Quality | Notes |
|----------|-------------|-------|
| D12 (birth cert) | ? | |
| D05 (lease) | ? | |
| D06 (utility) | ? | |
| D13 (immunization) | ? | |

---

## Agent 4: Stand By

**Recording delayed to Thursday PM / Friday AM.**

Need working on-device demo before recording.

---

## Daily Standup Format

Each agent reports:

1. **What I completed yesterday**
2. **What I'm doing today**
3. **Blockers** (if any, escalate immediately)

**No blockers allowed to sit overnight.**

---

## Success Criteria (Revised)

- [ ] llama.cpp runs on physical iPhone
- [ ] OCR extracts text from documents on-device
- [ ] Gemma analyzes OCR text, returns JSON
- [ ] B1 scenario passes end-to-end
- [ ] Documents never leave the device

**Failure mode:** If on-device truly impossible, we fail loudly and honestly — not quietly with cloud fallback.

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| llama.cpp build fails | Agent 2 escalates immediately, we reassess |
| OCR quality poor | Test today — if unusable, pivot to document-specific OCR tuning |
| Too slow (>60s) | Optimize: smaller model, quantization, or accept slower for demo |
| Doesn't fit in memory | Use Q4 quantization, target 2GB model size |

---

## Decision Log

**April 7, 2026:** Selected OCR + text inference over full vision. Trade-off: loses some layout/structure information, but keeps privacy promise.

**If this fails:** We have a genuine technical blocker to document, not a workaround.
