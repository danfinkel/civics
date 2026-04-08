# Week 2 Revised Plans (Rev 2)

**Date:** April 7, 2026  
**Sprint:** Week 2 (April 14–18, 2026)

---

## Agent Status

| Agent | Week 2 Status | Revised Plan? |
|-------|---------------|---------------|
| **Agent 1** | In progress — Unblocked | ✅ Yes (integration focus) |
| **Agent 2** | **RECOVERY NEEDED** | ✅ Yes (on-device recovery) |
| **Agent 3** | In progress — Deploy blocked | ✅ Yes (deployment focus) |
| **Agent 4** | **COMPLETE** | ❌ No — awaiting demo Thursday |

---

## Key Issue: On-Device Inference At Risk

### Agent 2: Cloud Fallback is NOT the Goal
- Agent 2 declared "cloud fallback as primary" — **this is wrong**
- On-device inference is the **core product differentiation**
- Cloud fallback is risk mitigation, not architecture

### Recovery Required
Agent 2 must attempt on-device recovery via:
- **Option A:** FFI to C++ MediaPipe (recommended)
- **Option B:** Platform channels to native iOS/Android
- **Option C:** Alternative stack (llama.cpp, MLX)

**Decision required by EOD.**

### Agent 3: Deployment Blocked
- Code complete, awaiting HF_TOKEN
- Manual Space creation is fallback

### Agent 1: No Longer Blocked
- Agent 2 delivered working `InferenceService`
- Use `preferCloud: true` for integration

---

## Revised Schedule

```
Tuesday:   Agent 1 integrates with Agent 2's cloud fallback
           Agent 3 deploys to HF Spaces

Wednesday: Agent 1 tests B1-B8 scenarios
           Agent 3 tests API with Agent 2

Thursday:  Agent 1 bug fixes
           Agent 3 mobile browser testing
           Agent 4 records demo (all agents support)

Friday:    Agent 1 physical device testing
           All agents: demo ready
```

---

## Critical Path

1. **Agent 3 deploys** → provides URL to Agent 2
2. **Agent 2 confirms** API works → Agent 1 integrates
3. **Agent 1 tests** B1 scenario → demo viable
4. **Agent 4 records** Thursday/Friday

---

## Files

- `agent1_integration.md` — Agent 1 revised plan
- `agent3_deployment.md` — Agent 3 revised plan
- `README.md` — This file

---

## Friday Goal (Unchanged)

Track B demo (B1 scenario) working end-to-end on physical device.
