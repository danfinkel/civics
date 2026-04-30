# W1 Warm-Up Findings: Structured Extraction

## What we tested

JSON field extraction against D03 (pay stub), clean PDF and degraded JPG, 10 runs each at temperature=0.

## What passed

- **Dates and pay periods** extracted correctly and with near-perfect stability on both clean and degraded inputs.
- **JSON output** 100% parseable across all 20 runs — no markdown wrapping, no narrative text.
- **Abstention** working correctly — `pay_date` returned `UNREADABLE` on degraded 9/10 when the field was genuinely hard to read.
- **Degraded accuracy (84.2%)** only 3.6 points below clean (87.8%) — the model is more robust to photo quality than expected.

## What failed

### Finding 1 — YTD column confusion (clean PDF)

The model hallucinated YTD gross ($10,258.75) and YTD net ($7,334.26) instead of current-period values on 9/10 and 10/10 clean runs respectively. Explicit prompt instructions to prefer current-period values did not reliably fix this. This is a systematic failure mode tied to dense tabular layouts where current and YTD values share the same visual row structure. Expected to generalize to real-world pay stubs from ADP, Paychex, Gusto, etc.

### Finding 2 — Arithmetic inference on degraded input

On degraded images, the model appears to compute net pay by subtracting deductions from gross rather than reading the explicitly labeled Net Pay field. When the deduction value is misread (cramped columns in the degraded image), this produces a confidently wrong net figure with no abstention signal — $1,258.75 instead of $1,324.85, consistent across 10/10 degraded runs. Dangerous because the output is internally consistent and looks plausible.

### Finding 3 — Inverse clean/degraded performance on key financial fields

Gross income was correct 10/10 on degraded but only 1/10 on clean. This counterintuitive result suggests degradation accidentally suppresses the YTD column, removing the confounding candidate. Real-world implication: model performance on financial fields may not correlate with image quality in the expected direction.

### Finding 4 — Consistent name truncation

Maria Gonzalez-Reyes truncated to Maria Gonzalez-Rey on both clean and degraded across all runs. Hyphenated surnames appear to be reliably clipped. Low severity for the spike but worth noting for a production system serving a Spanish-surname-heavy population.

## Decision tree implications

- **Hallucination rate** of 41.4% on clean and 14.3% on degraded both exceed the ≤5% spike target. Per the decision tree, this warrants prompt hardening before the formal spike Day 1.
- The **arithmetic inference failure (Finding 2)** is not addressed by the standard decision tree — recommend adding an explicit mitigation: instruct the model to read labeled fields directly and never compute values by inference.
- **OCR pre-processing fallback** is not indicated yet — the model is reading text correctly; the failures are semantic (wrong field selection), not legibility failures.

## Recommended actions before formal spike

1. **Redesign D03** to separate YTD totals into a visually distinct section — not to paper over the finding, but to isolate whether column confusion is the cause or a contributing factor alongside other layout signals.
2. **Add prompt instruction:** “Read each field value directly from its labeled location. Do not calculate or infer any value by arithmetic.”
3. **Re-run 10×** after each change to confirm hallucination rate drops before proceeding to Day 1.
