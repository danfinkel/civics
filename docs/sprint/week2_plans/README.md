# CivicLens — Week 2 Work Plans

**Sprint:** Week 2 (April 14–18, 2026)  
**Goal:** Complete Track B end-to-end on mobile. Demo scenario B1 working on a real phone by Friday.

---

## Agent Assignments

| Agent | Focus | Key Deliverable |
|-------|-------|-----------------|
| **Agent 1** | Mobile Track B UI + Integration | Working Track B on physical iPhone |
| **Agent 2** | MediaPipe Integration + Performance | Real Gemma 4 inference (not mock) |
| **Agent 3** | Web Demo Deployment + Polish | HF Spaces URL + Cloud fallback API |
| **Agent 4** | Video Script + Demo Scenarios | 3-minute script + screen recordings |

---

## Integration Schedule

```
Monday    Tuesday   Wednesday   Thursday   Friday
├─A1      ├─A1      ├─A1+A2     ├─All      ├─Demo
├─A2      ├─A2      │ (integrate)├─Test     └─Ready
├─A3      ├─A3      ├─A3        ├─A3
└─A4      └─A4      └─A4        └─A4
```

**Wednesday:** Critical integration day — Agents 1 and 2 work together  
**Thursday:** All-hands testing — B1-B8 scenarios  
**Friday:** Demo ready on physical device

---

## Key Dependencies

1. **Agent 2 → Agent 1:** MediaPipe integration ready by Wednesday AM
2. **Agent 3 → Agent 2:** Cloud fallback endpoint ready by Thursday
3. **Agents 1-3 → Agent 4:** Working demo needed by Thursday for recording

---

## Week 2 Success Criteria

- [ ] Track B complete packet analysis works end-to-end on mobile device
- [ ] B1 scenario (complete valid packet) passes on physical iPhone
- [ ] B4 scenario (duplicate category) shows correct warning
- [ ] HF Spaces deployed with stable public URL
- [ ] Cloud fallback API working for mobile
- [ ] 3-minute video script complete and timed
- [ ] Screen recordings captured for B1 and B4 scenarios

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| MediaPipe integration fails | Use cloud-only mode for demo |
| E2B too slow on device | Document performance, use cloud fallback |
| HF Spaces deployment blocked | Use local Ollama for demo |
| Physical device issues | Test on simulator first |

---

## Files

- `agent1_mobile_trackb.md` — Agent 1 work plan
- `agent2_mediapipe_integration.md` — Agent 2 work plan
- `agent3_web_demo_deployment.md` — Agent 3 work plan
- `agent4_video_script.md` — Agent 4 work plan

---

## Communication

- Daily standups: Post progress in team channel
- Wednesday integration: #agent-1-2-integration
- Blockers: Escalate immediately
