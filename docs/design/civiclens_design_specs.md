# CivicLens Design Specifications

**Agent 4 Deliverable | Week 1 Sprint**
**Project:** CivicLens - Privacy-First Civic Document Intelligence
**Stitch Project ID:** 7798513403930064434

---

## Overview

This document contains the design specifications for the CivicLens mobile application and web demo. All designs have been created using Google Stitch and follow the "CivicLens Institutional" design system.

**Design Principles:**
- Trustworthy & Government-Appropriate: Clean, minimal, no decorative elements
- Accessible & Inclusive: Large touch targets, high contrast, clear hierarchy
- Honest About Limitations: Confidence indicators are prominent
- Plain Language Throughout: Written for residents under stress

---

## Color Palette

### Primary Colors
| Token | Hex | Usage |
|-------|-----|-------|
| Primary | `#002444` | Headers, primary buttons, key actions |
| Primary Container | `#1A3A5C` | Card headers, navigation |
| On Primary | `#FFFFFF` | Text on primary backgrounds |

### Surface Colors
| Token | Hex | Usage |
|-------|-----|-------|
| Surface | `#F7F9FB` | Main app background |
| Surface Container Low | `#F2F4F6` | Secondary content areas |
| Surface Container Lowest | `#FFFFFF` | Cards, input fields |
| Surface Container | `#ECEEF0` | Subtle grouping backgrounds |

### Semantic Status Colors
| Token | Hex | Usage |
|-------|-----|-------|
| Success/High Confidence | `#10B981` | Satisfied, high confidence states |
| Warning/Medium Confidence | `#F59E0B` | Questionable, review recommended |
| Error/Low Confidence | `#EF4444` | Missing, please verify |
| Neutral | `#64748B` | Disabled, optional states |

### Background Variations for Status
| Token | Hex | Usage |
|-------|-----|-------|
| Light Green | `#F0FDF4` | High confidence results |
| Light Amber | `#FFFBEB` | Medium confidence, warnings |
| Light Red | `#FFF3F3` | Low confidence, errors |
| Light Blue | `#EFF6FF` | Action summary cards |

---

## Typography Hierarchy

**Font Family:** Inter (all weights)

| Level | Size | Weight | Line Height | Usage |
|-------|------|--------|-------------|-------|
| H1 | 24px | 700 | 1.3 | Screen titles |
| H2 | 20px | 600 | 1.4 | Section headers |
| Body | 16px | 400 | 1.5 | Primary content |
| Caption | 14px | 400 | 1.5 | Secondary text, labels |
| Small | 12px | 500 | 1.4 | Badges, status indicators |

**Typography Rules:**
- Use tight letter-spacing (-0.02em) for headlines
- Body text (16px) is the minimum for civic instructions
- Every screen must have a clear typographic "Anchor"

---

## Component Specifications

### Buttons

**Primary Button:**
- Background: `#002444` (Primary)
- Text: `#FFFFFF` (On Primary)
- Height: 48px minimum
- Padding: 16px horizontal
- Border Radius: 4px (ROUND_FOUR)
- Font: 16px, weight 600

**Secondary Button (Outline):**
- Background: Transparent
- Border: 1px solid `#73777F` (Outline)
- Text: `#002444` (Primary)
- Height: 48px minimum
- Border Radius: 4px

**Disabled State:**
- Background: `#E0E3E5` (Surface Container Highest)
- Text: `#64748B` (Neutral)

### Cards

**Ghost Card (Standard):**
- Background: `#FFFFFF` (Surface Container Lowest)
- Border: 1px solid `#C3C6CF` at 20% opacity (Ghost Border)
- Border Radius: 4px
- Padding: 16-24px
- No shadows

**Action Summary Card:**
- Background: `#EFF6FF` (Light Blue)
- Border Radius: 4px
- Padding: 20px
- Contains prominent header + body text

### Status Badges

**Pill-shaped badges with icon + text:**
- Height: 24px
- Padding: 4px 12px
- Border Radius: 12px (full round)
- Font: 12px, weight 500

**High Confidence Badge:**
- Background: `#F0FDF4`
- Text/Icon: `#10B981`
- Icon: Checkmark

**Medium Confidence Badge:**
- Background: `#FFFBEB`
- Text/Icon: `#F59E0B`
- Icon: Caution/Warning

**Low Confidence Badge:**
- Background: `#FFF3F3`
- Text/Icon: `#EF4444`
- Icon: X or Alert

### Document Upload Slots

**Structure:**
- Number indicator (1-5)
- Document title
- Required/Optional label
- Two action buttons: Camera icon, File/Library icon
- Status indicator (when completed)

**States:**
- Empty: Gray placeholder icons
- Completed: Thumbnail preview + green checkmark
- Blur Warning: Amber warning icon + "Photo unclear — retake?" text

### Warning Banner

**Duplicate Category Warning:**
- Background: `#FFFBEB` (Light Amber)
- Border Left: 4px solid `#F59E0B`
- Padding: 12px 16px
- Icon: Warning triangle (amber)
- Text: Dark gray, 14px

---

## Screen Specifications

### Screen 1: Home / Track Selection

**Screen ID:** `c45e3e74b70d464eb8df745348359aa3`

**Layout:**
- Header: "CivicLens" (H1, 24px, bold)
- Subtitle: "Document help for Massachusetts residents" (Caption, 14px)
- Two large selection cards
- Footer: "Your documents stay on your device" (Caption, centered)

**Card 1 - SNAP Benefits:**
- Title: "SNAP Benefits" (H2, 20px, weight 600)
- Subtitle: "Check your recertification documents"
- Arrow icon on right
- Full-width, tappable

**Card 2 - School Enrollment:**
- Title: "School Enrollment" (H2, 20px, weight 600)
- Subtitle: "Prepare your BPS registration packet"
- Arrow icon on right
- Full-width, tappable

**Card Styling:**
- Ghost card style (white background, subtle border)
- Padding: 20px
- Margin between cards: 16px

---

### Screen 2: Document Upload (Track B)

**Screen ID:** `64df89dce8b443a293f2c7a17d2226bb`

**Layout:**
- Top App Bar: "School Enrollment Packet" with back arrow
- Progress indicator: "Step 1 of 2: Upload Documents"
- Document slots (5 total)
- Optional toggle for Grade Indicator
- Primary CTA: "Check My Packet"

**Document Slots:**
1. Proof of Age (Required)
2. Residency Proof 1 (Required)
3. Residency Proof 2 (Required)
4. Immunization Record (Required)
5. Grade Indicator (Optional - toggle to show)

**Slot Structure:**
- Number circle (24px, outlined)
- Title (Body, 16px)
- "Required" or "Optional" label (Caption, 12px, color-coded)
- Action buttons row: Camera icon button, File icon button

**Completed State:**
- Thumbnail (48x48px)
- Green checkmark overlay
- "Document Verified" text

**Blur Warning State:**
- Amber warning icon
- Text: "Photo unclear — retake?"
- Retake button visible

**CTA Button:**
- "Check My Packet"
- Primary button style
- Disabled until all required slots filled
- Full-width, 48px height

---

### Screen 3: Results (Track B)

**Screen ID:** `8333b3e1e52f49dbb2b2eb19dc6490b7`

**Layout:**
- Top App Bar: "Packet Status" with back arrow, share button
- Subtitle: "Boston Public Schools Registration"
- Requirements checklist (4 rows)
- Duplicate category warning (conditional)
- Action summary card
- Bottom action buttons

**Requirements Checklist Row:**
- Requirement name (Body, 16px)
- Status badge (pill-shaped, color-coded)
- Matched document name (Caption, 14px, gray)

**Status Variations:**
- Satisfied: Green badge "Satisfied"
- Questionable: Amber badge "Questionable"
- Missing: Gray badge "Missing"

**Duplicate Category Warning Banner:**
- Amber background
- Warning icon
- Text: "Two leases count as one proof — you need a second document type from a different category"

**Action Summary Card:**
- Light blue background (#EFF6FF)
- Header: "What to bring to registration" (H2, 20px, weight 600)
- Body: Plain language instructions (Body, 16px)

**Bottom Buttons:**
- "Start Over" (Secondary/Outline, left)
- "Save Summary" (Primary, right)

---

### Screen 4: Confidence Indicators

**Purpose:** Component reference for inline usage

**Three States:**

1. **High Confidence:**
   - Green checkmark icon
   - Label: "High confidence"
   - Explanation: "The model is confident in this assessment"
   - Background: Light green

2. **Medium Confidence:**
   - Amber caution icon
   - Label: "Review recommended"
   - Explanation: "Please double-check this document"
   - Background: Light amber

3. **Low Confidence:**
   - Red X icon
   - Label: "Please verify"
   - Explanation: "The model cannot clearly read this document"
   - Background: Light red

**Inline Usage:**
- Compact pill badge
- Icon + short label
- Positioned right of document name

---

## Responsive Considerations

**Mobile-First Design:**
- Base width: 390px (iPhone 14 reference)
- All touch targets: 48px minimum
- Single column layout
- Full-width buttons

**Tablet Adaptations:**
- Cards max-width: 600px, centered
- Document slots: Two-column grid possible
- Larger padding (24px)

---

## Accessibility Requirements

**Color Contrast:**
- All text meets WCAG AA (4.5:1 minimum)
- Primary text on white: 7:1 ratio (AAA)
- Status colors maintain contrast on light backgrounds

**Touch Targets:**
- Minimum 48x48px for all interactive elements
- 8px minimum spacing between targets

**Typography:**
- Minimum 16px for body text
- Maximum line length: 60 characters
- Line height: 1.5 minimum

**Icons:**
- All icons have text labels
- Icon + label pattern for clarity

---

## Assets for Development

**Stitch Project:** https://stitch.google.com/projects/7798513403930064434

**Screens:**
1. Home Screen: `c45e3e74b70d464eb8df745348359aa3`
2. Document Upload: `64df89dce8b443a293f2c7a17d2226bb`
3. Results Screen: `8333b3e1e52f49dbb2b2eb19dc6490b7`

**HTML/CSS Export:**
Each screen has downloadable HTML code available via the Stitch project.

---

## Implementation Notes for Agents

### Agent 1 (Flutter Mobile)

**Dependencies:**
```yaml
dependencies:
  flutter:
    sdk: flutter
  google_fonts: ^6.0.0  # For Inter font
```

**Theme Configuration:**
```dart
// Primary color
const Color primaryColor = Color(0xFF002444);
const Color primaryContainer = Color(0xFF1A3A5C);

// Status colors
const Color successColor = Color(0xFF10B981);
const Color warningColor = Color(0xFFF59E0B);
const Color errorColor = Color(0xFFEF4444);
const Color neutralColor = Color(0xFF64748B);

// Background colors
const Color surfaceColor = Color(0xFFF7F9FB);
const Color surfaceContainerLow = Color(0xFFF2F4F6);
const Color surfaceContainerLowest = Color(0xFFFFFFFF);

// Action summary
const Color actionSummaryBackground = Color(0xFFEFF6FF);
```

**Text Styles:**
```dart
const TextStyle h1Style = TextStyle(
  fontFamily: 'Inter',
  fontSize: 24,
  fontWeight: FontWeight.w700,
  letterSpacing: -0.02,
);

const TextStyle h2Style = TextStyle(
  fontFamily: 'Inter',
  fontSize: 20,
  fontWeight: FontWeight.w600,
  letterSpacing: -0.02,
);

const TextStyle bodyStyle = TextStyle(
  fontFamily: 'Inter',
  fontSize: 16,
  fontWeight: FontWeight.w400,
  height: 1.5,
);
```

### Agent 3 (Web Demo)

**CSS Variables:**
```css
:root {
  --primary: #002444;
  --primary-container: #1A3A5C;
  --surface: #F7F9FB;
  --surface-container-low: #F2F4F6;
  --surface-container-lowest: #FFFFFF;
  --success: #10B981;
  --warning: #F59E0B;
  --error: #EF4444;
  --neutral: #64748B;
  --action-summary-bg: #EFF6FF;
}
```

**Gradio-Specific Notes:**
- Use `gr.Blocks()` for custom layouts
- Apply CSS via `css=` parameter
- Status badges: Use `gr.Label()` with color parameter
- Cards: Use `gr.Column()` with background color

---

## Design System Updates

Any changes to these specifications should be:
1. Updated in the Stitch project
2. Documented in this file
3. Communicated to Agent 1 and Agent 3

---

## Deliverables Checklist

- [x] Core color palette defined
- [x] Typography hierarchy documented
- [x] Component specifications created
- [x] Home screen design generated
- [x] Document upload screen design generated
- [x] Results screen design generated
- [x] Confidence indicator component defined
- [x] Design specs delivered to Agent 1 (mobile)
- [x] Design specs delivered to Agent 3 (web)

---

**Next Steps:**
1. Agents 1 and 3 should review this document
2. Reference Stitch project for visual examples
3. Download HTML/CSS from Stitch if needed
4. Implement components following these specifications
5. Request design review when screens are ready
