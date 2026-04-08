# CivicLens — Demo Scenarios

**Prepared for:** Week 2 Screen Recordings  
**Date:** April 7, 2026  
**Agent:** Agent 4

---

## Document Reference

All documents are from the spike artifacts in `/spike/artifacts/`:

| Doc ID | Type | Category | Language | Notes |
|--------|------|----------|----------|-------|
| D12 | Birth Certificate | Proof of Age | English | Clean, official |
| D05 | Lease Agreement | Residency (Lease/Deed) | English | Standard lease |
| D06 | Utility Bill | Residency (Utility) | English | Electric bill |
| D13 | Immunization Record | Immunization | English | Official form |
| D14 | Second Lease | Residency (Lease/Deed) | English | For duplicate test |

---

## Scenario B1 — Complete Valid Packet (Happy Path)

**Purpose:** Show successful end-to-end flow  
**Duration Target:** 45 seconds  
**Expected Result:** All 4 requirements satisfied

### Documents Used

1. **D12** (birth certificate) → Proof of Age
2. **D05** (lease agreement) → Residency Proof 1
3. **D06** (utility bill) → Residency Proof 2
4. **D13** (immunization record) → Immunization

### Expected JSON Output

```json
{
  "requirements": [
    {
      "requirement": "Proof of Age",
      "status": "satisfied",
      "matched_document": "birth_certificate.pdf",
      "evidence": "Document shows date of birth: January 15, 2018",
      "notes": ""
    },
    {
      "requirement": "Residency Proof 1",
      "status": "satisfied",
      "matched_document": "lease_agreement.pdf",
      "evidence": "123 Main Street, Boston, MA",
      "notes": ""
    },
    {
      "requirement": "Residency Proof 2",
      "status": "satisfied",
      "matched_document": "utility_bill.pdf",
      "evidence": "456 Oak Ave, Boston, MA - Bill dated March 2026",
      "notes": "Different category from lease - valid"
    },
    {
      "requirement": "Immunization Record",
      "status": "satisfied",
      "matched_document": "immunization_record.pdf",
      "evidence": "DTaP, MMR, Polio vaccines documented",
      "notes": ""
    }
  ],
  "duplicate_category_flag": false,
  "duplicate_category_explanation": "",
  "family_summary": "Your registration packet looks complete! Bring these documents to your BPS registration appointment."
}
```

### Screen Recording Steps

| Step | Action | Visual | Audio Cue |
|------|--------|--------|-----------|
| 1 | Open CivicLens app | Home screen appears | "Here's how it works" |
| 2 | Tap "School Enrollment" | Track B upload screen | "A family uploads their documents" |
| 3 | Tap slot 1, upload D12 | Thumbnail appears with checkmark | "Birth certificate" |
| 4 | Tap slot 2, upload D05 | Thumbnail appears with checkmark | "Lease agreement" |
| 5 | Tap slot 3, upload D06 | Thumbnail appears with checkmark | "Utility bill" |
| 6 | Tap slot 4, upload D13 | Thumbnail appears with checkmark | "Immunization record" |
| 7 | Tap "Check My Packet" | Loading screen appears | "CivicLens processes everything" |
| 8 | Wait for analysis | Loading animation | [Pause] |
| 9 | Results screen appears | All 4 green "Satisfied" | "All four requirements satisfied" |
| 10 | Scroll to family summary | Highlight summary card | "Your registration packet looks complete" |

### Success Criteria

- [ ] All 4 documents upload without errors
- [ ] Blur detection passes for all images
- [ ] Analysis completes in under 60 seconds
- [ ] All requirements show "Satisfied" (green)
- [ ] Duplicate category flag is false
- [ ] Family summary is clear and positive

---

## Scenario B4 — Duplicate Category Warning

**Purpose:** Show error detection and helpful guidance  
**Duration Target:** 30 seconds  
**Expected Result:** Duplicate category warning displayed

### Documents Used

1. **D12** (birth certificate) → Proof of Age
2. **D05** (lease agreement) → Residency Proof 1
3. **D14** (second lease) → Residency Proof 2 ← **DUPLICATE**
4. **D13** (immunization record) → Immunization

### Expected JSON Output

```json
{
  "requirements": [
    {
      "requirement": "Proof of Age",
      "status": "satisfied",
      "matched_document": "birth_certificate.pdf",
      "evidence": "Date of birth documented",
      "notes": ""
    },
    {
      "requirement": "Residency Proof 1",
      "status": "satisfied",
      "matched_document": "lease_agreement_1.pdf",
      "evidence": "Primary residence documented",
      "notes": ""
    },
    {
      "requirement": "Residency Proof 2",
      "status": "satisfied",
      "matched_document": "lease_agreement_2.pdf",
      "evidence": "Secondary address documented",
      "notes": "Same category as Proof 1"
    },
    {
      "requirement": "Immunization Record",
      "status": "satisfied",
      "matched_document": "immunization_record.pdf",
      "evidence": "Vaccinations up to date",
      "notes": ""
    }
  ],
  "duplicate_category_flag": true,
  "duplicate_category_explanation": "Two documents from the same category (lease/deed) count as only one proof. You need a second document from a different category such as a utility bill, bank statement, or government mail.",
  "family_summary": "You have all required documents, but your two residency proofs are from the same category. Bring a utility bill or bank statement instead of the second lease."
}
```

### Screen Recording Steps

| Step | Action | Visual | Audio Cue |
|------|--------|--------|-----------|
| 1 | Tap "Start Over" | Back to upload screen | "Now watch what happens" |
| 2 | Re-upload D12 | Thumbnail appears | [Quick, no narration] |
| 3 | Re-upload D05 | Thumbnail appears | [Quick] |
| 4 | Upload D14 to slot 3 | Thumbnail appears | "Swap the utility bill for a second lease" |
| 5 | Re-upload D13 | Thumbnail appears | [Quick] |
| 6 | Tap "Check My Packet" | Loading screen | [Pause] |
| 7 | Results screen appears | All satisfied + amber warning | "CivicLens flags the duplicate" |
| 8 | Scroll to warning banner | Highlight amber banner | "Two leases count as one proof" |
| 9 | Show family summary | Highlight updated summary | "The family knows to bring a different document" |

### Success Criteria

- [ ] All 4 documents upload successfully
- [ ] All requirements show "Satisfied" (technically correct)
- [ ] Duplicate category flag is true
- [ ] Amber warning banner is prominently displayed
- [ ] Warning explains the two-category rule clearly
- [ ] Family summary provides actionable guidance

---

## Recording Notes

### Timing

- **B1 Total:** ~45 seconds
- **B4 Total:** ~30 seconds
- **Combined:** ~75 seconds (fits within demo section)

### Visual Flow

1. Start with B1 (positive, establishes trust)
2. Smooth transition to B4 (shows intelligence)
3. End on the warning (memorable, useful)

### What to Emphasize

**B1:**
- Speed of analysis
- Clear green checkmarks
- Plain language summary

**B4:**
- The warning appears even though docs are "valid"
- Specific guidance (not just "error")
- Helps family avoid rejection at registration

### What to Avoid

- Don't show blur detection failures (keep it smooth)
- Don't show loading for too long (edit if needed)
- Don't scroll too fast
- Don't tap too quickly (let viewer follow)

---

## Backup Plans

### If D14 is not available

Use any other lease-type document from spike artifacts and note in video that it's a "second lease."

### If analysis is slow

- Keep recording, edit out long pauses in post-production
- Have a "Analyzing..." loading state ready

### If results differ from expected

- Document actual output
- Adjust script if needed
- As long as B1 shows success and B4 shows warning, the demo works

---

## File Locations

**Documents:**
```
/spike/artifacts/
├── D12_birth_certificate.pdf
├── D05_lease_agreement.pdf
├── D06_utility_bill.pdf
├── D13_immunization_record.pdf
└── D14_second_lease.pdf
```

**Recordings (to be created):**
```
/docs/video/recordings/
├── scenario_b1_happy_path.mov
└── scenario_b4_warning.mov
```

---

## Checklist for Recording Day

- [ ] All 5 documents loaded on test device
- [ ] CivicLens app installed and working
- [ ] Screen recording enabled on device
- [ ] Quiet recording environment
- [ ] Script printed for reference
- [ ] Backup device ready
- [ ] Agent 1 on standby for technical issues

---

**Document Version:** 1.0  
**Last Updated:** April 7, 2026  
**Status:** Ready for recording
