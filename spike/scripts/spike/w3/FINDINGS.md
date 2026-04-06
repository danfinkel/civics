# W3 Warm-Up Findings: Abstention vs. Guessing (D01-blurry)

## What we tested

Whether `gemma4:e2b` returns **`UNCERTAIN`** (with reasons) when it cannot read a field, instead of inventing values. Input: **D01-blurry.jpg** (~bottom 28% darkened), **5 runs, temperature=0.**

The prompt **evolved during the spike**:

1. **Baseline** — extraction prompt with **`notice_date` / `response_deadline`**, plain string **`holder_name`**, no transcription rules. (Logged in an earlier `w3_abstention_results.json` before the prompt change.)
2. **Current** — same date disambiguation, plus **transcription-mode `holder_name` rules** (copy character-by-character as printed; **`UNCERTAIN`** if any part unclear; no normalization or guessing; partial visibility → **`UNCERTAIN`**) and **`holder_name` as `{"value", "reason"}`** in the JSON schema.

Synthetic ground truth (`D01-clean.html`): **holder** Maria Gonzalez-Reyes; **notice date** April 1, 2026; **response deadline** April 15, 2026.

Latest raw logs: **`w3_abstention_results.json`** (transcription-mode prompt).

## What the two prompt regimes show

### Baseline holder field (no transcription instructions)

- **`holder_name`:** **“Darla Gonzales”** **5/5** — **not** a minor misread of the real name; a **plausible but unrelated** identity, **perfectly stable**. No **`UNCERTAIN`**, so nothing in the JSON flags the error.

**Implication:** Default “extract the holder name” behavior on this setup **requires human review** (or other gates) before any case linkage or resident-facing use. Fuzzy match against a roster would **not** rescue this failure mode—the string is **too far** from truth.

### Transcription-mode holder field (current file)

- **`holder_name`:** **“Maria Gonzalez-Raynes”** **5/5** vs ground truth **“Maria Gonzalez-Reyes.”** Same **structure** (given name + hyphenated surname), **small tail error** (**Raynes** vs **Reyes**) consistent with **misread glyphs**, not a random confabulation.
- **`holder_name` → `UNCERTAIN`:** **0/5** — the model **committed** to a full string rather than abstaining on D01-blurry, so the strict “partially visible → UNCERTAIN” rule is **not** reliably followed even when the image is degraded; the win is **what kind of error** appears, not abstention rate.

**Implication:** Transcription-style prompting **does not fully “solve”** names, but it **changes the error class** from **unrelated fiction** to **recoverable transcription noise**. That is **compatible with automation**: e.g. **fuzzy match** to enrolled names (Levenshtein or similar) with a **tuned threshold** (order-of-magnitude example: **edit distance ≤ 3** on tokens or full string—**calibrate on your corpus**, do not treat the number as universal).

### Other fields (current file)

- **Semantic date fields:** **`notice_date`** and **`response_deadline`** still **5/5** with **April 1, 2026** and **April 15, 2026**, matching the template. **Prompt specificity for date roles** remains a **durable win**.
- **`key_amount_or_address`:** **`UNCERTAIN` 5/5** with reasons citing lack of visible amount/address — **clean abstention** on this dimension in the latest run.
- **`document_type`:** **“Notice”** **5/5** in the current log (stable short label in this batch).
- **Parsing:** **0** JSON parse failures.

## Architectural takeaway (name fields)

**Name hallucination is prompt-responsive but not fully resolvable in-prompt alone.**

| Regime | Typical failure | Downstream strategy |
|--------|------------------|---------------------|
| Default extraction | Unrelated plausible name, stable | **Human review** (fuzzy match will not help) |
| **Transcription-mode** prompt | Near-correct string, small character errors | **Fuzzy match** to canonical records; avoid **exact** string equality as the only pass criterion |

**Recommendations:**

1. **Always use transcription-mode prompting** for resident / holder names (verbatim-as-printed, explicit ban on normalization and guessing, structured value/reason).
2. **Pair with a matching layer** that uses **fuzzy similarity** (and policy thresholds), not **exact** match, when linking extracted names to CRM / roster / prior uploads.
3. **Keep** OCR alignment or human spot checks for **high-stakes** decisions even when fuzzy match passes.

## Relationship to the blurry-band hypothesis

The dark band was intended to hide **deadline / consequence** text. The model still returns **April 15, 2026** **5/5**; that remains **numerically** consistent with the clean HTML but **does not prove** the model read the obscured pixels (template completion is possible). **Holder** behavior in the **transcription** run is now best read as **minor surname error**, not wrong-person fiction—**different risk profile** than the baseline run.

## Decision tree implications

- **Date disambiguation** (`notice_date` / `response_deadline`): **keep** in production-oriented prompts.
- **Names:** treat **prompt style** as a **safety switch** between “random plausible entity” and “noisy transcription”; **neither** replaces **matching policy** and **audit** for government documents.
- **Numeric / structured abstention** (`key_amount_or_address` as **`UNCERTAIN`**) can behave well; **do not assume** the same threshold applies to **free-text names** without transcription rules.

## Recommended follow-ups

1. **Default** new name extractors on **transcription-mode** instructions; document the baseline failure mode for reviewers.
2. **Implement and tune** fuzzy name match (distance metric, threshold, tokenization for hyphenated surnames) on labeled pairs from this spike and future docs.
3. **Measure** abstention rate for **`holder_name`** on **heavier** occlusions and **non-Latin** scripts; transcription prompt may need locale-specific examples.
4. **Side-by-side** **D01-clean** vs **D01-blurry** under transcription mode to separate **blur** from **model prior** on the Raynes/Reyes slip.
