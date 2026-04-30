# W2 Warm-Up Findings: Blind Document Type Classification

## What we tested

Whether `gemma4:e2b` can assign a document-type label **without** being told the candidate set beyond the fixed enum, using the W2 classification prompt. Inputs: D01 (government notice) and D03 (pay stub), each as clean PDF and degraded JPG. **5 runs per file, temperature=0.** Raw logs: `w2_classify_results.json`.

## What passed

- **Label accuracy:** **20/20** runs returned the expected label — `government_notice` for D01 and `pay_stub` for D03 on both clean and degraded images.
- **Stability at temp=0:** Within each file, the classification string was identical across all five runs (no label drift).
- **Structured output:** **0** JSON parse failures across 20 runs; responses were parseable objects with `classification`, `confidence`, and `evidence`.
- **D03 evidence on clean PDF:** Four of five runs cited concrete layout cues (e.g. EMPLOYER, RATE, HOURS, CURRENT, YTD, PAY), which matches the pay-stub genre even when phrased as a summary.

## What to treat carefully

### Finding 1 — Evidence can be wrong while the label stays right (degraded D01)

On **D01-degraded.jpg**, every run classified correctly as `government_notice` with `confidence: high`, but the **evidence** repeatedly quoted: *“Department of **Transportation** is required to verify current household income.”* The clean PDF runs instead referenced **Department of Transitional Assistance** and “Notice of Earned Income” — aligned with the synthetic document. So degradation did not break the **headline label**, but it **broke textual grounding** in a **stable** way (same fabricated agency line in 5/5 runs, not one-off noise).

**Product implication:** The model can **correctly classify** a document while **fabricating** the quoted justification. **Do not surface the `evidence` field directly to residents** without a separate grounding check (e.g. verify quoted spans against OCR, retrieval, or human review). Using `evidence` for **internal logging and debugging** is reasonable; using it as a **resident-facing explanation** on degraded or unknown-quality uploads is **not** safe.

### Finding 2 — Generic evidence on clean D03 (lower severity)

One clean D03 run used a generic description (“structured data detailing earnings, rates, hours, and deductions”) rather than naming specific on-page labels. That is not necessarily false, but it is weaker than a literal quote and would fail a strict “quote the document” bar.

### Finding 3 — Confidence did not separate clean vs degraded in this sample

All 20 runs reported **`confidence: high`**, including degraded inputs. So in this small run, **confidence was not a reliable indicator** of image quality or of evidence trustworthiness. Treat **`confidence` as uncorroborated** unless you calibrate it against held-out data or combine it with other signals.

## Decision tree implications

- **Classification-only path** (routing, bucket selection, which downstream extractor to run) looks **promising** on this spike: labels were stable and accurate at temp=0 for these two synthetics.
- **Evidence + confidence** must **not** gate resident trust or compliance copy without **independent verification** — the D01-degraded pattern shows **label correct + evidence confidently wrong**.

## Recommended follow-ups

1. **Policy:** Treat `classification` and `evidence` as **independent** outputs; only show resident-facing rationale from **grounded** sources.
2. **Optional eval:** Add automated checks that `evidence` strings appear in OCR text (or fuzzy match), and flag mismatches for review even when the label is correct.
3. **Re-run** with more documents and non-zero temperature to see whether label stability and confidence behavior generalize.
