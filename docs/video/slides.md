# CivicLens — Video Presentation Slides

**Purpose:** Optional title cards and transitions for video  
**Date:** April 7, 2026  
**Agent:** Agent 4

---

## Slide Overview

These slides supplement the screen recordings. Use for:
- Opening title card
- Section transitions
- Architecture diagrams
- Closing branding

---

## Slide 1: Title Card

**Duration:** 3 seconds  
**Placement:** Video opening (0:00–0:03)

### Visual Design

**Background:**
- Solid dark navy `#002444`
- Or subtle gradient to `#1A3A5C`

**Text Elements:**

| Element | Text | Font | Size | Color | Position |
|---------|------|------|------|-------|----------|
| Logo | "CivicLens" | Inter | 72pt | White `#FFFFFF` | Center, upper half |
| Tagline | "Privacy-First Civic Document Intelligence" | Inter | 32pt | White/90% opacity | Center, below logo |
| Event | "Gemma 4 Good Hackathon" | Inter | 18pt | White/70% opacity | Bottom center |

**Animation:**
- Fade in from black (0.5 seconds)
- Hold for 2 seconds
- Fade out or cut to problem section

**Audio:**
- None, or subtle ambient tone
- First narration starts after fade

---

## Slide 2: Problem Statement (Text Animation)

**Duration:** 30 seconds  
**Placement:** 0:00–0:30 (replaces or supplements live footage)

### Visual Design

**Background:**
- Dark navy `#002444`
- Or textured paper/document aesthetic

**Text Animation Sequence:**

| Time | Text Appears | Style |
|------|--------------|-------|
| 0:00 | "Every year, families applying for" | Fade in |
| 0:03 | "SNAP benefits" | Highlight/underline |
| 0:05 | "or enrolling children in" | Fade in |
| 0:07 | "school" | Highlight |
| 0:09 | "face the same challenge:" | Fade in |
| 0:12 | "gathering the right documents," | Fade in, bullet style |
| 0:15 | "by the right deadline," | Fade in |
| 0:18 | "in the right combination." | Fade in |
| 0:22 | "Miss a requirement and you start over." | Fade in, emphasis |

**Typography:**
- Main text: 36pt, Inter, white
- Highlighted terms: 40pt, bold, accent color
- Accent options: `#10B981` (green) or `#F59E0B` (amber)

**Icons (optional):**
- Document icon
- Calendar/clock icon
- Checklist icon
- Warning icon

---

## Slide 3: Spike Methodology

**Duration:** 30 seconds  
**Placement:** 0:30–1:00

### Visual Design

**Layout:** Split screen

**Left Side (40%):**
- Title: "Our Approach"
- Subtitle: "5-Day Feasibility Spike"
- Bullet points:
  - "16 synthetic documents"
  - "100+ inference experiments"
  - "Measured failure modes"
  - "Evidence-driven design"

**Right Side (60%):**
- Grid of document thumbnails (D01–D16)
- Or: Bar chart showing accuracy results:
  - Classification: 100%
  - Category Mapping: 85.9%
  - JSON Reliability: 100%

**Color Scheme:**
- Background: White `#FFFFFF`
- Text: Dark navy `#002444`
- Accents: Success green `#10B981`

---

## Slide 4: Architecture Diagram

**Duration:** 30 seconds  
**Placement:** 2:15–2:45

### Visual Design

**Background:**
- Light surface `#F7F9FB`

**Diagram:** Horizontal flow, center-aligned

```
┌─────────────┐      ┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│   📱 Phone  │  →   │   🔍 Blur   │  →   │  🧠 Gemma   │  →   │   ✅ Results │
│   Camera    │      │  Detection  │      │   4 E2B     │      │             │
└─────────────┘      └─────────────┘      └─────────────┘      └─────────────┘
     Light blue           White              Green tint           White
     #EFF6FF            #FFFFFF            #F0FDF4            #FFFFFF
```

**Box Specifications:**
- Size: 200×150px
- Border: 2px solid `#1A3A5C`
- Border radius: 4px
- Text: 20pt, Inter, centered
- Icon: 48px, above text

**Arrow Specifications:**
- Color: `#002444`
- Thickness: 3px
- Arrowhead: Solid triangle

**Caption:**
- Text: "On-device inference pipeline — documents never leave the phone"
- Position: Below diagram, centered
- Style: 24pt, Inter, `#64748B` (neutral gray)

**Privacy Emphasis:**
- Lock icon 🔒 next to caption
- Or: "No cloud" symbol with strikethrough

---

## Slide 5: Closing Card

**Duration:** 5 seconds  
**Placement:** 2:45–3:00 (end of video)

### Visual Design

**Background:**
- Dark navy `#002444`
- Or app screenshot blurred as background

**Text Elements:**

| Element | Text | Font | Size | Color |
|---------|------|------|------|-------|
| Logo | "CivicLens" | Inter | 72pt | White |
| Tagline | "Documents stay on your phone." | Inter | 32pt | White |
| Sub-tagline | "Help gets to the people who need it." | Inter | 24pt | White/80% |

**App Icon:**
- Centered above or below text
- 120×120px
- CivicLens logo (document with checkmark)

**Animation:**
- Fade in from demo footage
- Hold for 4 seconds
- Fade to black

---

## Optional: Transition Slides

### Section Divider

**Duration:** 1 second  
**Usage:** Between major sections

**Design:**
- Full screen dark navy `#002444`
- Section title centered: "The Demo" or "Privacy First"
- 48pt, white, Inter bold
- Wipe or fade transition

### Lower Third (During Demo)

**Duration:** Throughout demo section  
**Usage:** Identify what's being shown

**Design:**
- Position: Bottom 10% of screen
- Background: Dark navy at 80% opacity
- Text: "Scenario: Complete Valid Packet" or "Scenario: Duplicate Category Warning"
- 24pt, white, Inter

---

## Technical Specifications

### Export Settings

**For Video Editing:**
- Format: PNG sequence or MOV with alpha
- Resolution: 1920×1080 (1080p)
- Frame rate: 30fps
- Color space: sRGB

**Direct to Video:**
- Import slides into editing software
- Set duration per slide
- Add transitions (fade recommended)

### Font Requirements

**Required Font:** Inter
- Download: https://fonts.google.com/specimen/Inter
- Weights needed: 400 (Regular), 600 (Semi-bold), 700 (Bold)

### Color Reference

```css
:root {
  --primary: #002444;
  --primary-container: #1A3A5C;
  --surface: #F7F9FB;
  --success: #10B981;
  --warning: #F59E0B;
  --white: #FFFFFF;
  --neutral: #64748B;
}
```

---

## Creation Options

### Option 1: Stitch Export

Use existing Stitch presentation templates:
- Title Slide: `eed0db9d386e4c08a5cc3734a8471ec8`
- Content Slide: `509d24e09e394ed29289100b4697870c`
- Architecture Slide: `ae4e9224236743a1b7de8478122b11e5`

Export as PNG screenshots or HTML.

### Option 2: Google Slides

1. Use CivicLens template from `/docs/design/presentation_templates.md`
2. Export slides as PNG (File → Download → PNG)
3. Import to video editor

### Option 3: PowerPoint

1. Use CivicLens template from setup guide
2. Export as PNG (File → Save As → PNG)
3. Import to video editor

### Option 4: Design Software

Use Figma, Sketch, or Adobe XD with CivicLens design system:
- Import color palette
- Use Inter font
- Export at 1920×1080

---

## Slide Timing Summary

| Slide | Duration | Cumulative |
|-------|----------|------------|
| Title Card | 3 sec | 0:00–0:03 |
| Problem Statement | 30 sec | 0:00–0:30 |
| Spike Methodology | 30 sec | 0:30–1:00 |
| Demo B1 (Screen Recording) | 45 sec | 1:00–1:45 |
| Demo B4 (Screen Recording) | 30 sec | 1:45–2:15 |
| Architecture Diagram | 30 sec | 2:15–2:45 |
| Closing Card | 5 sec | 2:45–3:00 |
| **Total** | **~3:00** | |

---

## Notes for Video Editor

- Keep transitions simple (fade or cut)
- Maintain consistent timing with narration
- Screen recordings should fill most of the frame
- Slides are supplements, not primary content
- Use CivicLens color scheme throughout

---

**Document Version:** 1.0  
**Last Updated:** April 7, 2026  
**Status:** Ready for production
