# W4 Warm-Up Findings: Proof Category Matching

## What we tested

Whether `gemma4:e2b` can decide if a **document satisfies a requested proof category**, given an explicit **category definition** (not blind classification). Category: **EARNED INCOME**. Inputs:

| Document | Role in experiment |
|----------|-------------------|
| **D03.pdf** (clean pay stub) | Should accept as valid earned-income proof |
| **D03-degraded.jpg** | Same stub, degraded; accept, with lower confidence expected in the write-up |
| **D01.pdf** (government notice) | **Hard case:** notice **mentions** earned-income documentation but **is not** pay proof |

**5 runs per document, temperature=0.** Raw logs: `w4_match_results.json`.

## Headline result

**Category matching is the strongest behavior observed across W1–W4 on these synthetics.** All **15/15** runs produced **parseable JSON** with **`assessment`** and **`confidence`** aligned with the intended outcome for each pairing:

- **D03 clean:** **`likely_satisfies`** **5/5**, **`confidence: high`** **5/5**.
- **D03 degraded:** **`likely_satisfies`** **5/5**, **`confidence: high`** **5/5** (see caveat below vs. the original “expect medium” note).
- **D01:** **`likely_does_not_satisfy`** **5/5**, **`confidence: high`** **5/5**.

Within each file, **labels did not drift** across runs at temp=0.

## What passed (product-critical)

### Accept valid proof

The model **consistently treated the pay stub as satisfying** the earned-income definition, including on **degraded** JPEG.

### Reject invalid proof despite semantic pull (D01)

**D01** is the important stress test: the layout **explicitly references “EARNED INCOME (Required)”** and asks the recipient to **submit** documentation—so a shallow “keyword match” could wrongly **accept**. Instead, every run returned **`likely_does_not_satisfy`** with **`high`** confidence and **caveats** that correctly distinguish **a request for proof** from **proof itself** (e.g. that the document does not **contain** earned-income proof). That supports **sound category mapping** for this spike, not mere string matching on “income.”

### Structured output

**0** JSON parse failures across **15** runs; schema fields **`assessment`**, **`confidence`**, **`evidence`**, **`caveats`** were present and usable for downstream logic.

## What to treat carefully

### Evidence strings are not a verification layer

**`assessment` looks reliable here; `evidence` does not automatically qualify as a verbatim quote**, consistent with W2/W3 patterns.

- **D03 clean:** The repeated **`evidence`** snippet (**“Regular $1,847.50 $10,258.75”**) bundles figures in a way that overlaps with **W1’s YTD vs. current-period confusion**—plausibly **document-adjacent** but not clearly a **faithful transcription** of a single labeled line.
- **D03 degraded:** **`evidence`** often lists a **long, specific breakdown** (e.g. **Regular Pay $175.78**, overtime, differential, totals). That level of detail **reads like grounding**, but it **must be checked against OCR** before treating it as **court-grade citation**. On degraded inputs, **do not assume** the model quoted exactly what appears in pixels.

**Architecture implication (per product review):** The **matching layer** (category + definition → **`assessment`**) is **viable as designed** for routing and first-pass decisions on this evidence. **`evidence`** is best treated as **supporting context for human review** or internal debugging, **not** as a **verifiable quote** for residents or compliance audit **unless** separately grounded (e.g. substring check against OCR).

### Confidence did not drop on degraded D03 in this sample

The experiment narrative suggested **medium** confidence on **D03-degraded**; observed runs were **`high`** **5/5**. So **`confidence` is not yet validated** as a **calibrated** legibility signal—same lesson as W2/W3. **Do not rely on model-reported confidence** for policy thresholds without calibration.

## Cross–warm-up comparison (informal)

| Warm-up | Core question | Standout risk |
|---------|----------------|---------------|
| W1 | Field extraction | Wrong field / YTD confusion; arithmetic fill-ins |
| W2 | Blind doc type | Label OK, **evidence** can lie on degraded |
| W3 | Abstention | Names without transcription rules **confabulate**; transcription + fuzzy helps |
| **W4** | **Proof vs. category** | **Strong `assessment`; weak trust in `evidence` quotes** |

## Decision tree implications

- **Ship-shaped:** Document + **explicit category definition** → **`assessment`** for **automation-friendly** accept/reject on this slice of synthetics.
- **Guardrail:** **`evidence`** and **`caveats`** → **human-readable context**, optional OCR grounding, **not** sole source of truth for **what the document says**.
- **Optional:** Down-weight or hide **`evidence`** in resident UI; keep for **staff** review queues.

## Recommended follow-ups

1. **OCR grounding check** on **`evidence`** for a sample of degraded uploads; auto-flag when the string is not found in extracted text.
2. **Calibrate `confidence`** (or drop it from gating) using labeled clean/degraded sets.
3. **Expand categories** (rent, identity, etc.) and **adversarial** docs that **mention** a category without satisfying it.
4. **Revisit D03-degraded** after prompt tweaks if **medium** confidence on noisy images is a **product requirement** (model may need explicit instruction to lower confidence when legibility is poor).
