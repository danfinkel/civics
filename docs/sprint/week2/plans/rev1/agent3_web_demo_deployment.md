# Agent 3 — Week 2 Work Plan
## Web Demo Deployment + Polish

**Agent:** Agent 3 (Web Demo - Hugging Face Spaces)  
**Sprint:** Week 2 (April 14–18, 2026)  
**Goal:** Deploy to Hugging Face Spaces with stable URL. Mobile browser tested. Cloud fallback API ready for Agent 2.

---

## Dependencies

- **Agent 2:** Needs cloud fallback endpoint by Thursday
- **HF Token:** Required for deployment (user to provide)

---

## Deliverables

### 1. Hugging Face Spaces Deployment

**Prerequisites:**
- Hugging Face account with token
- Git installed locally

**Files to prepare:**

`web_demo/README.md` (update):
```markdown
# CivicLens Web Demo

Privacy-first civic document intelligence using Gemma 4 E4B.

## Demo URL
https://huggingface.co/spaces/{username}/civiclens

## Local Development
```bash
pip install -r requirements.txt
python app.py
```

## API Usage
See API documentation for mobile fallback integration.
```

**Deployment Steps:**

1. Create Space on Hugging Face:
   - Name: `civiclens`
   - SDK: Docker
   - Hardware: CPU (or GPU if available)

2. Configure `web_demo/Dockerfile`:
```dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    poppler-utils \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY requirements_hf.txt requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY . .

# Download model (if using HF Transformers)
# Or configure Ollama connection

EXPOSE 7860

CMD ["python", "app.py"]
```

3. Deploy:
```bash
cd web_demo
python deploy.py  # Or use git push to Space
```

**Verification:**
- [ ] Space builds successfully
- [ ] App launches without errors
- [ ] Track A and Track B tabs work
- [ ] File upload works for PDF and images
- [ ] Results display correctly

---

### 2. Mobile Browser Testing

**Test Matrix:**

| Device | Browser | Test |
|--------|---------|------|
| iPhone 13+ | Safari | Upload, analysis, results |
| iPhone 13+ | Chrome | Upload, analysis, results |
| Android Pixel | Chrome | Upload, analysis, results |

**Mobile-Specific Issues to Check:**
- File picker works (camera + gallery)
- Layout fits 390px width
- Text is readable (16px minimum)
- Buttons are tappable (48px minimum)
- Loading states visible

**Fixes needed in `web_demo/app.py`:**
```python
# Add viewport meta tag for mobile
gr.HTML("""
<meta name="viewport" content="width=device-width, initial-scale=1.0">
""")

# Ensure touch targets are large enough
CUSTOM_CSS += """
.gr-button {
    min-height: 48px !important;
    min-width: 48px !important;
}
"""
```

---

### 3. Cloud Fallback API for Agent 2

**New file:** `web_demo/api.py`

Agent 2 needs an HTTP endpoint for mobile cloud fallback. Create a simple API alongside the Gradio UI.

```python
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import List, Optional
import base64

from inference import run_track_a, run_track_b

app = FastAPI()

class AnalyzeRequest(BaseModel):
    track: str  # "a" or "b"
    prompt: str
    images: List[str]  # base64 encoded

class AnalyzeResponse(BaseModel):
    success: bool
    parsed: Optional[dict]
    raw_response: str
    error: Optional[str]

@app.post("/analyze", response_model=AnalyzeResponse)
async def analyze(request: AnalyzeRequest):
    """Analyze documents via cloud API for mobile fallback."""
    try:
        # Decode base64 images to temp files
        # Call run_track_a or run_track_b
        # Return structured response
        pass
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# Mount Gradio app
from app import demo
app = gr.mount_gradio_app(app, demo, path="/")
```

**API Documentation for Agent 2:**

```markdown
## Cloud Fallback API

Endpoint: `POST https://{username}-civiclens.hf.space/analyze`

Request:
{
  "track": "b",
  "prompt": "You are helping a family...",
  "images": ["base64encodedstring1", "base64encodedstring2"]
}

Response:
{
  "success": true,
  "parsed": {
    "requirements": [...],
    "family_summary": "..."
  },
  "raw_response": "...",
  "error": null
}
```

**CORS Configuration:**
```python
from fastapi.middleware.cors import CORSMiddleware

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Restrict in production
    allow_methods=["POST"],
    allow_headers=["*"],
)
```

---

### 4. Track B Scenario Verification

Test all B1-B8 scenarios on deployed web demo:

| Scenario | Documents | Expected Result | Status |
|----------|-----------|-----------------|--------|
| B1 | D12 + D05 + D06 + D13 | 4 satisfied | [ ] |
| B2 | D12 + D05 + D06 (no immunization) | Missing immunization | [ ] |
| B4 | D12 + D05 + D14 + D13 | Duplicate category warning | [ ] |
| B5 | D12 + D05 (Spanish) + D06 + D13 | All satisfied | [ ] |
| B6 | D12 + host affidavit + D06 + D13 | All satisfied | [ ] |
| B7 | D12 + D05 + D07 (phone) + D13 | D07 questionable | [ ] |
| B8 | D09 only | All 4 missing | [ ] |

**Document Mapping:**
- D12 = birth certificate
- D05 = lease agreement
- D06 = utility bill
- D13 = immunization record
- D14 = second lease (for duplicate test)
- D07 = phone bill
- D09 = state ID

---

## File Changes

```
web_demo/
├── app.py                    # MODIFY: mobile viewport, CSS
├── api.py                    # NEW: cloud fallback API
├── Dockerfile                # MODIFY: production-ready
├── requirements_hf.txt       # MODIFY: add fastapi, uvicorn
├── deploy.py                 # MODIFY: deployment automation
└── README.md                 # MODIFY: add API docs
```

---

## Daily Checkpoints

| Day | Target |
|-----|--------|
| Monday | HF Spaces account setup, Dockerfile ready |
| Tuesday | Deploy to HF Spaces, verify build |
| Wednesday | Mobile browser testing, fixes |
| Thursday | Cloud fallback API complete, hand off to Agent 2 |
| Friday | B1-B8 scenario verification, documentation |

---

## Acceptance Criteria

- [ ] Public HF Spaces URL working and stable
- [ ] Track A and Track B fully functional on web
- [ ] Mobile browser tested (iPhone Safari, Android Chrome)
- [ ] Cloud fallback API endpoint documented and working
- [ ] CORS configured for mobile app access
- [ ] All B1-B8 scenarios verified on deployed instance
- [ ] API documentation delivered to Agent 2

---

## Notes

- Keep the Space warm: if cold start is slow, consider a scheduled ping
- Monitor HF Spaces logs for errors
- Coordinate API contract with Agent 2 early in the week
- Document any HF-specific quirks in README.md
