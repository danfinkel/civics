# CivicLens Prism Design Migration Specification

**Document Type:** Migration Guide  
**Date:** April 9, 2026  
**From:** Original CivicLens Design  
**To:** Prism Design System  
**Scope:** Mobile App (Flutter) and Web Demo

---

## Overview

This document provides a detailed specification for migrating the CivicLens application from the original "CivicLens Institutional" design to the updated "Prism" design system. The Prism design maintains the same core color tokens while adopting **Civic Prism** typography (Space Grotesk + Public Sans per Stitch design-system assets), plus refined visual styling, improved hierarchy, and enhanced component patterns.

**Key Principle:** Migration should be additive where possible—existing functionality remains intact while visual layers are enhanced.

---

## Design Philosophy Changes

### Original Design
- "The Digital Archivist" — institutional, government-appropriate
- Flat, minimal aesthetic
- Ghost borders and subtle separation
- Conservative use of color

### Prism Design
- "Transparent Confidence" — honest about AI capabilities
- Layered, prismatic visual metaphor
- Enhanced depth through subtle gradients and shadows
- Strategic color usage for wayfinding
- Focus on trust through transparency

---

## Screen Mapping

| Screen | Original ID | Prism ID | Migration Priority |
|--------|-------------|----------|-------------------|
| Home / Track Selection | `c45e3e74b70d464eb8df745348359aa3` | `6826a9a6e6e04cc092eadd1e37be9cbd` | P1 — Entry point |
| School Enrollment Upload | `64df89dce8b443a293f2c7a17d2226bb` | `33383f8ec86f49f99d2d7930e64d8839` | P1 — Core flow |
| Packet Status Results | `8333b3e1e52f49dbb2b2eb19dc6490b7` | `8c33ee3965c4439cb666f3b538b2562d` | P1 — Core flow |
| Reliability Transparency | N/A | `5533357ba8a94d01b3ecaf19fc78ad6f` | P2 — New feature |
| Confidence Indicators | `87cb1fb9bade40f695ca9dd69501aeac` | Same component | P2 — Update styling |

---

## Token Changes

### Unchanged Tokens (Carry Over)

These remain identical between designs:

| Token | Value | Usage |
|-------|-------|-------|
| Primary | `#002444` | Headers, buttons |
| Primary Container | `#1A3A5C` | Cards, navigation |
| Surface | `#F7F9FB` | Backgrounds |
| Success | `#10B981` | High confidence |
| Warning | `#F59E0B` | Medium confidence |
| Error | `#EF4444` | Low confidence |

### New/Modified Tokens

| Token | Original | Prism | Change |
|-------|----------|-------|--------|
| Typography | Inter (Institutional / root theme) | **Space Grotesk** (display, headlines, app bar titles) + **Public Sans** (body, labels, buttons) | Match Stitch **Civic Prism** design-system assets; root `get_project.designTheme` may still list Inter |
| Card Elevation | 0dp (flat) | 2-4dp (subtle shadow) | Add depth |
| Border Radius | 4px uniform | 8-12px variable | Softer corners |
| Gradient Overlays | None | Subtle prism gradients | Visual interest |
| Glassmorphism | None | 90% opacity + blur | Layering |
| Status Badge Style | Pill | Prism crystal shape | Brand identity |

---

## Component Migration Guide

### 1. Cards

**Original (Ghost Card):**
```dart
Container(
  decoration: BoxDecoration(
    color: Colors.white,
    border: Border.all(
      color: outlineVariant.withOpacity(0.2),
      width: 1,
    ),
    borderRadius: BorderRadius.circular(4),
  ),
)
```

**Prism (Elevated Card):**
```dart
Container(
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(12), // Increased
    boxShadow: [
      BoxShadow(
        color: primary.withOpacity(0.08),
        blurRadius: 8,
        offset: Offset(0, 2),
      ),
    ],
  ),
)
```

**Migration Steps:**
1. Increase border radius from 4px to 12px
2. Add subtle shadow (primary color at 8% opacity)
3. Remove ghost border (optional — can keep for definition)
4. Add optional gradient overlay for "prism" effect

---

### 2. Track Selection Cards (Home Screen)

**Original:**
- Flat white cards
- Subtle border
- Arrow icon on right
- Minimal shadow

**Prism:**
- Elevated cards with depth
- Gradient accent on left edge (4px)
- Icon + text layout
- Hover/tap state with increased elevation

**Implementation:**
```dart
// Prism track card
Container(
  margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  decoration: BoxDecoration(
    color: surfaceContainerLowest,
    borderRadius: BorderRadius.circular(16),
    boxShadow: [
      BoxShadow(
        color: primary.withOpacity(0.06),
        blurRadius: 12,
        offset: Offset(0, 4),
      ),
    ],
  ),
  child: ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: Row(
      children: [
        // Prism accent bar
        Container(
          width: 4,
          color: primary, // or category color
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(categoryIcon, color: primary),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: h2Style),
                      Text(subtitle, style: captionStyle),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward, color: primary),
              ],
            ),
          ),
        ),
      ],
    ),
  ),
)
```

---

### 3. Document Upload Slots

**Original:**
- Numbered circles
- Camera + file icons
- Simple checkmark on complete

**Prism:**
- Prism-shaped status indicator
- Document thumbnail with glassmorphism overlay
- Animated progress on upload
- Enhanced blur warning with icon

**Key Changes:**
1. Replace number circles with prism-shaped indicators
2. Add document thumbnail preview
3. Glassmorphism effect on completed documents
4. Animated transitions between states

---

### 4. Status Badges

**Original (Pill):**
- Full rounded corners (12px radius)
- Solid background
- Icon + text

**Prism (Crystal):**
- Asymmetric corners (top-left and bottom-right sharper)
- Gradient background
- Glow effect matching status color
- Icon with subtle animation

**Implementation:**
```dart
// Prism status badge
Container(
  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  decoration: BoxDecoration(
    gradient: LinearGradient(
      colors: [
        statusColor.withOpacity(0.15),
        statusColor.withOpacity(0.05),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    borderRadius: BorderRadius.only(
      topLeft: Radius.circular(4),
      topRight: Radius.circular(12),
      bottomLeft: Radius.circular(12),
      bottomRight: Radius.circular(4),
    ),
    border: Border.all(
      color: statusColor.withOpacity(0.3),
      width: 1,
    ),
  ),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(statusIcon, size: 16, color: statusColor),
      SizedBox(width: 6),
      Text(
        statusLabel,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: statusColor,
        ),
      ),
    ],
  ),
)
```

---

### 5. Results Screen

**Original:**
- Flat list of requirements
- Simple status badges
- Warning banner
- Action summary card

**Prism:**
- Layered card design
- Prism-shaped requirement indicators
- Animated status transitions
- Glassmorphism on summary card
- Enhanced duplicate warning with visual hierarchy

**New Component: Requirement Row (Prism)**
```dart
Container(
  margin: EdgeInsets.only(bottom: 12),
  decoration: BoxDecoration(
    color: surfaceContainerLowest,
    borderRadius: BorderRadius.circular(12),
    boxShadow: [
      BoxShadow(
        color: primary.withOpacity(0.04),
        blurRadius: 8,
        offset: Offset(0, 2),
      ),
    ],
  ),
  child: ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: IntrinsicHeight(
      child: Row(
        children: [
          // Status prism indicator
          Container(
            width: 6,
            color: statusColor,
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(requirementName, style: bodyStyle),
                        SizedBox(height: 4),
                        Text(documentName, style: captionStyle),
                      ],
                    ),
                  ),
                  PrismStatusBadge(status: status),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  ),
)
```

---

## New Screen: Reliability Transparency

**Screen ID:** `5533357ba8a94d01b3ecaf19fc78ad6f`

**Purpose:** Build user trust by transparently communicating AI model capabilities and limitations.

**Components:**
1. **Confidence Meter** — Visual gauge of overall confidence
2. **Capability Cards** — What the model can reliably do
3. **Limitation Cards** — What requires human verification
4. **Learn More Link** — Link to detailed methodology

**Implementation Notes:**
- Access via "About" or info icon on results screen
- Optional: Show on first use as onboarding
- Should not block main user flow

---

## Animation Guidelines

### Prism Design Animations

| Interaction | Animation | Duration | Easing |
|-------------|-----------|----------|--------|
| Card tap | Scale down + shadow increase | 150ms | easeOut |
| Card release | Scale up + shadow decrease | 200ms | easeOutBack |
| Status change | Color transition + prism glow | 300ms | easeInOut |
| Document upload | Progress prism fill | 2000ms | linear |
| Screen transition | Slide + fade | 300ms | easeInOut |
| Loading state | Prism shimmer | 1500ms | linear loop |

### Implementation (Flutter)

```dart
// Prism card with tap animation
class PrismCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  @override
  _PrismCardState createState() => _PrismCardState();
}

class _PrismCardState extends State<PrismCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 150),
        curve: Curves.easeOut,
        transform: Matrix4.identity()
          ..scale(_isPressed ? 0.98 : 1.0),
        decoration: BoxDecoration(
          // Prism styling with animated shadow
          boxShadow: [
            BoxShadow(
              color: primary.withOpacity(_isPressed ? 0.12 : 0.06),
              blurRadius: _isPressed ? 16 : 12,
              offset: Offset(0, _isPressed ? 6 : 4),
            ),
          ],
        ),
        child: widget.child,
      ),
    );
  }
}
```

---

## Migration Checklist

### Phase 1: Foundation (P1 Screens)

- [x] Update card component with Prism styling (`prism_tokens.dart`, `prismCardDecoration`, theme cards/buttons 12px)
- [x] Implement elevated shadows
- [x] Update border radius tokens (4px → 12px)
- [x] Migrate Home screen (`6826a9a6e6e04cc092eadd1e37be9cbd`) — `_PrismTrackCard` in `main.dart`
- [x] Migrate Upload screen (`33383f8ec86f49f99d2d7930e64d8839`) — `track_b_screen.dart` upload chrome, `document_slot.dart`
- [x] Migrate Results screen (`8c33ee3965c4439cb666f3b538b2562d`) — hero, checklist header, `requirement_row`, summary glass card
- [x] Update status badges to crystal shape — `CrystalStatusBadge`, `ConfidenceBadge`, `PrismSlotStep`
- [x] Add tap animations — home track cards (scale + shadow)

### Phase 2: Enhancement (P2 Features)

- [x] Implement Reliability Transparency screen (content + Prism section cards — `model_transparency_screen.dart`; full “meter / capability cards” still optional)
- [x] Add shimmer loading states — `prism_shimmer.dart` on app boot, Track B analysis card (`track_b_screen.dart`, `main.dart`)
- [x] Implement screen transition animations — `prism_page_routes.dart` (slide+fade push; fade replace from onboarding)
- [x] Add document upload progress animation — slot `LinearProgressIndicator` while capture runs; `AnimatedSwitcher` empty→preview (`document_slot.dart`)
- [x] Update Confidence Indicators styling — stronger gradient, border, status glow (`confidence_badge.dart`)
- [x] Add glassmorphism effects — verified thumbnail `BackdropFilter` + frost gradient (`document_slot.dart`); hero already has blur
- [x] Implement prism-shaped indicators — hex prism step + animated check (`prism_slot_step.dart`)

### Phase 3: Polish

- [ ] Performance optimization (shadows, animations)
- [ ] Accessibility audit (reduced motion support)
- [ ] Dark mode consideration (if applicable)
- [ ] Cross-screen consistency check
- [ ] User testing with Prism design

---

## File Structure

```
lib/
├── core/
│   └── theme/
│       ├── app_colors.dart              # Unchanged
│       ├── app_typography.dart          # Unchanged
│       └── prism_shadows.dart           # NEW: Shadow definitions
├── shared/
│   └── widgets/
│       ├── cards/
│       │   ├── ghost_card.dart          # Original (keep)
│       │   └── prism_card.dart          # NEW: Prism variant
│       ├── badges/
│       │   ├── pill_badge.dart          # Original (keep)
│       │   └── crystal_badge.dart       # NEW: Prism variant
│       └── indicators/
│           ├── prism_indicator.dart     # NEW: Prism shape
│           └── shimmer_loading.dart     # NEW: Loading animation
└── features/
    └── reliability/                     # NEW: Transparency feature
        ├── reliability_screen.dart
        └── widgets/
```

---

## Backward Compatibility

**Strategy:** Component coexistence

- Keep original components as `GhostCard`, `PillBadge`
- Add Prism variants as `PrismCard`, `CrystalBadge`
- Use feature flag or theme mode to switch between designs
- Gradual migration screen-by-screen

**Feature Flag Example:**
```dart
class DesignSystem {
  static bool get usePrismDesign => 
    const bool.fromEnvironment('USE_PRISM', defaultValue: false);
}

// Usage
DesignSystem.usePrismDesign 
  ? PrismCard(child: content)
  : GhostCard(child: content);
```

---

## Testing Considerations

### Visual Regression
- Screenshot comparison between original and Prism
- Verify all status colors render correctly
- Check shadow rendering on different devices

### Performance
- Measure frame drops during animations
- Test on lower-end devices
- Verify reduced motion accessibility

### Accessibility
- Ensure screen readers handle new shapes
- Test with high contrast mode
- Verify touch targets remain 48px minimum

---

## Reference Materials

- **Stitch Project:** https://stitch.google.com/projects/7798513403930064434
- **Original Design Spec:** `/docs/design/civiclens_design_specs.md`
- **Prism Screens:**
  - Home: `6826a9a6e6e04cc092eadd1e37be9cbd`
  - Upload: `33383f8ec86f49f99d2d7930e64d8839`
  - Results: `8c33ee3965c4439cb666f3b538b2562d`
  - Reliability: `5533357ba8a94d01b3ecaf19fc78ad6f`

---

## Questions for Implementation

1. Should Prism design be the default or opt-in for this release?
2. Do we need to support both designs simultaneously (A/B testing)?
3. What's the timeline for full migration?
4. Are there any performance constraints on target devices?

---

**Document Version:** 1.0  
**Last Updated:** April 9, 2026  
**Status:** Ready for implementation review
