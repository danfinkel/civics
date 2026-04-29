"""
CivicLens Web Demo - Gradio Application

A privacy-first civic document intelligence demo using Gemma 4 E4B.
Helps residents prepare document packets for SNAP recertification and school enrollment.

Visual design aligns with mobile `mobile/lib/shared/theme/app_theme.dart` (Prism / Civic Prism).
"""

import base64
import html
import json
from pathlib import Path

import gradio as gr
from gradio.themes import Color, GoogleFont, Soft
from gradio.themes import colors as theme_colors

from inference_backend import run_track_a, run_track_b
from upload_utils import coerce_track_a_files, coerce_track_b_files
from label_formatting import (
    format_assessment,
    format_notice_consequence,
    format_requirement_name,
    format_track_b_status,
    track_a_badge_class,
    track_b_badge_class,
)

_WEB_DIR = Path(__file__).resolve().parent
_SAMPLE_DIR = _WEB_DIR / "sample_docs"
# Track A SNAP: bundled demo JPGs for “Load sample” (also copied in Dockerfile for HF Spaces).
SAMPLE_TRACK_A_NOTICE_JPG = _SAMPLE_DIR / "D01-clean.jpg"
SAMPLE_TRACK_A_SUPPORTING_JPG = _SAMPLE_DIR / "D03-clean.jpg"


def _sample_jpg_path_or_error(path: Path) -> str:
    if not path.is_file():
        raise gr.Error(
            f"Sample file is missing: {path.name}. "
            "Ensure web_demo/sample_docs/ is present (see repo or Docker COPY)."
        )
    return str(path.resolve())


def load_sample_track_a_notice() -> str:
    return _sample_jpg_path_or_error(SAMPLE_TRACK_A_NOTICE_JPG)


def load_sample_track_a_supporting() -> str:
    return _sample_jpg_path_or_error(SAMPLE_TRACK_A_SUPPORTING_JPG)


# Mirrors mobile AppColors (+ existing web demo hues)
COLORS = {
    "primary": "#002444",
    "primary_container": "#1A3A5C",
    "on_primary": "#FFFFFF",
    "surface": "#F7F9FB",
    "surface_container_low": "#F2F4F6",
    "surface_container": "#ECEEF0",
    "surface_container_lowest": "#FFFFFF",
    "success": "#10B981",
    "warning": "#F59E0B",
    "error": "#EF4444",
    "neutral": "#64748B",
    "outline": "#73777F",
    "ghost_border": "#C3C6CF",
    "light_green": "#F0FDF4",
    "light_amber": "#FFFBEB",
    "light_red": "#FFF3F3",
    "light_blue": "#EFF6FF",
}


def civic_gradio_theme() -> Soft:
    """
    Drive Gradio's own CSS variables (fonts, primary ramp, surfaces) — matches mobile AppColors.
    A plain Soft() theme leaves indigo Tailwind primaries; custom Color fixes --primary-500 to #002444.
    """
    primary = Color(
        c50="#E8EEF4",
        c100="#D1DDE8",
        c200="#A4B7C8",
        c300="#6D8AA0",
        c400="#375A78",
        c500="#002444",
        c600="#001F3C",
        c700="#1A3A5C",
        c800="#001228",
        c900="#000E1C",
        c950="#000814",
        name="civic_navy",
    )
    return Soft(
        primary_hue=primary,
        secondary_hue=primary,
        neutral_hue=theme_colors.slate,
        font=[GoogleFont("Public Sans"), "system-ui", "sans-serif"],
        font_mono=[GoogleFont("IBM Plex Mono"), "ui-monospace", "monospace"],
    ).set(
        body_background_fill="#F7F9FB",
        body_text_color="#002444",
        # Slate-700: Gradio routes many "muted" ribbons to subdued; slate-500 on white washed out.
        body_text_color_subdued="#334155",
        # Match light Prism everywhere — OS dark-mode users otherwise get graphite shell + pale tokens on white cards.
        body_background_fill_dark="#F7F9FB",
        body_text_color_dark="#002444",
        body_text_color_subdued_dark="#334155",
        background_fill_primary="#FFFFFF",
        background_fill_secondary="#F2F4F6",
        block_background_fill="#FFFFFF",
        block_border_color="#C3C6CF",
        border_color_primary="#C3C6CF",
        border_color_accent="#002444",
        color_accent_soft="#EFF6FF",
        block_label_text_color="#002444",
        block_title_text_color="#002444",
        button_primary_background_fill="#002444",
        button_primary_background_fill_hover="#1A3A5C",
        button_primary_text_color="#FFFFFF",
        link_text_color="#1A3A5C",
        link_text_color_hover="#002444",
        link_text_color_active="#002444",
        link_text_color_visited="#375A78",
    )


def _brand_icon_data_uri() -> str:
    icon = _WEB_DIR / "branding" / "app_icon.png"
    if not icon.is_file():
        return ""
    return "data:image/png;base64," + base64.b64encode(icon.read_bytes()).decode("ascii")


def _brand_icon_html() -> str:
    uri = _brand_icon_data_uri()
    if not uri:
        return ""
    return (
        f'<img class="civiclens-brand-logo" src="{uri}" '
        'width="72" height="72" alt="" role="presentation" />'
    )

_RAW_PREVIEW_MAX = 12000

# Load via <link> in markup — @import inside injected CSS can be stripped on some CSPs / Spaces.
_FONT_LINKS_HTML = """
<link rel="preconnect" href="https://fonts.googleapis.com"/>
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin/>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Public+Sans:ital,wght@0,400;0,500;0,600;1,400&family=Space+Grotesk:wght@600;700&display=swap"/>
"""


def _fatal_inference_failure(result: dict) -> bool:
    """No model output (crash / missing uploads); distinguish from JSON parse failures."""
    return not (result.get("raw_response") or "").strip()


def _failure_headline_panel_style(result: dict) -> tuple[str, bool]:
    """(title, use_red_banner). Inference errors get explicit titles—not a generic documents error."""
    err = (result.get("error") or "").strip()

    if "No documents provided" in err:
        return "No documents to analyze", False

    if err.startswith("Inference failed:"):
        return "Inference could not finish", True

    # Model returned text we could not parse into our JSON schema (raw is non-empty).
    if not _fatal_inference_failure(result):
        return "Unstructured response", False

    if "could not be parsed as JSON" in err:
        return "No usable text from the model", False

    return "Analysis did not complete", True


def _format_inference_failure_panel(result: dict) -> str:
    """Distinguish missing uploads / inference crashes / parse misses / empty decode."""
    error_msg = result.get("error") or "Unknown error"
    blur = result.get("blur_warnings") or []
    blur_html = ""
    if blur:
        br = "<br>".join(html.escape(b) for b in blur)
        blur_html = f'''
        <div style="margin: 12px 0; padding: 10px; background-color: #FEFCE8;
                    border-radius: 6px; font-size: 14px;"><strong>Image quality hints</strong><br>{br}</div>
        '''

    raw = result.get("raw_response") or ""
    raw_esc_full = html.escape(raw)
    excerpt = raw_esc_full[:_RAW_PREVIEW_MAX]
    truncated_note = ""
    if len(raw_esc_full) > _RAW_PREVIEW_MAX:
        truncated_note = (
            '<p style="font-size: 12px; color: #6B7280;">'
            f"Showing first {_RAW_PREVIEW_MAX} characters."
            "</p>"
        )
    err_esc = html.escape(error_msg)
    headline, red = _failure_headline_panel_style(result)

    if not (_fatal_inference_failure(result)):
        return f"""
    <div style="padding: 16px; background-color: {COLORS['light_amber']}; border: 2px solid #B45309;
                border-radius: 8px;">
        <h3 style="color: #92400E; margin-top: 0;">{html.escape(headline)}</h3>
        <p>{err_esc}</p>
        <p style="font-size: 14px; line-height: 1.5;">The model returned text we could not map to the
        expected JSON checklist. Inspect the raw output below; it may still contain useful guidance.</p>
        {blur_html}
        <details open>
            <summary>Raw model output</summary>
            {truncated_note}
            <pre style="font-size: 11px; overflow-x: auto; white-space: pre-wrap;">{excerpt}</pre>
        </details>
    </div>
    """

    bg = COLORS["light_red"] if red else COLORS["light_amber"]
    border = f"border: {'2px solid #FCA5A5' if red else '2px solid #B45309'};"
    hc = COLORS["error"] if red else "#92400E"

    hint = ""
    if (_fatal_inference_failure(result) and "Inference failed:" in error_msg):
        hint = (
            '<p style="font-size: 13px; color: #6B7280;">If this persists, open the Space <strong>Logs</strong> '
            "tab on Hugging Face (GPU memory, timeouts, or first-load model download).</p>"
        )
    elif _fatal_inference_failure(result) and "could not be parsed as JSON" in error_msg:
        hint = (
            '<p style="font-size: 13px; color: #6B7280;">The reply decoded to whitespace only. '
            "Try a smaller image/PDF page or retry after cold start.</p>"
        )

    return f"""
        <div style="padding: 16px; background-color: {bg}; border-radius: 8px; {border}">
            <h3 style="color: {hc}; margin-top: 0;">{html.escape(headline)}</h3>
            <p>{err_esc}</p>
            {hint}
            {blur_html}
            <details>
                <summary>Technical details / raw output (if any)</summary>
                <pre style="font-size: 11px; overflow-x: auto; white-space: pre-wrap;">{excerpt}</pre>
            </details>
        </div>
        """


def _format_success_but_empty_visual_panel(result: dict, track_label: str) -> str:
    """Inference reported success but no panel blocks matched (empty or nested payloads)."""
    raw = result.get("raw_response") or ""
    parsed = result.get("parsed")

    excerpt = ""
    try:
        if parsed is not None:
            excerpt = json.dumps(parsed, indent=2, default=str)
    except (TypeError, ValueError):
        excerpt = ""
    if not excerpt.strip() and raw:
        excerpt = raw
    excerpt = excerpt[:_RAW_PREVIEW_MAX]
    excerpt_esc = html.escape(excerpt)
    truncated = ""
    if len(raw) > _RAW_PREVIEW_MAX:
        truncated = (
            f'<p style="font-size: 12px; color: #6B7280;">'
            f"Showing first {_RAW_PREVIEW_MAX} characters of assistant text.</p>"
        )

    return f"""
    <div style="padding: 16px; background-color: {COLORS["light_blue"]}; border: 1px solid #93C5FD;
                border-radius: 8px; margin: 16px 0;">
        <h3 style="margin-top: 0; color: {COLORS["primary"]};">Nothing mapped to summary panels yet</h3>
        <p style="color: #374151; line-height: 1.5;">
            The run finished, but structured fields for {html.escape(track_label)} were empty or did not match
            the expected layout (for example checklist keys nested under another object). Expand
            <strong>Raw JSON Output</strong> for the full reply. Parsed payload or assistant text preview:
        </p>
        {truncated}
        <pre style="font-size: 11px; overflow-x: auto; white-space: pre-wrap;
                  background: #fff; border: 1px solid #E5E7EB; border-radius: 4px;
                  padding: 12px;">{excerpt_esc}</pre>
    </div>
    """


# Custom CSS — Prism / mobile theme (fonts loaded via `_FONT_LINKS_HTML` above)
CUSTOM_CSS = f"""
:root {{
    --primary: {COLORS['primary']};
    --primary-container: {COLORS['primary_container']};
    --surface: {COLORS['surface']};
    --surface-low: {COLORS['surface_container_low']};
    --surface-container: {COLORS['surface_container']};
    --on-surface: {COLORS['primary']};
    --success: {COLORS['success']};
    --warning: {COLORS['warning']};
    --error: {COLORS['error']};
    --neutral: {COLORS['neutral']};
    --outline: {COLORS['outline']};
    --ghost-border: {COLORS['ghost_border']};
    --radius-md: 12px;
    --radius-lg: 16px;
    --font-display: 'Space Grotesk', system-ui, sans-serif;
    --font-body: 'Public Sans', system-ui, sans-serif;
    --prism-card-shadow: 0 2px 8px rgba(0, 36, 68, 0.08);
}}

html, body {{
    background-color: {COLORS['surface']} !important;
}}

/*
 * Full-page Prism background: Gradio's index.html applies dark body colors under
 * @media (prefers-color-scheme: dark); that paints a nearly-black gutter around the
 * white `.civiclens-shell`, and prose/tab "muted" tokens read as pale-on-white inside the shell.
 * Keep CivicLens on light Prism surfaces consistently.
 */
gradio-app {{
    background-color: {COLORS['surface']} !important;
}}

@media (prefers-color-scheme: dark) {{
    html, body {{
        background-color: {COLORS['surface']} !important;
    }}
    gradio-app {{
        background-color: {COLORS['surface']} !important;
    }}
}}

/*
 * civic_gradio_theme() sets Public Sans on :root --font (Gradio native UI).
 * Space Grotesk = mobile display font for markdown + tabs; hero title stays on gradient (styles below).
 */
#civiclens-app .prose h1,
#civiclens-app .prose h2,
#civiclens-app .prose h3 {{
    font-family: 'Space Grotesk', 'Public Sans', system-ui, sans-serif !important;
    letter-spacing: -0.02em !important;
    font-weight: 600 !important;
    color: {COLORS['primary']} !important;
}}

#civiclens-app [role="tablist"] button,
#civiclens-app [data-testid="tab-nav"] button,
#civiclens-app button[role="tab"] {{
    font-family: 'Space Grotesk', 'Public Sans', system-ui, sans-serif !important;
    font-weight: 600 !important;
}}

/* Tabs: inactive often omits aria-selected until focus — default all tab pills dark, lift active */
#civiclens-app button[role="tab"] {{
    color: #1e293b !important;
    opacity: 1 !important;
}}
#civiclens-app button[role="tab"][aria-selected="true"],
#civiclens-app button[role="tab"][data-state="active"],
#civiclens-app button[role="tab"][aria-selected="true"]:not([disabled]) {{
    color: {COLORS['primary']} !important;
}}

/* Tabs: inactive state — kept for redundancy with [role="tab"] rules above */
#civiclens-app [role="tablist"] button[aria-selected="true"],
#civiclens-app [role="tablist"] button[data-state="active"] {{
    color: {COLORS['primary']} !important;
}}
#civiclens-app [role="tablist"] button[aria-selected="false"],
#civiclens-app [role="tablist"] button[data-state="inactive"] {{
    color: #334155 !important;
    opacity: 1 !important;
}}

/* Markdown card titles ("### …") — cover non-.prose wrappers Gradio sometimes uses */
#civiclens-app .civiclens-intro .markdown :where(h1, h2, h3, h4),
#civiclens-app .civiclens-shell .markdown :where(h1, h2, h3, h4) {{
    font-family: 'Space Grotesk', 'Public Sans', system-ui, sans-serif !important;
    color: {COLORS['primary']} !important;
    font-weight: 600 !important;
}}

/* prose / tailwind typography can assign pale heading colors when prefers-color-scheme: dark matches OS */
@media (prefers-color-scheme: dark) {{
    #civiclens-app .prose :where(h1, h2, h3, h4, h5, h6),
    #civiclens-app .civiclens-shell article :where(h1, h2, h3, h4),
    #civiclens-app .markdown :where(h1, h2, h3, h4) {{
        color: {COLORS['primary']} !important;
    }}
}}

/* Intro body copy — slate-700 on white (neutral #64748B was marginal on light gray backgrounds) */
.civiclens-intro .prose p,
.civiclens-intro .prose li {{
    color: #334155 !important;
}}
/* Bold / links inside intro must not pick up tertiary/muted markdown tokens */
.civiclens-intro .prose strong {{
    color: {COLORS['primary']} !important;
}}
.civiclens-intro .prose a {{
    color: {COLORS['primary_container']} !important;
}}

/* Compact note under Analyze (HF vs E2B inference) */
#civiclens-app .civiclens-inference-note,
#civiclens-app .civiclens-inference-note p {{
    font-size: 13px !important;
    line-height: 1.45 !important;
    color: #64748b !important;
    margin: 12px 0 0 !important;
}}

/*
 * File preview styling: Internals read `--body-text-color` / `--link-text-color` (incl. across shadow roots).
 * Anchor on `elem_classes=["civic-file-slot"]`. Subdued token stays slate so idle/hint copy stays legible on white.
 */
#civiclens-app .civic-file-slot {{
    /* Main preview text uses `--body-text-color`; helper lines use subdued — kept dark enough for idle areas. */
    --body-text-color: rgba(248, 250, 252, 0.98);
    --body-text-color-subdued: #64748b;
    --link-text-color: rgba(248, 250, 252, 0.98);
    --link-text-color-hover: #ffffff;
    --link-text-color-visited: rgba(226, 232, 240, 0.9);
    --link-text-color-active: #ffffff;
}}

gradio-app .civic-file-slot {{
    --body-text-color: rgba(248, 250, 252, 0.98);
    --body-text-color-subdued: #64748b;
    --link-text-color: rgba(248, 250, 252, 0.98);
    --link-text-color-hover: #ffffff;
}}

#civiclens-app .civic-file-slot [class*="file-preview"],
#civiclens-app .civic-file-slot [class*="filename"] .stem,
#civiclens-app .civic-file-slot [class*="filename"] .ext,
#civiclens-app .civic-file-slot [class*="file-name"],
#civiclens-app .civic-file-slot [class*="file-name"] *,
#civiclens-app .civic-file-slot [class*="file-size"],
#civiclens-app .civic-file-slot [class*="drag-handle"],
#civiclens-app .civic-file-slot [class*="label-clear-button"],
#civiclens-app .civic-file-slot [class*="download"] :is(a, a:link, a:visited, a:active) {{
    color: rgba(248, 250, 252, 0.98) !important;
}}

#civiclens-app .civic-file-slot [class*="download"] a:hover {{
    color: #ffffff !important;
}}

#civiclens-app .civic-file-slot [class*="file-preview-holder"] svg,
#civiclens-app .civic-file-slot .file[class*="svelte"] svg {{
    color: rgba(248, 250, 252, 0.95) !important;
    stroke: rgba(248, 250, 252, 0.95) !important;
    fill: none;
    opacity: 1 !important;
}}

/* Upload-slot progress stripe (`Upload` `.wrap:after`) — `:after` sits on `.wrap` while `.file` is inside it. */
#civiclens-app .wrap[class*="svelte"]:has(> input[type="file"]),
#civiclens-app .wrap[class*="svelte"]:has([class*="file-name"]),
#civiclens-app .wrap[class*="svelte"]:has([class*="uploading"]),
#civiclens-app .wrap[class*="svelte"]:has([class*="file-preview"]) {{
    position: relative;
}}
#civiclens-app .wrap[class*="svelte"]:has([class*="file-name"]):after,
#civiclens-app .wrap[class*="svelte"]:has([class*="uploading"]):after {{
    background: linear-gradient(
        90deg,
        rgba(248, 250, 252, 0.22) 0%,
        rgba(248, 250, 252, 0.06) 100%
    ) !important;
    mix-blend-mode: screen;
}}

/* Headings / display text inside our gr.HTML result panels use .civiclens-* rules below */

/* Prism hero header (matches mobile prismHeroGradient intent) */
.civiclens-hero {{
    background: linear-gradient(135deg, {COLORS['primary']} 0%, {COLORS['primary_container']} 100%);
    color: {COLORS['on_primary']};
    border-radius: var(--radius-lg);
    padding: 28px 24px;
    margin-bottom: 24px;
    box-shadow: 0 8px 24px rgba(0, 36, 68, 0.22);
}}

.civiclens-hero-inner {{
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: center;
    gap: 20px;
    max-width: 920px;
    margin: 0 auto;
}}

.civiclens-brand-row {{
    display: flex;
    align-items: center;
    gap: 18px;
    text-align: left;
}}

.civiclens-brand-logo {{
    flex-shrink: 0;
    border-radius: var(--radius-md);
    box-shadow: 0 6px 20px rgba(0, 0, 0, 0.25);
    object-fit: cover;
}}

.civiclens-hero-title {{
    font-family: var(--font-display);
    margin: 0;
    font-size: 1.75rem;
    font-weight: 700;
    letter-spacing: -0.02em;
}}

/* Prism hero: never inherit navy body/text tokens. Do not scope through Blocks elem_id:
   Gradio 6 can render user HTML under wrappers where #civiclens-app is not an ancestor. */
.civiclens-hero,
.civiclens-hero *,
.civiclens-hero h1.civiclens-hero-title,
.civiclens-hero .civiclens-tagline {{
    color: {COLORS['on_primary']} !important;
}}

.civiclens-tagline {{
    margin: 6px 0 0;
    font-size: 14px;
    font-weight: 400;
    line-height: 1.45;
    opacity: 0.92;
}}

/* Accordions with primary/header styling need light label text (theme block_title remains navy — for white panels). */
.civic-json-accordion details > summary,
.civic-json-accordion details > summary *,
.civic-json-accordion summary,
.civic-json-accordion summary * {{
    color: {COLORS['on_primary']} !important;
}}

/* Taller header strip: label + progress/runtime text must fit on one row without floating above the bar */
#civiclens-app .civic-json-accordion details.gr-accordion summary,
#civiclens-app .civic-json-accordion details > summary {{
    min-height: 4.25rem !important;
    padding-top: 1.125rem !important;
    padding-bottom: 1.125rem !important;
    box-sizing: border-box;
    align-items: center;
}}
#civiclens-app .civic-json-accordion [class*="label-wrap"],
#civiclens-app .civic-json-accordion summary [class*="label-wrap"] {{
    min-height: 4.25rem !important;
    padding: 1rem 1.125rem !important;
    box-sizing: border-box;
    align-items: center !important;
    gap: 0.75rem;
}}

.civic-json-accordion .label-wrap,
.civic-json-accordion .label-wrap *,
.civic-json-accordion button[aria-expanded],
.civic-json-accordion button[aria-expanded] *,
.civic-json-accordion [class*="label"],
.civic-json-accordion [class*="label"] * {{
    color: {COLORS['on_primary']} !important;
}}

/*
 * Inference status (StreamingBar). Idle state uses `.wrap.hide` + opacity 0; our min-height still
 * reserved a strip — collapse the tracker entirely until a run. Thicken `.progress-bar-wrap` (track behind fill).
 */
#civiclens-app [data-testid="status-tracker"]:has(.wrap.hide),
gradio-app [data-testid="status-tracker"]:has(.wrap.hide) {{
    display: none !important;
}}

#civiclens-app [data-testid="status-tracker"],
gradio-app [data-testid="status-tracker"] {{
    --body-text-color: rgba(248, 250, 252, 0.98);
    --loader-color: {COLORS['on_primary']};
    --background-fill-secondary: rgba(0, 36, 68, 0.15);
}}

#civiclens-app [data-testid="status-tracker"] span,
#civiclens-app [data-testid="status-tracker"] time,
#civiclens-app [data-testid="status-tracker"] .progress-text,
#civiclens-app [data-testid="status-tracker"] .duration,
#civiclens-app [data-testid="status-tracker"] .progress-level-inner,
#civiclens-app [data-testid="status-tracker"] .meta-text,
#civiclens-app [data-testid="status-tracker"] .meta-text-center,
#civiclens-app [data-testid="status-tracker"] .loading {{
    color: rgba(248, 250, 252, 0.98) !important;
}}

#civiclens-app [data-testid="status-tracker"] .loading-spinner,
.civic-json-accordion .loading-spinner {{
    border-color: rgba(248, 250, 252, 0.95) !important;
    border-top-color: transparent !important;
}}

#civiclens-app [data-testid="status-tracker"] svg {{
    color: rgba(248, 250, 252, 0.95) !important;
    stroke: rgba(248, 250, 252, 0.95) !important;
    opacity: 1 !important;
}}

/* Thicker track (light bar the fill runs on) + optional bottom countdown strip */
#civiclens-app [data-testid="status-tracker"] .progress-bar-wrap {{
    height: 12px !important;
    min-height: 12px !important;
    border-radius: var(--radius-full);
}}
#civiclens-app [data-testid="status-tracker"] .progress-bar {{
    min-height: 12px !important;
}}
#civiclens-app [data-testid="status-tracker"] .streaming-bar {{
    height: 6px !important;
}}

/* Room for absolute-positioned ETA captions only while the bar is active (not `.hide`) */
#civiclens-app [data-testid="status-tracker"] > .wrap[class*="svelte"]:not(.hide) {{
    box-sizing: border-box;
    min-height: 5rem;
    padding-top: 0.75rem !important;
    padding-bottom: 1.75rem !important;
}}

/* In-accordion StreamingBar: undo absolute meta/center text so "processing | …" sits in the navy header */
#civiclens-app .civic-json-accordion [data-testid="status-tracker"] {{
    flex: 1 1 auto;
    min-width: 0;
    max-width: 100%;
}}

#civiclens-app .civic-json-accordion [data-testid="status-tracker"] > .wrap[class*="svelte"]:not(.hide) {{
    position: relative !important;
    inset: auto !important;
    min-height: unset !important;
    padding: 0 !important;
    overflow: visible !important;
    align-items: flex-end;
    justify-content: flex-end;
}}

#civiclens-app .civic-json-accordion [data-testid="status-tracker"] .meta-text,
#civiclens-app .civic-json-accordion [data-testid="status-tracker"] .meta-text-center {{
    position: static !important;
    inset: auto !important;
    transform: none !important;
    align-self: center;
    margin: 0 !important;
    padding: 0 !important;
    font-size: 0.75rem !important;
    white-space: nowrap;
}}

#civiclens-app .civic-json-accordion [data-testid="status-tracker"] .progress-level-inner {{
    position: static !important;
    margin: 0.125rem 0 0 !important;
}}

#civiclens-app .civic-json-accordion [data-testid="status-tracker"] .progress-level {{
    width: 100%;
    max-width: 18rem;
}}
#civiclens-app .civic-json-accordion [data-testid="status-tracker"] .progress-bar-wrap {{
    height: 14px !important;
    min-height: 14px !important;
    width: min(100%, 18rem) !important;
}}
#civiclens-app .civic-json-accordion [data-testid="status-tracker"] .progress-bar {{
    min-height: 14px !important;
}}

#civiclens-app .civic-json-accordion [data-testid="status-tracker"] .eta-bar {{
    position: absolute !important;
    inset: auto !important;
    left: 0 !important;
    right: 0 !important;
    bottom: 0 !important;
    top: auto !important;
    height: 6px !important;
    border-radius: var(--radius-full);
    opacity: 0.85;
}}

.civic-json-accordion [data-testid="status-tracker"] span,
.civic-json-accordion [data-testid="status-tracker"] .progress-text {{
    color: rgba(248, 250, 252, 0.95) !important;
}}

.civic-json-accordion [data-testid="status-tracker"] svg {{
    color: rgba(248, 250, 252, 0.95) !important;
    stroke: rgba(248, 250, 252, 0.95) !important;
    opacity: 1 !important;
}}

.civiclens-brand-text {{
    min-width: 0;
}}

.civiclens-intro p,
.civiclens-intro li {{
    line-height: 1.55;
}}

.civiclens-shell .prose {{
    max-width: none;
}}

.civiclens-shell {{
    background: {COLORS['surface_container_lowest']};
    border: 1px solid {COLORS['ghost_border']};
    border-radius: var(--radius-lg);
    padding: 20px 16px;
    margin-bottom: 8px;
    box-shadow: var(--prism-card-shadow);
}}

@media (max-width: 768px) {{
    .civiclens-hero {{
        padding: 22px 16px;
    }}
    .civiclens-hero-title {{ font-size: 1.4rem !important; }}
    .civiclens-brand-row {{ flex-wrap: nowrap; gap: 12px; }}
    .requirement-row {{
        flex-direction: column !important;
        align-items: flex-start !important;
    }}
    .requirement-row > div:last-child {{
        margin-top: 12px;
        text-align: left !important;
    }}
}}

/* Tab labels — avoid targeting primary action buttons inside panels */
#civiclens-app [data-testid="tab-nav"] button,
#civiclens-app div[class*="tab-nav"] > button {{
    font-family: var(--font-display) !important;
    font-weight: 600 !important;
    letter-spacing: -0.01em !important;
}}

.gr-button {{
    font-family: var(--font-body) !important;
    font-weight: 600 !important;
    border-radius: var(--radius-md) !important;
    min-height: 48px !important;
}}

.gr-file-upload {{
    min-height: 48px !important;
    border-radius: var(--radius-md) !important;
    border-color: var(--ghost-border) !important;
}}

/* Primary CTA buttons */
.primary, .lg.primary, button.primary {{
    border-radius: var(--radius-md) !important;
}}

.gr-button-primary {{
    background: linear-gradient(180deg, {COLORS['primary']} 0%, #001a38 140%) !important;
    border: none !important;
}}

.gr-button-primary:hover {{
    background: {COLORS['primary_container']} !important;
}}

.gr-button-primary:active {{
    opacity: 0.95 !important;
}}

/* Result cards + badges (semantic colors unchanged) */
.status-satisfied {{
    background-color: {COLORS['light_green']};
    color: {COLORS['success']};
    padding: 8px 16px;
    border-radius: var(--radius-md);
    font-weight: 600;
    display: inline-block;
}}

.status-questionable {{
    background-color: {COLORS['light_amber']};
    color: #B45309;
    padding: 8px 16px;
    border-radius: var(--radius-md);
    font-weight: 600;
    display: inline-block;
}}

.status-missing {{
    background-color: {COLORS['light_red']};
    color: {COLORS['error']};
    padding: 8px 16px;
    border-radius: var(--radius-md);
    font-weight: 600;
    display: inline-block;
}}

.status-uncertain {{
    background-color: {COLORS['surface_container']};
    color: {COLORS['neutral']};
    padding: 8px 16px;
    border-radius: var(--radius-md);
    font-weight: 600;
    display: inline-block;
}}

.action-summary {{
    background-color: {COLORS['light_blue']};
    border-left: 4px solid {COLORS['primary']};
    padding: 20px;
    border-radius: var(--radius-md);
    margin: 16px 0;
}}

.warning-banner {{
    background-color: {COLORS['light_amber']};
    border-left: 4px solid {COLORS['warning']};
    padding: 12px 16px;
    border-radius: var(--radius-md);
    margin: 16px 0;
}}

.confidence-high {{ color: {COLORS['success']}; font-weight: 600; }}
.confidence-medium {{ color: {COLORS['warning']}; font-weight: 600; }}
.confidence-low {{ color: {COLORS['error']}; font-weight: 600; }}

.requirement-row, .proof-pack-item {{
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 16px;
    background: {COLORS['surface_container_lowest']};
    border: 1px solid var(--ghost-border);
    border-radius: var(--radius-md);
    margin: 8px 0;
    box-shadow: var(--prism-card-shadow);
}}

.proof-pack-item {{
    align-items: flex-start;
}}

.privacy-footer {{
    text-align: center;
    padding: 24px 12px;
    margin-top: 28px;
    border-top: 1px solid {COLORS['ghost_border']};
    font-size: 12px;
    color: var(--neutral);
}}

.privacy-footer strong {{
    color: var(--primary);
}}
"""


def format_track_b_results(result: dict) -> str:
    """Format Track B results as HTML."""
    if not result.get("success"):
        return _format_inference_failure_panel(result)

    parsed = result.get("parsed", {})
    blur_warnings = result.get("blur_warnings", [])

    html_parts = []

    # Blur warnings
    if blur_warnings:
        html_parts.append(f"""
        <div class="warning-banner">
            <strong>⚠️ Image quality</strong><br>
            {"<br>".join(blur_warnings)}
        </div>
        """)

    # Duplicate category warning (first — unmissable, matches mobile)
    if parsed.get("duplicate_category_flag"):
        expl = (parsed.get("duplicate_category_explanation") or "").strip()
        expl_html = f'<div style="font-size: 14px; color: #1A1A1A; margin-top: 8px;">{expl}</div>' if expl else ""
        html_parts.append(f"""
        <div style="background-color: {COLORS['light_amber']}; border: 2px solid #B45309;
                    border-radius: 8px; padding: 16px; margin-bottom: 16px;">
            <div style="font-size: 16px; font-weight: bold; color: #92400E;">
                Two documents from the same category
            </div>
            <div style="font-size: 14px; color: #1A1A1A; margin-top: 8px; line-height: 1.5;">
                You may have submitted two documents from the same category (for example, two leases).
                BPS requires two proofs of residency from <strong>different</strong> categories — for example,
                a lease and a utility bill. A second document of the same type does not count as a second proof.
            </div>
            {expl_html}
        </div>
        """)

    # Family summary (prominent, before per-requirement rows)
    family_summary = parsed.get("family_summary", "")
    if family_summary:
        html_parts.append(f"""
        <div class="action-summary">
            <h3 style="margin-top: 0; color: {COLORS['primary']};">What to bring to registration</h3>
            <p style="margin-bottom: 0; line-height: 1.6;">{family_summary}</p>
        </div>
        """)

    # Requirements checklist
    requirements = parsed.get("requirements", [])
    if requirements:
        html_parts.append("<h3>Requirements checklist</h3>")
        for req in requirements:
            status = req.get("status", "unknown")
            confidence = req.get("confidence", "medium")
            req_name = format_requirement_name(req.get("requirement"))
            matched_doc = req.get("matched_document", "MISSING")
            evidence = req.get("evidence", "")
            notes = req.get("notes", "")

            status_label = format_track_b_status(status)
            badge_class = track_b_badge_class(status)
            confidence_class = f"confidence-{confidence}"

            html_parts.append(f"""
            <div class="requirement-row">
                <div style="flex: 1;">
                    <div style="font-weight: 600; margin-bottom: 4px;">{req_name}</div>
                    <div style="font-size: 12px; color: #6B7280;">
                        Matched: {matched_doc}
                        {f"<br>Evidence: {evidence}" if evidence else ""}
                        {f"<br>Notes: {notes}" if notes else ""}
                    </div>
                </div>
                <div style="text-align: right;">
                    <span class="{badge_class}">{status_label}</span>
                    <div style="font-size: 11px; margin-top: 4px;" class="{confidence_class}">
                        {confidence} confidence
                    </div>
                </div>
            </div>
            """)

    out = "\n".join(html_parts)
    if result.get("success") and not out.strip():
        return _format_success_but_empty_visual_panel(result, "Track B")
    return out


def format_track_a_results(result: dict) -> str:
    """Format Track A results as HTML."""
    if not result.get("success"):
        return _format_inference_failure_panel(result)

    parsed = result.get("parsed", {})
    blur_warnings = result.get("blur_warnings", [])

    html_parts = []

    # Blur warnings
    if blur_warnings:
        html_parts.append(f"""
        <div class="warning-banner">
            <strong>⚠️ Image quality</strong><br>
            {"<br>".join(blur_warnings)}
        </div>
        """)

    # Notice: deadline banner + summary (align with mobile)
    notice_summary = parsed.get("notice_summary", {})
    if notice_summary:
        deadline = notice_summary.get("deadline", "")
        categories = notice_summary.get("requested_categories", [])
        consequence = notice_summary.get("consequence", "")
        cons_disp = format_notice_consequence(consequence) or consequence

        if deadline and deadline != "UNCERTAIN":
            html_parts.append(f"""
            <div style="background-color: {COLORS['light_red']}; border: 2px solid #B71C1C;
                        border-radius: 8px; padding: 16px; margin-bottom: 16px;">
                <div style="font-size: 18px; font-weight: bold; color: #B71C1C;">
                    Respond by {deadline}
                </div>
                {f'<div style="font-size: 14px; color: #555555; margin-top: 4px;">{cons_disp}</div>' if cons_disp else ""}
            </div>
            """)
        elif deadline == "UNCERTAIN":
            html_parts.append(f"""
            <div style="background-color: {COLORS['light_amber']}; border: 2px solid #B45309;
                        border-radius: 8px; padding: 16px; margin-bottom: 16px;">
                <div style="font-size: 16px; font-weight: bold; color: #92400E;">
                    Notice is unclear
                </div>
                <div style="font-size: 14px; color: #1A1A1A; margin-top: 8px;">
                    We could not read a clear deadline on this notice. Contact DTA at the number
                    on your notice to confirm your response date.
                </div>
            </div>
            """)

        if categories:
            html_parts.append(f"""
            <div style="background: white; border: 1px solid #E5E7EB; border-radius: 8px; padding: 16px; margin: 16px 0;">
                <h3 style="margin-top: 0; color: {COLORS['primary']};">Notice summary</h3>
                <div><strong>Proof requested:</strong> {", ".join(categories)}</div>
            </div>
            """)

    # Proof pack
    proof_pack = parsed.get("proof_pack", [])
    if proof_pack:
        html_parts.append("<h3>Your proof pack</h3>")
        for item in proof_pack:
            category = format_requirement_name(item.get("category"))
            assessment = item.get("assessment", "uncertain")
            confidence = item.get("confidence", "medium")
            matched_doc = item.get("matched_document", "MISSING")
            evidence = item.get("evidence", "")
            caveats = item.get("caveats", "")

            status_class = track_a_badge_class(assessment)
            assess_label = format_assessment(assessment)
            confidence_class = f"confidence-{confidence}"

            html_parts.append(f"""
            <div class="proof-pack-item">
                <div style="display: flex; justify-content: space-between; align-items: start;">
                    <div style="flex: 1;">
                        <div style="font-weight: 600; font-size: 16px; margin-bottom: 4px;">{category}</div>
                        <div style="font-size: 14px; color: #374151;">
                            Document: {matched_doc}
                        </div>
                        {f'<div style="font-size: 12px; color: #6B7280; margin-top: 4px;">Evidence: {evidence}</div>' if evidence else ""}
                        {f'<div style="font-size: 12px; color: #B45309; margin-top: 4px;">⚠️ {caveats}</div>' if caveats else ""}
                    </div>
                    <div style="text-align: right;">
                        <span class="{status_class}">{assess_label}</span>
                        <div style="font-size: 11px; margin-top: 4px;" class="{confidence_class}">
                            {confidence} confidence
                        </div>
                    </div>
                </div>
            </div>
            """)

    # Action summary
    action_summary = parsed.get("action_summary", "")
    if action_summary:
        html_parts.append(f"""
        <div class="action-summary">
            <h3 style="margin-top: 0; color: {COLORS['primary']};">What To Do Next</h3>
            <p style="margin-bottom: 0; line-height: 1.6;">{action_summary}</p>
        </div>
        """)

    out = "\n".join(html_parts)
    if result.get("success") and not out.strip():
        return _format_success_but_empty_visual_panel(result, "Track A")
    return out


def process_track_a(notice, doc1, doc2, doc3):
    """Process Track A documents and return formatted results."""
    if not any(coerce_track_a_files(notice, doc1, doc2, doc3)):
        return (
            "Upload at least one document (your DTA notice first, if you have it).",
            "",
        )

    result = run_track_a(notice, doc1, doc2, doc3)
    html_output = format_track_a_results(result)
    json_output = json.dumps(result.get("parsed", {}), indent=2) if result.get("parsed") else result.get("raw_response", "")
    return html_output, json_output


def process_track_b(doc1, doc2, doc3, doc4, doc5):
    """Process Track B documents and return formatted results."""
    if not any(coerce_track_b_files(doc1, doc2, doc3, doc4, doc5)):
        return "Please upload at least one document to begin.", ""

    result = run_track_b(doc1, doc2, doc3, doc4, doc5)
    html_output = format_track_b_results(result)
    json_output = json.dumps(result.get("parsed", {}), indent=2) if result.get("parsed") else result.get("raw_response", "")
    return html_output, json_output


# Build the Gradio interface (Prism / mobile-aligned — see mobile/lib/shared/theme/)
with gr.Blocks(
    title="CivicLens",
    elem_id="civiclens-app",
) as demo:
    gr.HTML(f"""
    {_FONT_LINKS_HTML}
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=5.0"/>
    """)

    _icon = _brand_icon_html()
    gr.HTML(f"""
    <header class="civiclens-hero" aria-label="CivicLens">
        <div class="civiclens-hero-inner">
            <div class="civiclens-brand-row">
                {_icon}
                <div class="civiclens-brand-text">
                    <h1 class="civiclens-hero-title">CivicLens</h1>
                    <p class="civiclens-tagline">
                        Privacy-first civic document intelligence — same Civic Prism design language as our mobile app.
                        On this demo, uploads are processed on the server you run.
                    </p>
                </div>
            </div>
        </div>
    </header>
    """)

    with gr.Column(elem_classes=["civiclens-shell"]):
        with gr.Tabs(elem_classes=["civiclens-tabs"]):
            # Track A: SNAP Benefits
            with gr.Tab("SNAP Benefits"):
                gr.Markdown(
                    """
### SNAP document assistant

Upload your **DTA notice** first, then **supporting documents** (pay stubs, lease, etc.).
CivicLens reads the notice for deadlines and required proof, then checks your uploads
against each requirement.
""",
                    elem_classes=["civiclens-intro"],
                )

                with gr.Row():
                    with gr.Column(scale=1):
                        notice_input = gr.File(
                            elem_classes=["civic-file-slot"],
                            label="1. DTA notice (required — e.g. verification or recertification letter)",
                            file_types=[".pdf", ".jpg", ".jpeg", ".png"],
                        )
                        sample_notice_btn = gr.Button(
                            "Load sample (D01)",
                            size="sm",
                            variant="secondary",
                        )
                        doc1_input = gr.File(
                            elem_classes=["civic-file-slot"],
                            label="2. Supporting document",
                            file_types=[".pdf", ".jpg", ".jpeg", ".png"],
                        )
                        sample_supporting_btn = gr.Button(
                            "Load sample (D03)",
                            size="sm",
                            variant="secondary",
                        )

                        analyze_btn_a = gr.Button(
                            "Analyze Documents",
                            variant="primary",
                            size="lg",
                        )
                        gr.Markdown(
                            "This demo uses **Hugging Face inference**, not the deployed **Gemma / E2B** path used "
                            "on device. Model and runtime differ, so results may vary from other CivicLens builds.",
                            elem_classes=["civiclens-inference-note"],
                        )

                        doc2_input = gr.File(
                            elem_classes=["civic-file-slot"],
                            label="3. Supporting document (optional)",
                            file_types=[".pdf", ".jpg", ".jpeg", ".png"],
                        )
                        doc3_input = gr.File(
                            elem_classes=["civic-file-slot"],
                            label="4. Supporting document (optional)",
                            file_types=[".pdf", ".jpg", ".jpeg", ".png"],
                        )

                    with gr.Column(scale=2):
                        results_html_a = gr.HTML(label="Results")
                        with gr.Accordion("Raw JSON Output", open=False, elem_classes=["civic-json-accordion"]):
                            json_output_a = gr.Code(label="JSON", language="json")

                analyze_btn_a.click(
                    fn=process_track_a,
                    inputs=[notice_input, doc1_input, doc2_input, doc3_input],
                    outputs=[results_html_a, json_output_a],
                    show_progress_on=results_html_a,
                )
                sample_notice_btn.click(
                    fn=load_sample_track_a_notice,
                    inputs=[],
                    outputs=notice_input,
                )
                sample_supporting_btn.click(
                    fn=load_sample_track_a_supporting,
                    inputs=[],
                    outputs=doc1_input,
                )

            # Track B: School Enrollment
            with gr.Tab("School Enrollment"):
                gr.Markdown(
                    """
### BPS Enrollment Packet Checker

Upload your documents for Boston Public Schools registration.
CivicLens checks against the four BPS requirements:
- Proof of child's age
- Two proofs of residency from **different** categories
- Current immunization record
- Grade indicator (optional)
""",
                    elem_classes=["civiclens-intro"],
                )

                with gr.Row():
                    with gr.Column(scale=1):
                        b_doc1 = gr.File(
                            elem_classes=["civic-file-slot"],
                            label="Document 1 (required)",
                            file_types=[".pdf", ".jpg", ".jpeg", ".png"],
                        )
                        b_doc2 = gr.File(
                            elem_classes=["civic-file-slot"],
                            label="Document 2",
                            file_types=[".pdf", ".jpg", ".jpeg", ".png"],
                        )
                        b_doc3 = gr.File(
                            elem_classes=["civic-file-slot"],
                            label="Document 3",
                            file_types=[".pdf", ".jpg", ".jpeg", ".png"],
                        )
                        b_doc4 = gr.File(
                            elem_classes=["civic-file-slot"],
                            label="Document 4",
                            file_types=[".pdf", ".jpg", ".jpeg", ".png"],
                        )
                        b_doc5 = gr.File(
                            elem_classes=["civic-file-slot"],
                            label="Document 5 (optional)",
                            file_types=[".pdf", ".jpg", ".jpeg", ".png"],
                        )

                        analyze_btn_b = gr.Button(
                            "Check My Packet",
                            variant="primary",
                            size="lg",
                        )

                    with gr.Column(scale=2):
                        results_html_b = gr.HTML(label="Results")
                        with gr.Accordion("Raw JSON Output", open=False, elem_classes=["civic-json-accordion"]):
                            json_output_b = gr.Code(label="JSON", language="json")

                analyze_btn_b.click(
                    fn=process_track_b,
                    inputs=[b_doc1, b_doc2, b_doc3, b_doc4, b_doc5],
                    outputs=[results_html_b, json_output_b],
                    show_progress_on=results_html_b,
                )

    gr.HTML("""
    <div class="privacy-footer">
        <p><strong>Privacy Notice:</strong> This web demo sends your uploads to whatever inference backend
        configures this deployment (hosted API or server-side model).</p>
        <p>For strongest privacy — documents stay on your phone — use the <strong>CivicLens</strong>
        mobile app with on-device inference.</p>
    </div>
    """)

if __name__ == "__main__":
    demo.launch(
        server_name="0.0.0.0",
        server_port=7860,
        share=False,
        show_error=True,
        theme=civic_gradio_theme(),
        css=CUSTOM_CSS,
    )
