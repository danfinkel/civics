# CivicLens — Video Script

**Duration:** 3 minutes  
**Target Audience:** Hackathon judges, general public  
**Tone:** Professional, empathetic, clear  
**Language:** Plain English, no jargon

---

## Final Script

### 0:00–0:30 — The Problem

**Visual:** Text animation on dark background. Simple, no music yet.

**Audio:**
> "Every year, families applying for SNAP benefits or enrolling children in school face the same challenge: gathering the right documents, by the right deadline, in the right combination. Miss a requirement and you start over. The instructions exist — but understanding whether what you have is what is needed requires expertise most families don't have access to."

**Notes:** 
- Slow pacing, let the problem sink in
- Show text: "SNAP benefits" → "School enrollment" → "Right documents" → "Right deadline"

---

### 0:30–1:00 — Our Approach

**Visual:** Split screen. Left: spike methodology diagram. Right: document images (pay stub, lease, birth certificate).

**Audio:**
> "Before building, we spent a week rigorously testing whether Gemma 4 could reliably handle civic documents — pay stubs, leases, government notices, birth certificates. We ran over 100 experiments, measured failure modes, and designed the product around what we learned."

**Notes:**
- Show the 16 synthetic documents from the spike
- Brief flash of experiment results (classification 100%, mapping 85.9%)
- Transition to app demo at 0:58

---

### 1:00–2:15 — Demo (Track B)

**Visual:** Screen recording of CivicLens app on phone. Real-time usage.

**Audio:**
> "Here's how it works. A family uploads their documents: birth certificate, lease agreement, utility bill, immunization record. CivicLens processes everything on the device using Gemma 4. In under a minute, it shows all four requirements satisfied."

**[Pause for visual: Show all green checkmarks]**

> "Now watch what happens when something's wrong. Swap the utility bill for a second lease — CivicLens flags the duplicate category violation. Two leases count as one proof. The family knows to bring a different document."

**Notes:**
- B1 scenario (1:00–1:45): Smooth, happy path
- B4 scenario (1:45–2:15): Show the warning banner clearly
- Emphasize the plain-language summary

**Screen Recording Steps (B1):**
1. Home screen → Tap "School Enrollment"
2. Upload D12 (birth certificate) to "Proof of Age"
3. Upload D05 (lease) to "Residency Proof 1"
4. Upload D06 (utility bill) to "Residency Proof 2"
5. Upload D13 (immunization) to "Immunization Record"
6. Tap "Check My Packet"
7. Show loading: "Analyzing your documents..."
8. Results screen: All 4 green "Satisfied"
9. Highlight: "Your registration packet looks complete!"

**Screen Recording Steps (B4):**
1. Tap "Start Over"
2. Re-upload D12, D05
3. Upload D14 (second lease) to "Residency Proof 2"
4. Upload D13
5. Tap "Check My Packet"
6. Results screen: All satisfied BUT amber warning banner
7. Highlight: "Two leases count as one proof"

---

### 2:15–2:45 — Privacy Architecture

**Visual:** Architecture diagram. Phone → Blur Detection → Gemma 4 E2B → Results. No cloud icon. Animated line shows data staying on device.

**Audio:**
> "Every document is processed entirely on device using Gemma 4 E2B. Nothing is uploaded. For a resident submitting a birth certificate and a state ID, that matters."

**Notes:**
- Show the 4-box diagram from presentation template
- Emphasize "Nothing is uploaded"
- Show lock icon or privacy shield

---

### 2:45–3:00 — Call to Action

**Visual:** CivicLens app icon on phone. Fade to logo.

**Audio:**
> "CivicLens. Documents stay on your phone. Help gets to the people who need it."

**Notes:**
- End on logo: "CivicLens" + tagline
- Hold for 3 seconds
- Fade to black

---

## Timing Summary

| Section | Time | Duration |
|---------|------|----------|
| The Problem | 0:00–0:30 | 30 sec |
| Our Approach | 0:30–1:00 | 30 sec |
| Demo B1 (Happy Path) | 1:00–1:45 | 45 sec |
| Demo B4 (Warning) | 1:45–2:15 | 30 sec |
| Privacy Architecture | 2:15–2:45 | 30 sec |
| Call to Action | 2:45–3:00 | 15 sec |
| **Total** | | **2:50** |

---

## Reading Notes

**Pacing:**
- Problem section: Slow, deliberate
- Approach section: Conversational
- Demo section: Energetic but clear
- Privacy section: Serious, trustworthy
- CTA: Confident, memorable

**Emphasis Words:**
- "right documents, right deadline, right combination"
- "over 100 experiments"
- "on the device" / "on your phone"
- "Nothing is uploaded"
- "Documents stay on your phone"

**Avoid:**
- Technical jargon ("inference", "multimodal", "E2B")
- Speaking too fast during demo
- Sounding like a sales pitch

---

## Recording Checklist

- [ ] Read through script aloud (timing: ~2:50)
- [ ] Mark breath points in script
- [ ] Practice demo sections with actual app
- [ ] Test microphone levels
- [ ] Record in quiet environment
- [ ] Have water nearby
- [ ] Do 2-3 takes of each section

---

## Alternate Versions

### Short Version (60 seconds)

> "Families applying for benefits face a document challenge: gathering the right papers, by the deadline, in the right combination. CivicLens helps. Upload your documents — birth certificate, lease, utility bill. Our app checks them using on-device AI. All requirements satisfied? You're ready. Something wrong? You'll know what to fix. CivicLens. Documents stay on your phone. Help gets to the people who need it."

### Extended Version (With Team Intro)

Add after "Our Approach":
> "We're a team of [X] developers, designers, and researchers who believe that privacy-preserving AI can make government services more accessible."

---

**Script Version:** 1.0  
**Last Updated:** April 7, 2026  
**Status:** Ready for recording
