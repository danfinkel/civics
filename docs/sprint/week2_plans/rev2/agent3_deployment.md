# Agent 3 — Week 2 Revised Plan (Rev 2)
## Deploy + Test + Coordinate

**Agent:** Agent 3 (Web Demo)  
**Date:** April 7, 2026  
**Status:** Code complete — Deployment blocked on HF_TOKEN

---

## What Changed

All code is ready. Only blocker is HF_TOKEN for deployment.

---

## Remaining Week 2 Work

### 1. Deploy to Hugging Face Spaces (Immediate)

**Two options:**

**Option A: Automated (if you have token)**
```bash
export HF_TOKEN="hf_xxx"
cd web_demo
python deploy.py
```

**Option B: Manual (if no token)**
1. Go to https://huggingface.co/spaces
2. Click "Create new Space"
3. Name: `civiclens`
4. SDK: Docker
5. Hardware: CPU (or GPU Basic if available)
6. Clone the Space locally
7. Copy `web_demo/` contents into the cloned repo
8. Push to Hugging Face

**Verify deployment:**
- [ ] Space builds without errors
- [ ] Health check passes: `GET /health`
- [ ] Gradio UI loads
- [ ] Track A and Track B tabs work

---

### 2. Test Cloud Fallback API with Agent 2 (Today/Tomorrow)

**Endpoint to test:** `POST /analyze`

**Test with curl:**
```bash
curl -X POST https://{username}-civiclens.hf.space/analyze \
  -H "Content-Type: application/json" \
  -d '{
    "track": "b",
    "images_base64": ["base64encoded_image_1", "base64encoded_image_2"],
    "document_labels": ["Document 1", "Document 2"]
  }'
```

**Expected response:**
```json
{
  "success": true,
  "parsed": {
    "requirements": [...],
    "family_summary": "..."
  },
  "raw_response": "...",
  "processing_time_ms": 4500
}
```

**Coordinate with Agent 2:**
- Provide the HF Spaces URL
- Test end-to-end from mobile app
- Debug any CORS or API issues

---

### 3. Mobile Browser Testing (Thursday)

**Test matrix:**

| Device | Browser | Test |
|--------|---------|------|
| iPhone 13+ | Safari | Upload, analyze, results |
| Android Pixel | Chrome | Upload, analyze, results |

**Checklist:**
- [ ] File picker opens
- [ ] Images upload successfully
- [ ] Analysis completes
- [ ] Results display correctly
- [ ] Layout fits mobile screen
- [ ] Touch targets work (48px min)

---

### 4. B1-B8 Scenario Verification (Thursday/Friday)

Run all scenarios on deployed instance:

| Scenario | Documents | Expected |
|----------|-----------|----------|
| B1 | D12 + D05 + D06 + D13 | 4 satisfied |
| B4 | D12 + D05 + D14 + D13 | Duplicate warning |
| B7 | D12 + D05 + D07 + D13 | D07 questionable |
| B8 | D09 only | All missing |

**Document sources:** `/spike/artifacts/clean/`

---

## Revised Daily Plan

| Day | Task |
|-----|------|
| **Today** | Deploy to HF Spaces (get token if needed) |
| **Tomorrow** | Test API with Agent 2, fix any issues |
| **Thursday** | Mobile browser testing, B1-B8 verification |
| **Friday** | Keep Space warm, documentation |

---

## Deliverables to Other Agents

**For Agent 2 (needed by Thursday):**
- HF Spaces URL: `https://{username}-civiclens.hf.space`
- Confirm `/analyze` endpoint works
- CORS enabled for mobile app

**For Agent 4 (needed by Thursday):**
- Working web demo URL (backup recording source)
- Confirm B1 and B4 scenarios work

---

## Acceptance Criteria (Revised)

- [ ] Deployed to HF Spaces with stable URL
- [ ] Cloud fallback API tested with Agent 2
- [ ] Mobile browser tested
- [ ] B1-B8 scenarios verified
- [ ] URL delivered to Agents 2 and 4

---

## Notes

- If HF_TOKEN unavailable, manual Space creation works fine
- Keep Space warm with periodic requests if cold start is slow
- Prioritize API functionality for Agent 2 over Gradio polish
