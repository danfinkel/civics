# CivicLens — Product Vision

**Version 1.0 | April 2026**  
**Hackathon:** Gemma 4 Good | Kaggle  
**Track:** Digital Equity & Inclusivity / Safety & Trust

---

## The Problem

Every year, millions of Americans interact with government benefit systems and public institutions that require them to submit documentary proof of who they are, where they live, and how much they earn. SNAP recertification. School enrollment. Housing assistance applications. Medicaid renewals. These processes share a common obstacle: residents must gather, interpret, and submit the right documents — often under deadline pressure, often without help, and often in their second language.

The administrative burden is not abstract. A family that misses a SNAP recertification deadline because they didn't understand which documents were required loses food assistance. A child who doesn't get enrolled in the right school because the family submitted two leases instead of a lease and a utility bill loses a school year. The documents are not hard to find. The instructions are not impossible to read. But the combination of unfamiliar bureaucratic language, tight deadlines, multiple simultaneous requirements, and the stress of economic precarity creates real failure rates for people who cannot afford to fail.

This is a solvable problem. The documents exist. The requirements are published. The gap is interpretation and organization — helping a resident understand whether what they have is what is needed, and what to do if it is not.

---

## Why Gemma 4, Why Now

Multimodal local language models capable of reading and reasoning about document photographs have not been practically deployable on consumer hardware until very recently. Gemma 4's E2B and E4B variants change that. A 4-billion-parameter model that can accept a phone photo of a pay stub and return structured, accurate field extraction — running entirely on device, without any network request — is a qualitatively new capability.

The privacy implication is significant for this use case. The documents involved — pay stubs, birth certificates, state IDs, government notices — are among the most sensitive documents a person carries. Existing solutions that require uploading these documents to a server ask residents to trust a third party with information they have good reason to protect. On-device inference removes that requirement entirely. The document never leaves the phone.

The multimodal capability matters because residents do not have scanners. They have phones. The real input to this system is a photograph taken under kitchen lighting, at a slight angle, with variable focus. A model that only works on clean PDFs is not useful in the field. A model that can extract structured information from a degraded phone photo is.

---

## What We Built and How We Know It Works

CivicLens was not designed by assumption. Before writing a line of product code, we ran a structured five-day feasibility spike testing Gemma 4 E4B against 16 synthetic civic documents — DTA verification notices, pay stubs, leases, utility bills, birth certificates, immunization records, and more — in both clean PDF and degraded phone-photo variants.

The spike was designed to answer four specific questions before committing to a build:

1. Can the model reliably extract structured fields from photographed documents?
2. Can it classify document types without being told what they are?
3. Can it assess whether a document satisfies a specific proof category?
4. Can it detect when something is missing or when a document is ambiguous?

We measured every experiment against formal pass/fail thresholds, recorded failure modes, and made architectural decisions based on evidence rather than assumptions. Here is what we found.

**What works reliably:**
- Document type classification: 100% accuracy across 16 document types on degraded phone photos, including Spanish-language documents and handwritten notes
- Category mapping: 85.9% accuracy on BPS requirements, 66.7% on SNAP proof categories
- Structured JSON output: 100% parseability across all runs with a retry wrapper
- Action/deadline extraction: 100% accuracy on readable government notices
- Critical safety checks: zero false positives — award letters never accepted as income proof, informal notes never accepted as residency proof, duplicate document categories correctly flagged

**What does not work reliably:**
- Field-level extraction from complex tabular layouts (pay stubs with adjacent current/YTD columns) — approximately 40% hallucination rate on specific numeric fields
- Abstention on blurry or partially obscured images — the model generates plausible-sounding content rather than flagging illegibility; this cannot be fixed through prompt engineering alone
- Missing-item detection recall — the model tends toward optimistic "likely satisfies with caveats" rather than hard MISSING flags; approximately 50–67% recall

**What these findings mean for the product:**

The two capabilities that work reliably — classification and category mapping — are the ones that matter most for a useful resident-facing tool. A resident does not primarily need a computer to read the exact dollar amount on their pay stub. They need to know whether the documents they have are the right documents for the request they received. That question the model answers well.

The two capabilities that do not work reliably — precise field extraction and image quality self-assessment — require architectural mitigations rather than prompt engineering. Blur detection runs before the image reaches the model. Human review is required for any output the model flags as uncertain. The product never auto-approves; it assists and the resident decides.

---

## Product Description

CivicLens is a privacy-first mobile application that helps residents prepare document packets for government benefit processes and school enrollment.

The application has two modes:

**SNAP Document Assistant (Track A):** The resident photographs a DTA verification or recertification notice and the documents they have at home. CivicLens reads the notice, identifies what proof categories are being requested and the deadline, assesses whether each uploaded document satisfies a requested category, and produces a checklist showing what is covered and what is missing — with a plain-language summary of what to do next.

**BPS Enrollment Assistant (Track B):** The resident photographs the documents they plan to submit for Boston Public Schools registration. CivicLens checks each document against the four BPS requirements (proof of age, two residency proofs from different categories, immunization record, grade indicator), flags the two-category residency rule if violated, and produces a plain-language summary of what to bring and what to replace.

In both modes:
- All inference runs on-device using Gemma 4 E2B. Documents never leave the phone.
- A blur detection check runs before any document reaches the model. Images below the quality threshold are flagged with guidance on retaking.
- All outputs include confidence levels. Low and medium confidence results are visually flagged for review.
- The application never states that a document is accepted by the relevant agency. It uses "appears to satisfy" language throughout. Final determination is always made by the agency.
- Action summaries are written in plain language designed for residents, not administrators. Spanish language documents are handled without degradation.

---

## Why This, Why Us

The combination of on-device inference, multimodal document understanding, and a use case where privacy is genuinely non-negotiable makes this a natural fit for Gemma 4's capabilities. We are not using a local model because it is novel. We are using it because the alternative — uploading a birth certificate and a state ID to a server — is a meaningful harm reduction failure for the population this tool is designed to serve.

The spike methodology is what distinguishes this from a typical hackathon prototype. We built 16 synthetic documents, ran over 100 inference experiments, identified specific failure modes, and made product decisions based on measured evidence. The 40% field-extraction hallucination rate that most teams would treat as a blocker became a design constraint: the product pre-fills and the resident corrects. The abstention failure on blurry images became a feature: blur detection routes poor-quality images to a retake prompt before they ever reach the model. Known limitations become explicit product requirements rather than hidden technical debt.

The residents this application is designed to serve — low-income families navigating SNAP recertification and school enrollment in Massachusetts — are not an abstract user persona. They are the people our spike's synthetic resident, Maria Gonzalez-Reyes, was designed to represent: working, under deadline pressure, often navigating bureaucratic systems in a second language, and unable to absorb the cost of a missed deadline or an incorrectly assembled packet.

CivicLens does not solve the underlying policy complexity. It does not replace caseworkers or enrollment offices. It gives residents the same kind of help that a knowledgeable friend would give — someone who can look at your documents and say: "you have what you need for this, but you're missing something for that, and you need to get it in by April 15."

---

## Design Principles

These principles apply to every product decision in the build phase:

**Privacy is not a feature, it is a constraint.** On-device inference is required, not optional. Any architectural decision that routes sensitive document content to a server requires explicit justification and explicit user consent.

**The model assists; the resident decides.** No output is presented as a final determination. Every assessment includes confidence context. The action summary tells residents what to do, not what the agency will accept.

**Honest about limitations.** The application surfaces uncertainty rather than hiding it. A document the model cannot read clearly is flagged. An assessment with caveats shows the caveats. The product is more trustworthy for being honest about what it does not know.

**Plain language throughout.** Government document processes are already full of bureaucratic language. The application's output — particularly the action summary — is written for a resident who may be reading it under stress, possibly in their second language, on a small phone screen.

**Evidence-driven development.** Product decisions during the build phase are grounded in spike findings. When a new question arises about model capability, the right response is to measure it, not assume it.

---

## Success Criteria for the Hackathon Submission

A successful submission demonstrates:

1. A working application that runs Gemma 4 on-device and handles real-world document photographs
2. A compelling resident-facing use case with genuine social impact in the Digital Equity category
3. A rigorous technical foundation — the spike methodology, measurements, and architectural decisions are documented and defensible
4. A video that tells the resident story before showing the technology
5. A codebase that is well-documented and reproducible

The measure of success is not whether the model achieves perfect accuracy. The measure is whether a resident using this application is meaningfully better positioned to successfully submit the right documents by the right deadline than they would be without it.

---

## Relationship to the Feasibility Spike

The full spike methodology, experiment results, and architectural decisions are documented in the `/spike` directory of the repository. The key outputs that inform the build phase are:

- `spike/docs/warmup_readout.docx` — Pre-spike findings from W1–W4
- `spike/docs/day1_findings.docx` — Structured extraction results and failure mode analysis
- `spike/docs/day2_findings.md` — Classification and category mapping results
- `spike/docs/day3_findings.md` — End-to-end scenario results for Track A and Track B
- `spike/docs/day5_decision_memo.md` — Final scoring table, decision tree, and go/no-go decision
- `spike/artifacts/` — 16 synthetic documents used in spike experiments
- `spike/scripts/` — All experiment runner and scoring scripts

These documents are the evidence base for every architectural decision in the build phase. When a build-phase agent makes a decision that touches model capability, prompt design, or output handling, it should reference the relevant spike finding.