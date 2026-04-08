"""
CivicLens Web Demo - Gradio Application

A privacy-first civic document intelligence demo using Gemma 4 E4B.
Helps residents prepare document packets for SNAP recertification and school enrollment.
"""

import json
from pathlib import Path

import gradio as gr

from inference import run_track_a, run_track_b

# Design system colors from Agent 4 spec
COLORS = {
    "primary": "#002444",
    "primary_container": "#1A3A5C",
    "surface": "#F7F9FB",
    "surface_container": "#ECEEF0",
    "surface_container_lowest": "#FFFFFF",
    "success": "#10B981",
    "warning": "#F59E0B",
    "error": "#EF4444",
    "neutral": "#64748B",
    "light_green": "#F0FDF4",
    "light_amber": "#FFFBEB",
    "light_red": "#FFF3F3",
    "light_blue": "#EFF6FF",
}

# Custom CSS for CivicLens design system
CUSTOM_CSS = f"""
:root {{
    --primary: {COLORS['primary']};
    --success: {COLORS['success']};
    --warning: {COLORS['warning']};
    --error: {COLORS['error']};
    --surface: {COLORS['surface']};
}}

/* Mobile viewport optimization */
@media (max-width: 768px) {{
    .civiclens-header h1 {{
        font-size: 22px !important;
    }}
    .civiclens-header p {{
        font-size: 12px !important;
    }}
    .requirement-row {{
        flex-direction: column !important;
        align-items: flex-start !important;
    }}
    .requirement-row > div:last-child {{
        margin-top: 12px;
        text-align: left !important;
    }}
}}

/* Ensure touch targets are at least 48px */
.gr-button {{
    min-height: 48px !important;
    min-width: 48px !important;
}}

.gr-file-upload {{
    min-height: 48px !important;
}}

/* Improve text readability on mobile */
body {{
    font-size: 16px !important;
    line-height: 1.5 !important;
}}

.civiclens-header {{
    text-align: center;
    padding: 24px 0;
    background: linear-gradient(135deg, {COLORS['primary']} 0%, {COLORS['primary_container']} 100%);
    color: white;
    border-radius: 8px;
    margin-bottom: 24px;
}}

.civiclens-header h1 {{
    margin: 0;
    font-size: 28px;
    font-weight: 700;
    letter-spacing: -0.02em;
}}

.civiclens-header p {{
    margin: 8px 0 0 0;
    font-size: 14px;
    opacity: 0.9;
}}

.status-satisfied {{
    background-color: {COLORS['light_green']};
    color: {COLORS['success']};
    padding: 8px 16px;
    border-radius: 12px;
    font-weight: 600;
    display: inline-block;
}}

.status-questionable {{
    background-color: {COLORS['light_amber']};
    color: #B45309;
    padding: 8px 16px;
    border-radius: 12px;
    font-weight: 600;
    display: inline-block;
}}

.status-missing {{
    background-color: {COLORS['light_red']};
    color: {COLORS['error']};
    padding: 8px 16px;
    border-radius: 12px;
    font-weight: 600;
    display: inline-block;
}}

.status-uncertain {{
    background-color: #F3F4F6;
    color: {COLORS['neutral']};
    padding: 8px 16px;
    border-radius: 12px;
    font-weight: 600;
    display: inline-block;
}}

.action-summary {{
    background-color: {COLORS['light_blue']};
    border-left: 4px solid {COLORS['primary']};
    padding: 20px;
    border-radius: 4px;
    margin: 16px 0;
}}

.warning-banner {{
    background-color: {COLORS['light_amber']};
    border-left: 4px solid {COLORS['warning']};
    padding: 12px 16px;
    border-radius: 4px;
    margin: 16px 0;
}}

.confidence-high {{
    color: {COLORS['success']};
    font-weight: 600;
}}

.confidence-medium {{
    color: {COLORS['warning']};
    font-weight: 600;
}}

.confidence-low {{
    color: {COLORS['error']};
    font-weight: 600;
}}

.requirement-row {{
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 16px;
    background: white;
    border: 1px solid #E5E7EB;
    border-radius: 8px;
    margin: 8px 0;
}}

.proof-pack-item {{
    padding: 16px;
    background: white;
    border: 1px solid #E5E7EB;
    border-radius: 8px;
    margin: 8px 0;
}}

.privacy-footer {{
    text-align: center;
    padding: 16px;
    color: {COLORS['neutral']};
    font-size: 12px;
    margin-top: 24px;
}}

.gr-button-primary {{
    background-color: {COLORS['primary']} !important;
}}

.gr-button-primary:hover {{
    background-color: {COLORS['primary_container']} !important;
}}
"""


def format_track_b_results(result: dict) -> str:
    """Format Track B results as HTML."""
    if not result.get("success"):
        error_msg = result.get("error", "Unknown error")
        raw = result.get("raw_response", "")
        return f"""
        <div style="padding: 16px; background-color: {COLORS['light_red']}; border-radius: 8px;">
            <h3 style="color: {COLORS['error']}; margin-top: 0;">Error Processing Documents</h3>
            <p>{error_msg}</p>
            <details>
                <summary>Raw Response (for debugging)</summary>
                <pre style="font-size: 11px; overflow-x: auto;">{raw}</pre>
            </details>
        </div>
        """

    parsed = result.get("parsed", {})
    blur_warnings = result.get("blur_warnings", [])

    html_parts = []

    # Blur warnings
    if blur_warnings:
        html_parts.append(f"""
        <div class="warning-banner">
            <strong>⚠️ Image Quality Warning</strong><br>
            {"<br>".join(blur_warnings)}
        </div>
        """)

    # Requirements checklist
    requirements = parsed.get("requirements", [])
    if requirements:
        html_parts.append("<h3>Requirements Checklist</h3>")
        for req in requirements:
            status = req.get("status", "unknown")
            confidence = req.get("confidence", "medium")
            req_name = req.get("requirement", "Unknown")
            matched_doc = req.get("matched_document", "MISSING")
            evidence = req.get("evidence", "")
            notes = req.get("notes", "")

            status_class = f"status-{status}"
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
                    <span class="{status_class}">{status.upper()}</span>
                    <div style="font-size: 11px; margin-top: 4px;" class="{confidence_class}">
                        {confidence} confidence
                    </div>
                </div>
            </div>
            """)

    # Duplicate category warning
    if parsed.get("duplicate_category_flag"):
        html_parts.append(f"""
        <div class="warning-banner">
            <strong>⚠️ Duplicate Category Warning</strong><br>
            {parsed.get("duplicate_category_explanation", "Two documents from the same category count as only ONE proof. You need a second document from a different category.")}
        </div>
        """)

    # Family summary
    family_summary = parsed.get("family_summary", "")
    if family_summary:
        html_parts.append(f"""
        <div class="action-summary">
            <h3 style="margin-top: 0; color: {COLORS['primary']};">What to Bring to Registration</h3>
            <p style="margin-bottom: 0; line-height: 1.6;">{family_summary}</p>
        </div>
        """)

    return "\n".join(html_parts)


def format_track_a_results(result: dict) -> str:
    """Format Track A results as HTML."""
    if not result.get("success"):
        error_msg = result.get("error", "Unknown error")
        raw = result.get("raw_response", "")
        return f"""
        <div style="padding: 16px; background-color: {COLORS['light_red']}; border-radius: 8px;">
            <h3 style="color: {COLORS['error']}; margin-top: 0;">Error Processing Documents</h3>
            <p>{error_msg}</p>
            <details>
                <summary>Raw Response (for debugging)</summary>
                <pre style="font-size: 11px; overflow-x: auto;">{raw}</pre>
            </details>
        </div>
        """

    parsed = result.get("parsed", {})
    blur_warnings = result.get("blur_warnings", [])

    html_parts = []

    # Blur warnings
    if blur_warnings:
        html_parts.append(f"""
        <div class="warning-banner">
            <strong>⚠️ Image Quality Warning</strong><br>
            {"<br>".join(blur_warnings)}
        </div>
        """)

    # Notice summary
    notice_summary = parsed.get("notice_summary", {})
    if notice_summary:
        deadline = notice_summary.get("deadline", "")
        categories = notice_summary.get("requested_categories", [])
        consequence = notice_summary.get("consequence", "")

        if deadline or categories:
            html_parts.append(f"""
            <div style="background: white; border: 1px solid #E5E7EB; border-radius: 8px; padding: 16px; margin: 16px 0;">
                <h3 style="margin-top: 0; color: {COLORS['primary']};">Notice Summary</h3>
                {f'<div style="font-size: 24px; font-weight: 700; color: {COLORS["primary"]}; margin: 8px 0;">Deadline: {deadline}</div>' if deadline and deadline != "UNCERTAIN" else ""}
                {f'<div style="color: {COLORS["warning"]}; font-weight: 600;">⚠️ Deadline unclear — please contact DTA at (617) 348-8400</div>' if deadline == "UNCERTAIN" else ""}
                {f'<div style="margin-top: 8px;"><strong>Required:</strong> {", ".join(categories)}</div>' if categories else ""}
                {f'<div style="margin-top: 8px; color: #6B7280;">{consequence}</div>' if consequence else ""}
            </div>
            """)

    # Proof pack
    proof_pack = parsed.get("proof_pack", [])
    if proof_pack:
        html_parts.append("<h3>Your Proof Pack</h3>")
        for item in proof_pack:
            category = item.get("category", "Unknown")
            assessment = item.get("assessment", "uncertain")
            confidence = item.get("confidence", "medium")
            matched_doc = item.get("matched_document", "MISSING")
            evidence = item.get("evidence", "")
            caveats = item.get("caveats", "")

            status_class = f"status-{assessment.replace('likely_', '').replace('does_not_satisfy', 'missing')}"
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
                        <span class="{status_class}">{assessment.replace('_', ' ').upper()}</span>
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

    return "\n".join(html_parts)


def process_track_a(notice, doc1, doc2, doc3):
    """Process Track A documents and return formatted results."""
    if notice is None:
        return "Please upload a government notice to begin.", ""

    result = run_track_a(notice, doc1, doc2, doc3)
    html_output = format_track_a_results(result)
    json_output = json.dumps(result.get("parsed", {}), indent=2) if result.get("parsed") else result.get("raw_response", "")
    return html_output, json_output


def process_track_b(doc1, doc2, doc3, doc4, doc5):
    """Process Track B documents and return formatted results."""
    if doc1 is None:
        return "Please upload at least one document to begin.", ""

    result = run_track_b(doc1, doc2, doc3, doc4, doc5)
    html_output = format_track_b_results(result)
    json_output = json.dumps(result.get("parsed", {}), indent=2) if result.get("parsed") else result.get("raw_response", "")
    return html_output, json_output


# Build the Gradio interface
with gr.Blocks(title="CivicLens") as demo:
    # Viewport meta tag for mobile
    gr.HTML("""
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=5.0">
    """)

    # Header
    gr.HTML(f"""
    <div class="civiclens-header">
        <h1>CivicLens</h1>
        <p>Privacy-First Civic Document Intelligence | Documents stay on your device</p>
    </div>
    """)

    # Tabbed interface for Track A and Track B
    with gr.Tabs():
        # Track A: SNAP Benefits
        with gr.Tab("SNAP Benefits"):
            gr.Markdown("""
            ### SNAP Document Assistant

            Upload your DTA verification or recertification notice and your supporting documents.
            CivicLens will identify what proof categories are needed and assess whether your documents satisfy them.
            """)

            with gr.Row():
                with gr.Column(scale=1):
                    notice_input = gr.File(
                        label="Government Notice (required)",
                        file_types=[".pdf", ".jpg", ".jpeg", ".png"],
                    )
                    doc1_input = gr.File(
                        label="Document 1",
                        file_types=[".pdf", ".jpg", ".jpeg", ".png"],
                    )
                    doc2_input = gr.File(
                        label="Document 2 (optional)",
                        file_types=[".pdf", ".jpg", ".jpeg", ".png"],
                    )
                    doc3_input = gr.File(
                        label="Document 3 (optional)",
                        file_types=[".pdf", ".jpg", ".jpeg", ".png"],
                    )

                    analyze_btn_a = gr.Button(
                        "Analyze Documents",
                        variant="primary",
                        size="lg",
                    )

                with gr.Column(scale=2):
                    results_html_a = gr.HTML(label="Results")
                    with gr.Accordion("Raw JSON Output", open=False):
                        json_output_a = gr.Code(label="JSON", language="json")

            analyze_btn_a.click(
                fn=process_track_a,
                inputs=[notice_input, doc1_input, doc2_input, doc3_input],
                outputs=[results_html_a, json_output_a],
            )

        # Track B: School Enrollment
        with gr.Tab("School Enrollment"):
            gr.Markdown("""
            ### BPS Enrollment Packet Checker

            Upload your documents for Boston Public Schools registration.
            CivicLens checks against the four BPS requirements:
            - Proof of child's age
            - Two proofs of residency from **different** categories
            - Current immunization record
            - Grade indicator (optional)
            """)

            with gr.Row():
                with gr.Column(scale=1):
                    b_doc1 = gr.File(
                        label="Document 1 (required)",
                        file_types=[".pdf", ".jpg", ".jpeg", ".png"],
                    )
                    b_doc2 = gr.File(
                        label="Document 2",
                        file_types=[".pdf", ".jpg", ".jpeg", ".png"],
                    )
                    b_doc3 = gr.File(
                        label="Document 3",
                        file_types=[".pdf", ".jpg", ".jpeg", ".png"],
                    )
                    b_doc4 = gr.File(
                        label="Document 4",
                        file_types=[".pdf", ".jpg", ".jpeg", ".png"],
                    )
                    b_doc5 = gr.File(
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
                    with gr.Accordion("Raw JSON Output", open=False):
                        json_output_b = gr.Code(label="JSON", language="json")

            analyze_btn_b.click(
                fn=process_track_b,
                inputs=[b_doc1, b_doc2, b_doc3, b_doc4, b_doc5],
                outputs=[results_html_b, json_output_b],
            )

    # Privacy footer
    gr.HTML(f"""
    <div class="privacy-footer">
        <p><strong>Privacy Notice:</strong> This demo uses local inference with Gemma 4 E4B via Ollama.</p>
        <p>Documents are processed on this server. For true privacy, use the mobile app with on-device inference.</p>
    </div>
    """)

if __name__ == "__main__":
    demo.launch(
        server_name="0.0.0.0",
        server_port=7860,
        share=False,
        show_error=True,
        css=CUSTOM_CSS,
    )
