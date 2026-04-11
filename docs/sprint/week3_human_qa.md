# Week 3 Human QA Findings

**Date:** [fill in after walkthrough]  
**Device:** iPhone [model], iOS [version]  
**Tester:** [name]  
**Build:** [debug/release, eval mode Y/N]

---

## Setup (5 min)

```bash
./mobile/scripts/sync_test_assets.sh   # ensure test images in Photos
./mobile/scripts/dev_deploy.sh          # fresh install
```

Verify test images are in Photos app:
- D01-degraded.jpg, D03-degraded.jpg, D04-degraded.jpg (Track A)
- D05-degraded.jpg, D06-degraded.jpg, D07-degraded.jpg, D12-degraded.jpg, D13-degraded.jpg, D14-degraded.jpg (Track B)
- D01-blurry.jpg (A6 test)

---

## FLOW 1: Track A — D01/D03 happy path (the RMV story)

- [ ] Home screen looks polished, no placeholder text
- [ ] Tap "SNAP Benefits" — navigates correctly
- [ ] Upload D01-degraded.jpg as notice — blur check passes, slot fills
- [ ] Upload D03-degraded.jpg as pay stub — slot fills
- [ ] Tap "Analyze" — processing state visible, not frozen
- [ ] Results: deadline banner is the FIRST thing I see
- [ ] Results: "earned income" row shows green satisfied status
- [ ] Results: no technical labels anywhere on screen
- [ ] Action summary: reads like a knowledgeable friend, not a computer
- [ ] Back/start over navigation works

**Notes/issues:**

---

## FLOW 2: Track A — A3 stale pay stub

- [ ] Upload D01-degraded.jpg as notice
- [ ] Upload D04-degraded.jpg as stale pay stub
- [ ] Results: income row shows "May not meet this requirement"
- [ ] Caveats mention the date issue
- [ ] Action summary tells me to get a more recent pay stub

**Notes/issues:**

---

## FLOW 3: Track A — A6 blurry notice

- [ ] Upload D01-blurry.jpg as notice
- [ ] Upload D03-degraded.jpg as pay stub
- [ ] Results: amber "unclear notice" banner visible
- [ ] App does not confidently assert wrong deadline

**Notes/issues:**

---

## FLOW 4: Track B — B1 complete packet

- [ ] Tap "School Enrollment" from home
- [ ] Upload D12 (birth certificate)
- [ ] Upload D05 (lease 1)
- [ ] Upload D06 (utility bill)
- [ ] Upload D13 (immunization record)
- [ ] Results: all 4 requirements green
- [ ] No technical labels
- [ ] Family summary is clear

**Notes/issues:**

---

## FLOW 5: Track B — B4 duplicate leases

- [ ] Upload D12 (birth certificate)
- [ ] Upload D05 (lease 1)
- [ ] Upload D14 (lease 2 — same address)
- [ ] Upload D13 (immunization record)
- [ ] Results: duplicate category warning banner is unmissable
- [ ] Warning explains in plain language: two leases = one category
- [ ] Family summary tells me what to replace

**Notes/issues:**

---

## FLOW 6: Error states

- [ ] Take a deliberately blurry photo — blur warning appears
- [ ] "Use anyway" override works
- [ ] Try navigating back mid-inference — app handles gracefully

**Notes/issues:**

---

## Summary

### P0 Issues (blocking demo recording)
| # | Issue | Screenshot | Assigned |
|---|-------|------------|----------|
| 1 | | | |
| 2 | | | |

### P1 Issues (visible to judges)
| # | Issue | Screenshot | Assigned |
|---|-------|------------|----------|
| 1 | | | |
| 2 | | | |

### P2 Issues (edge cases / nice to have)
| # | Issue | Notes |
|---|-------|-------|
| 1 | | |

### Looks Good ✓
- [item]
- [item]

---

## Sign-off

**Tester:** _________________  **Date:** _________________

**All P0 issues resolved:** [ ] Yes  [ ] No — blocked on: _________________

**Ready for Agent 4 video recording:** [ ] Yes  [ ] No
