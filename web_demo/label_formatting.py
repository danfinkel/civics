"""
Resident-facing labels for web demo — aligned with mobile LabelFormatter.
"""

ASSESSMENT_LABELS: dict[str, str] = {
    "likely_satisfies": "Appears to meet this requirement",
    "likely_does_not_satisfy": "May not meet this requirement",
    "insufficient_information": "Unclear — needs review",
    "missing": "Not found in your documents",
    "questionable": "Accepted by some offices — check with yours",
    "residency_ambiguous": "Acceptance varies by office",
    "invalid_proof": "This type of document is not accepted",
    "same_residency_category_duplicate": "Same type as another document you submitted",
    "satisfied": "Looks good",
    "uncertain": "Unclear — needs review",
}

# Track B / proof-pack keys from model may be snake_case or mixed
_REQUIREMENT_KEY_ALIASES: dict[str, str] = {
    "proof_of_age": "Proof of age",
    "residency_proof_1": "Residency proof (1 of 2)",
    "residency_proof_2": "Residency proof (2 of 2)",
    "immunization_record": "Immunization record",
    "grade_indicator": "Grade indicator (if applicable)",
    "earned_income": "Earned income",
    "residency": "Proof of residency",
    "household_expenses": "Household expenses",
}


def format_assessment(raw: str | None) -> str:
    if not raw:
        return "Unknown"
    key = str(raw).lower().strip()
    return ASSESSMENT_LABELS.get(key, str(raw).replace("_", " ").strip())


def format_track_b_status(raw: str | None) -> str:
    """Map requirement status (satisfied|questionable|missing) to resident copy."""
    if not raw:
        return format_assessment("uncertain")
    key = str(raw).lower().strip()
    if key in ("satisfied", "questionable", "missing"):
        return format_assessment(key if key != "satisfied" else "satisfied")
    return format_assessment(raw)


def format_requirement_name(raw: str | None) -> str:
    if not raw:
        return "Requirement"
    key = str(raw).lower().strip()
    return _REQUIREMENT_KEY_ALIASES.get(key, str(raw).replace("_", " ").title())


def format_notice_consequence(raw: str | None) -> str:
    """Short consequence line under deadline (align with mobile noticeConsequenceLabel)."""
    t = (raw or "").strip()
    if not t:
        return ""
    if t.lower() == "case_closure":
        return "Your benefits could be stopped if you do not respond in time."
    return t


def track_a_badge_class(assessment: str | None) -> str:
    """CSS class for proof-pack rows (status-* in app CUSTOM_CSS)."""
    a = (assessment or "").lower().strip()
    if a in ("likely_satisfies", "satisfied"):
        return "status-satisfied"
    if a in ("questionable", "residency_ambiguous", "insufficient_information", "uncertain"):
        return "status-uncertain" if a in ("insufficient_information", "uncertain") else "status-questionable"
    if a in ("likely_does_not_satisfy", "missing", "invalid_proof"):
        return "status-missing"
    return "status-uncertain"


def track_b_badge_class(status: str | None) -> str:
    s = (status or "").lower().strip()
    if s == "satisfied":
        return "status-satisfied"
    if s == "questionable":
        return "status-questionable"
    if s == "missing":
        return "status-missing"
    return "status-uncertain"
