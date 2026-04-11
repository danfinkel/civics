# CivicLens — Week 3 Status (Monday–Tuesday)

**Report for:** Project management  
**Sprint:** Week 3 (April 14–18, 2026)  
**Scope:** Agent 1 track — dev workflow + resident-facing copy  
**Period covered:** Monday Apr 14 – Tuesday Apr 15, 2026  
**Overall status:** **Green** — planned Mon/Tue items for this track are **done**.

---

## Executive summary

We shipped a **repeatable iOS dev loop** (build, model config, optional model push, attach) and **cleaned resident-facing results** so demos no longer show raw model tokens, evidence excerpts, or confidence chrome unless the app is built in **eval mode** (`./scripts/dev_deploy.sh --eval` → `EVAL_MODE=true`).

That gives us a **clear split**: production-style builds for stakeholders and **eval builds** for model QA and engineering, without maintaining two codebases.

---

## Monday — Dev workflow scripts

| Deliverable | Status | Notes |
|-------------|--------|--------|
| **`mobile/scripts/dev_deploy.sh`** | Done | Writes `lib/core/config/model_config.dart`, hash-based `flutter clean`, debug/release, **`--eval`** (`--dart-define=EVAL_MODE=true`), optional `--install`, `--attach-only`, `--push-model`, `--bump-build`; end-of-run summary |
| **`mobile/scripts/serve_model.sh`** | Done | HTTP serve GGUF + **`/health`** for sanity checks |
| **`mobile/scripts/sync_test_assets.sh`** | Done | Demo asset checklist + guidance when auto-sync is not available |
| **`mobile/scripts/README.md`** | Done | Blessed sequence: Xcode Profile/Release for cold start, iteration loop, **`--eval`** documented (eval flag vs device install called out) |
| **Repo hygiene** | Done | `.gitignore` updated for generated `model_config` / `.pubspec_hash` as planned |

**PM takeaway:** Engineers can follow one README path from “fresh clone” to “phone + model + attach.” Default script behavior **skips CLI install** on purpose (Xcode Run is the reliable path on some setups); **`--install`** is available when automation needs it.

---

## Tuesday — Static analysis + resident-facing labels

| Deliverable | Status | Notes |
|-------------|--------|--------|
| **String / label mapping** | Done | Central **`LabelFormatter`** in `mobile/lib/core/utils/label_formatter.dart` (plan referenced `shared/utils`; **core** avoids circular imports with result models) |
| **`EVAL_MODE` / `kEvalMode`** | Done | `mobile/lib/core/utils/eval_mode.dart` — `bool.fromEnvironment('EVAL_MODE')` |
| **Track A results** | Done | Friendly requirement names, status chips, no raw `MISSING`; **evidence + confidence badge only when `kEvalMode`** |
| **Track B results** | Done | **`RequirementRow`**: friendly titles/subtitles; evidence, notes, **confidence badge** gated on eval; softer **MET** chip; status copy from formatter |
| **Track B compliance card** | Done | Resident builds: **“Checklist”** headline instead of confidence-derived lines (“Strong alignment”, etc.) |
| **Duplicate banner** | Done | Raw explanations (e.g. `same_residency_category_duplicate`) mapped to human text |
| **Share text (`TrackBResult.toShareableText`)** | Done | Friendly labels; **matched/evidence lines only in eval builds** |
| **`flutter analyze`** | Done | **Changed production `lib/` paths analyze clean**; full-repo analyze still reports pre-existing issues in tests/integration_test/packages (unchanged this sprint) |

**PM takeaway:** Demo screenshots and resident flows should read like a product, not a JSON debugger. Technical detail remains available when explicitly building for evaluation.

---

## Dependencies and handoffs

- **Agent 2 / eval automation:** `dev_deploy.sh --eval` is **feasible and wired** in the app. What may still need a human (any week) is **device install** (signing, `devicectl`, or preference for Xcode Run) — not the eval flag itself. Documented in `mobile/scripts/README.md`.
- **Wednesday (next):** Widget tests for Track A/B results (per plan), further Track A polish.

---

## Risks (low)

| Risk | Mitigation |
|------|------------|
| Stakeholder expects eval-only fields on a default build | Use a **non–eval** build for PM/stakeholder demos; use **`--eval`** only for QA. |
| Full `flutter analyze` noise in CI | Treat **user-facing `lib/`** as the gate for this workstream; schedule cleanup of integration_test / vendored packages separately if needed. |

---

## Appendix — Key paths

| Area | Path |
|------|------|
| Deploy / eval script | `mobile/scripts/dev_deploy.sh` |
| Script docs | `mobile/scripts/README.md` |
| Eval flag (Dart) | `mobile/lib/core/utils/eval_mode.dart` |
| Copy mapping | `mobile/lib/core/utils/label_formatter.dart` |
