# Week 2 Friday: Finish Line

**Date:** Friday, April 10, 2026  
**Goal:** B1 demo working on physical iPhone, ready for recording  
**Theme:** Prove the privacy-first architecture works

---

## Agent Assignments

| Agent | Mission | Success Criteria |
|-------|---------|------------------|
| **Agent 2** | Full pipeline on device | B1 works end-to-end, handed off to Agent 1 |
| **Agent 1** | Demo ready | UI polished, B1 reliable, handed to Agent 4 |
| **Agent 4** | Capture recording | 60-90s demo video, ready for editing |
| **Agent 3** | Support + backup | HF Spaces stable, available if needed |

---

## Critical Path

```
Morning:
  9am  Agent 2: OCR + pipeline test
  10am Agent 2: Handoff to Agent 1
  11am Agent 1: UI integration
  12pm Agent 1: B1 manual test

Afternoon:
  1pm  Agent 1: Error handling, polish
  2pm  Agent 1: Handoff to Agent 4
  3pm  Agent 4: Setup, recording
  4pm  Agent 4: Capture takes
  5pm  Agent 4: Review, organize files
```

---

## Exit Criteria for Week 2

### Must Have (Demo Blockers)
- [ ] B1 scenario works on physical iPhone
- [ ] On-device inference (OCR + LLM)
- [ ] Results display correctly
- [ ] Demo recorded

### Should Have (Polish)
- [ ] B4 scenario works (duplicate warning)
- [ ] Performance < 120 seconds
- [ ] Clean error handling
- [ ] Multiple recording takes

### Nice to Have (Week 3)
- [ ] Android working
- [ ] All B1-B8 scenarios
- [ ] Speed optimizations
- [ ] Edited video

---

## Risk Assessment

| Risk | Level | Mitigation |
|------|-------|------------|
| OCR fails on device | 🟡 Medium | Agent 2 escalates by 10am |
| Pipeline crashes | 🟡 Medium | Agent 2 escalates by 12pm |
| UI integration breaks | 🟡 Medium | Agent 1 uses mock data for demo |
| Recording fails | 🟡 Medium | Use web demo backup |
| Total time > 120s | 🟢 Low | Demo anyway, optimize in Week 3 |

---

## Friday Checkpoints

| Time | Check | Owner |
|------|-------|-------|
| 10am | OCR working? | Agent 2 |
| 12pm | Pipeline working? | Agent 2 |
| 2pm | UI integrated? | Agent 1 |
| 4pm | Demo ready? | Agent 1 |
| 5pm | Recording done? | Agent 4 |

---

## Success Scenarios

### Best Case (Green)
- B1 works on device in < 120s
- Clean recording captured
- Week 2 complete, Week 3 for polish

### Acceptable (Yellow)
- B1 works but slow (> 120s)
- OR: Minor UI issues
- Demo recorded with caveats
- Document issues for Week 3

### Worst Case (Red)
- On-device fails
- Use web demo for recording
- Document on-device as Week 3 priority
- Still have a demo, just not on-device

---

## Key Principle

**Privacy first is the goal, not the blocker.**

If on-device truly doesn't work today, we:
1. Document what was tried
2. Use web demo for video
3. Make on-device Week 3 priority
4. Don't compromise the demo quality

But we're close. Agent 2 proved the model runs on device. Today is about connecting the pieces.

---

## Files

- `agent2_friday_finish.md` — Agent 2 mission
- `agent1_friday_finish.md` — Agent 1 mission
- `agent4_friday_recording.md` — Agent 4 mission
- `agent3_friday_support.md` — Agent 3 mission
- `README_FRIDAY.md` — This file

---

## End of Week 2

**Friday 5pm:** Assess against exit criteria.

**Then:** Week 3 planning (polish, video editing, submission prep).
