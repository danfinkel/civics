# Agent 3 — Friday Mission: Support + Backup

**Date:** Friday, April 10, 2026  
**Goal:** Ensure demo has a working fallback, support other agents  
**Success Criteria:** HF Spaces stable, mobile tested, ready as backup

---

## Status

**HF Spaces:** ✅ Deployed and working  
**URL:** https://DanFinkel-civiclens.hf.space  
**API:** Ready for cloud fallback (if needed)

**Primary role this week:** Backup and support.

---

## Morning: Stability + Testing (9am–12pm)

### Step 1: Verify HF Spaces is Live (15 min)

**Check:**
```bash
curl https://DanFinkel-civiclens.hf.space/health
```

**Expected:**
```json
{"status": "healthy", "version": "1.0.0"}
```

**If down:**
- Check Hugging Face dashboard
- Restart Space if needed
- Alert team immediately

---

### Step 2: Mobile Browser Test (1 hour)

**Test matrix:**

| Device | Browser | Test | Status |
|--------|---------|------|--------|
| iPhone 13+ | Safari | Upload, analyze, results | [ ] |
| Android Pixel | Chrome | Upload, analyze, results | [ ] |

**Checklist for each:**
- [ ] File picker opens
- [ ] Images upload successfully
- [ ] Analysis completes
- [ ] Results display correctly
- [ ] Layout fits screen
- [ ] Touch targets work

**Document issues:** Screenshot + description.

---

### Step 3: B1 Scenario on Web (30 min)

**Test B1 on HF Spaces:**
1. Upload D12, D05, D06, D13
2. Run analysis
3. Verify: 4 satisfied

**This is the backup demo if mobile fails.**

---

## Afternoon: Support (1pm–5pm)

### Step 4: Stand By for Agent 1/2 (2 hours)

**Be available for:**
- API questions
- Cloud fallback testing
- Debugging help

**If mobile pipeline fails:**
- Help diagnose (logs, error messages)
- Confirm cloud fallback works
- Document workarounds

---

### Step 5: Documentation (1 hour)

**Update:**
- `web_demo/README.md` with current status
- API documentation if changes made
- Known limitations (cold start, etc.)

---

### Step 6: Coordinate with Agent 4 (1 hour)

**If mobile demo not ready:**
- Prepare web demo for recording
- Test B1 flow on desktop
- Be ready to screenshare

**Web demo recording setup:**
- Browser: Chrome or Safari
- Resolution: 1920×1080
- Clean desktop (no notifications)

---

## Success Criteria (EOD Friday)

### Green
- [ ] HF Spaces stable and tested
- [ ] Mobile browser tested
- [ ] B1 works on web
- [ ] Supported other agents as needed

### Yellow
- [ ] HF Spaces works
- [ ] Minor mobile issues found
- [ ] Action: Document for Week 3 fix

### Red
- [ ] HF Spaces down
- [ ] Action: Emergency restart, notify team

---

## Key Reminder

**You're the safety net.** If on-device mobile fails, your web demo is the backup.

Keep it warm, keep it working.

---

## Friday Definition of Done

**For Agent 3:**
- [ ] HF Spaces verified working
- [ ] Mobile browser tested
- [ ] Available as backup demo

**For CivicLens Week 2:**
- [ ] Fallback option secured
- [ ] Team supported
- [ ] Ready for Week 3 improvements
