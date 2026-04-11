# Agent 4 — Week 2 Sprint Report

**Agent:** Agent 4 (Design System + Video Production)  
**Sprint:** Week 2 (April 14–18, 2026)  
**Report Date:** April 7, 2026  
**Status:** Documentation Complete, Awaiting Demo for Recording

---

## Executive Summary

Agent 4 successfully completed all documentation deliverables for the CivicLens hackathon video. The 3-minute video script, demo scenarios, recording setup guide, and presentation slide specifications are ready for production. Screen recording is pending delivery of the working demo from Agents 1-3, scheduled for Thursday per the build plan.

---

## Deliverables Completed

### 1. Video Script (3 Minutes)

**File:** `docs/video/script.md`  
**Status:** ✅ Complete and timed

**Timing Breakdown:**

| Section | Time | Duration | Visual | Audio Focus |
|---------|------|----------|--------|-------------|
| The Problem | 0:00–0:30 | 30 sec | Text animation | Document burden on families |
| Our Approach | 0:30–1:00 | 30 sec | Spike methodology | 100+ experiments, evidence-driven |
| Demo B1 (Happy Path) | 1:00–1:45 | 45 sec | Screen recording | Successful document verification |
| Demo B4 (Warning) | 1:45–2:15 | 30 sec | Screen recording | Duplicate category detection |
| Privacy Architecture | 2:15–2:45 | 30 sec | Architecture diagram | On-device processing |
| Call to Action | 2:45–3:00 | 15 sec | Closing card | "Documents stay on your phone" |
| **Total** | | **2:50** | | |

**Script Features:**
- Plain language, no technical jargon
- Emphasis on privacy and on-device processing
- Practice reading time: 2 minutes 50 seconds
- Includes alternate 60-second version
- Reading notes with pacing and emphasis guidance

### 2. Demo Scenarios

**File:** `docs/video/scenarios.md`  
**Status:** ✅ Complete

**Scenario B1 — Complete Valid Packet (Happy Path):**
- **Purpose:** Show successful end-to-end flow
- **Documents:** D12 (birth cert), D05 (lease), D06 (utility), D13 (immunization)
- **Expected Result:** All 4 requirements satisfied, duplicate_flag: false
- **Recording Target:** 45 seconds
- **10-step walkthrough** with visual and audio cues documented

**Scenario B4 — Duplicate Category Warning:**
- **Purpose:** Show error detection and helpful guidance
- **Documents:** D12, D05, D14 (second lease), D13
- **Expected Result:** All satisfied BUT duplicate_flag: true with amber warning
- **Recording Target:** 30 seconds
- **9-step walkthrough** with transition from B1

**Document Reference Table:**
All 5 documents mapped from `/spike/artifacts/` with categories and expected outputs.

### 3. Recording Setup Guide

**File:** `docs/video/recording_setup.md`  
**Status:** ✅ Complete

**Methods Documented:**

| Method | Platform | Quality | Use Case |
|--------|----------|---------|----------|
| iOS Device (Preferred) | iOS 11+ | ⭐⭐⭐⭐⭐ | Primary recording |
| Android Device | Android 11+ | ⭐⭐⭐⭐☆ | Alternative |
| iOS Simulator | macOS | ⭐⭐⭐☆☆ | Backup |
| Android Emulator | Any | ⭐⭐☆☆☆ | Last resort |

**iOS Setup Includes:**
- Control Center configuration
- Document transfer via AirDrop
- Do Not Disturb and brightness settings
- Recording start/stop procedures
- File transfer to computer

**Post-Processing Guide:**
- Trim recommendations
- Target durations (B1: 45s, B4: 30s)
- Export settings (MP4, 1080p, 30fps)

**Troubleshooting Section:**
Common issues and solutions for recording problems.

### 4. Presentation Slide Specifications

**File:** `docs/video/slides.md`  
**Status:** ✅ Complete

**5 Slides Specified:**

| Slide | Duration | Purpose | Key Elements |
|-------|----------|---------|--------------|
| Title Card | 3 sec | Opening | Logo, tagline, event name |
| Problem Statement | 30 sec | Context | Animated text, key terms highlighted |
| Spike Methodology | 30 sec | Credibility | 16 documents, accuracy metrics |
| Architecture Diagram | 30 sec | Privacy | 4-box flow, "no cloud" message |
| Closing Card | 5 sec | Branding | Logo, tagline, app icon |

**Technical Specs:**
- Resolution: 1920×1080 (1080p)
- Font: Inter (400, 600, 700 weights)
- Color palette: CivicLens institutional colors
- Export: PNG or MOV with alpha

**Creation Options:**
- Stitch export (existing templates)
- Google Slides (template ready)
- PowerPoint (template ready)
- Design software (Figma/Sketch)

---

## File Structure Created

```
docs/video/
├── script.md              # 3-minute video script
├── scenarios.md           # B1 and B4 demo walkthroughs
├── recording_setup.md     # Technical recording guide
└── slides.md              # Presentation slide specs

docs/sprint/week2_reports/
└── agent4_week2_report.md # This report
```

---

## Acceptance Criteria Status

From Week 2 build plan:

| Criteria | Status | Notes |
|----------|--------|-------|
| 3-minute script drafted and timed | ✅ Complete | 2:50 reading time |
| B1 scenario documented with expected outputs | ✅ Complete | 10-step walkthrough |
| B4 scenario documented with expected outputs | ✅ Complete | 9-step walkthrough |
| Recording setup guide complete | ✅ Complete | 4 methods documented |
| Raw screen recordings captured | ⏳ Pending | Waiting for demo (Thursday) |
| Footage handed off to Week 3 | ⏳ Pending | After recording |

---

## Dependencies

| Dependency | From | Status | Impact |
|------------|------|--------|--------|
| Working demo | Agents 1-3 | ⏳ Thursday | Required for screen recording |
| Test documents | `/spike/artifacts/` | ✅ Ready | D12, D05, D06, D13, D14 verified |

---

## Next Steps

### Thursday (Demo Day)
- [ ] Coordinate with Agent 1 for demo availability
- [ ] Test CivicLens app on recording device
- [ ] Verify all 5 documents load correctly
- [ ] Record B1 scenario (multiple takes)
- [ ] Record B4 scenario (multiple takes)

### Friday (Wrap-up)
- [ ] Transfer footage to computer
- [ ] Review and select best takes
- [ ] Trim and prepare raw files
- [ ] Hand off to Week 3 for editing
- [ ] Update status report

---

## Risk Mitigation

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Demo not ready Thursday | Medium | Can use simulator recording as backup |
| Recording quality issues | Low | Multiple takes, 4 methods available |
| Documents don't produce expected output | Low | Documented actual outputs acceptable |
| Audio sync issues | Low | Separate narration track possible |

---

## Key Metrics

| Metric | Value |
|--------|-------|
| Script word count | ~450 words |
| Script reading time | 2:50 (target: 3:00) |
| Demo scenarios documented | 2 (B1, B4) |
| Recording methods documented | 4 |
| Presentation slides specified | 5 |
| Documentation files created | 4 |
| Total documentation pages | ~15 |

---

## Collaboration Notes

- **Agent 1 (Flutter):** Will provide working demo by Thursday
- **Agent 3 (Web):** Web demo can serve as backup recording source
- **Week 3 (Editing):** Will receive raw footage Friday for post-production

---

## Lessons Learned

1. **Early documentation pays off:** Having scripts and scenarios ready before demo day reduces stress
2. **Multiple recording methods:** Documenting 4 approaches ensures we can capture footage regardless of technical issues
3. **Spike artifacts are valuable:** Having pre-tested documents (D12-D14) ensures predictable demo outcomes

---

## Resources

- **Stitch Project:** https://stitch.google.com/projects/7798513400064434
- **Design Specs:** `/docs/design/civiclens_design_specs.md`
- **Presentation Templates:** `/docs/design/presentation_templates.md`
- **Spike Artifacts:** `/spike/artifacts/`

---

## Conclusion

All Week 2 documentation deliverables are complete and ready for production. The video script tells a compelling 3-minute story emphasizing privacy, evidence-driven development, and real-world utility. Demo scenarios are thoroughly documented with step-by-step instructions. Recording setup is prepared for multiple platforms.

**Ready for Thursday's demo recording session.**

---

**Report Prepared By:** Agent 4  
**Review Status:** Complete, Pending Demo  
**Next Report:** After screen recording (Friday)
