# Agent 1 — Week 3 Plan: Wednesday-Friday

**Scope:** Widget tests, Track A polish, human walkthrough, final fixes  
**Goal:** Demo-ready app by Friday with all P0/P1 issues resolved

---

## Wednesday: Widget Tests + Track A Polish

### Morning (3 hours)
**Write widget tests**

Create `mobile/test/widget/track_a_results_test.dart`:

```dart
void main() {
  testWidgets('Track A results shows deadline prominently', (tester) async {
    final mockResult = TrackAResult(
      noticeSummary: NoticeSummary(
        requestedCategories: ['earned_income'],
        deadline: 'April 15, 2026',
        consequence: 'case_closure',
      ),
      proofPack: [
        ProofPackItem(
          category: 'earned_income',
          matchedDocument: 'D03',
          assessment: AssessmentLabel.likelySatisfies,
          confidence: ConfidenceLevel.high,
          evidence: '',
          caveats: '',
        ),
      ],
      actionSummary: 'Your pay stub appears to cover what DTA is asking for.',
    );
    
    await tester.pumpWidget(
      MaterialApp(home: TrackAResultsScreen(result: mockResult)),
    );
    
    // Deadline must be visible
    expect(find.text('April 15, 2026'), findsWidgets);
    
    // No technical labels visible
    expect(find.text('likely_satisfies'), findsNothing);
    expect(find.text('high'), findsNothing);
    
    // Action summary visible
    expect(find.textContaining('pay stub appears to cover'), findsOneWidget);
  });

  testWidgets('Track A results shows MISSING item in red', (tester) async {
    final mockResult = TrackAResult(
      noticeSummary: NoticeSummary(
        requestedCategories: ['earned_income'],
        deadline: 'April 15, 2026',
        consequence: 'case_closure',
      ),
      proofPack: [
        ProofPackItem(
          category: 'earned_income',
          matchedDocument: 'MISSING',
          assessment: AssessmentLabel.missing,
          confidence: ConfidenceLevel.low,
          evidence: '',
          caveats: '',
        ),
      ],
      actionSummary: "You're missing 1 required document.",
    );
    
    await tester.pumpWidget(
      MaterialApp(home: TrackAResultsScreen(result: mockResult)),
    );
    
    // MISSING must be displayed with resident-friendly label
    expect(find.text('Not found in your documents'), findsOneWidget);
    expect(find.text('MISSING'), findsNothing); // raw value should not appear
  });
}
```

Create `mobile/test/widget/track_b_results_test.dart`:

```dart
testWidgets('Track B duplicate category shows warning banner', (tester) async {
  final mockResult = TrackBResult(
    requirements: [...],
    duplicateCategoryFlag: true,
    duplicateCategoryExplanation: 'same_residency_category_duplicate',
    familySummary: 'You need a lease AND a different document type.',
  );
  
  await tester.pumpWidget(
    MaterialApp(home: TrackBResultsScreen(result: mockResult)),
  );
  
  // Warning banner must be visible
  expect(find.textContaining('two leases'), findsOneWidget);
  expect(find.textContaining('different'), findsOneWidget);
});
```

Run tests:
```bash
cd mobile && flutter test test/widget/
```

### Afternoon (2 hours)
**Track A deadline banner prominence**

The deadline banner must be the FIRST element after the screen title:

```dart
if (result.noticeSummary.deadline.isNotEmpty &&
    result.noticeSummary.deadline != 'UNCERTAIN')
  Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF3F3),
      border: Border.all(color: const Color(0xFFB71C1C), width: 2),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Respond by ${result.noticeSummary.deadline}',
          style: const TextStyle(
            fontSize: 18, fontWeight: FontWeight.bold,
            color: Color(0xFFB71C1C),
          ),
        ),
        if (result.noticeSummary.consequence.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _formatConsequence(result.noticeSummary.consequence),
              style: const TextStyle(fontSize: 14, color: Color(0xFF555555)),
            ),
          ),
      ],
    ),
  ),
```

**Action summary prominence:**
- Style as a card with slightly larger font than proof pack rows
- This is the most important element — make it visually primary

**MISSING item treatment:**
- Red background (`Color(0xFFFFF3F3)` with border)
- Use `LabelFormatter.assessmentLabel('missing')` → "Not found in your documents"

---

## Thursday: Human Walkthrough

### Setup (15 min)
```bash
./mobile/scripts/sync_test_assets.sh   # ensure test images in Photos
./mobile/scripts/dev_deploy.sh          # fresh install
```

### Walk these 6 flows in order (~60 min)

**FLOW 1: Track A — D01/D03 happy path (the RMV story)**
- [ ] Home screen looks polished, no placeholder text
- [ ] Tap "SNAP Benefits" — navigates correctly
- [ ] Upload D01-degraded.jpg as notice — blur check passes, slot fills
- [ ] Upload D03-degraded.jpg as pay stub — slot fills
- [ ] Tap "Analyze" — processing state visible, not frozen
- [ ] Results: deadline banner is the FIRST thing I see
- [ ] Results: "earned income" row shows green satisfied status
- [ ] Results: no technical labels anywhere on screen
- [ ] Action summary: reads like a knowledgeable friend, not a computer
- [ ] Back/start over navigation works

**FLOW 2: Track A — A3 stale pay stub**
- [ ] Upload D01-degraded.jpg as notice
- [ ] Upload D04-degraded.jpg as stale pay stub
- [ ] Results: income row shows "May not meet this requirement"
- [ ] Caveats mention the date issue
- [ ] Action summary tells me to get a more recent pay stub

**FLOW 3: Track A — A6 blurry notice**
- [ ] Upload D01-blurry.jpg as notice
- [ ] Upload D03-degraded.jpg as pay stub
- [ ] Results: amber "unclear notice" banner visible
- [ ] App does not confidently assert wrong deadline

**FLOW 4: Track B — B1 complete packet**
- [ ] Tap "School Enrollment" from home
- [ ] Upload D12, D05, D06, D13
- [ ] Results: all 4 requirements green
- [ ] No technical labels
- [ ] Family summary is clear

**FLOW 5: Track B — B4 duplicate leases**
- [ ] Upload D12, D05, D14, D13
- [ ] Results: duplicate category warning banner is unmissable
- [ ] Warning explains in plain language: two leases = one category
- [ ] Family summary tells me what to replace

**FLOW 6: Error states**
- [ ] Take a deliberately blurry photo — blur warning appears
- [ ] "Use anyway" override works
- [ ] Try navigating back mid-inference — app handles gracefully

### Document findings

Create `docs/sprint/week3_human_qa.md`:

```markdown
# Week 3 Human QA Findings
Date: [date]
Device: iPhone [model], iOS [version]

## P0 Issues (blocking demo recording)
- [issue description + screenshot filename]

## P1 Issues (visible to judges)
- [issue description + screenshot filename]

## P2 Issues (edge cases)
- [issue description]

## Looks Good
- [things that passed]
```

---

## Friday: Fix Findings + Final Verification

### Morning (3 hours)
**Process human QA findings**

Fix all P0 issues (blocking demo). Fix P1 issues if time permits.

Common issues to watch for:
- Technical labels still visible somewhere
- Deadline banner not first element
- Duplicate warning not prominent enough
- Action summary not styled as primary
- Navigation issues (back/start over)

### Afternoon (2 hours)
**Final verification**

- [ ] `./scripts/dev_deploy.sh` works end-to-end
- [ ] `grep` for technical labels returns 0 results in user-facing code
- [ ] `flutter analyze` returns 0 errors on production `lib/`
- [ ] Widget tests pass
- [ ] All 6 human walkthrough flows pass
- [ ] App is demo-ready for Agent 4 video recording

---

## Acceptance Criteria (Friday EOD)

- [ ] Widget tests pass for Track A results, MISSING item, Track B duplicate flag
- [ ] Human walkthrough completed with documented findings
- [ ] All P0 issues resolved, P1 issues resolved or documented
- [ ] Deadline banner is first element in Track A results
- [ ] Duplicate category banner is unmissable in Track B B4
- [ ] Action summary styled prominently on both results screens
- [ ] `flutter analyze` returns 0 errors on user-facing code
- [ ] App ready to hand off to Agent 4 for video recording
