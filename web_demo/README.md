# CivicLens Web Demo

A privacy-first civic document intelligence demo using Gemma 4 E4B.

## Overview

This web demo helps residents prepare document packets for:
- **SNAP Benefits** (Track A): Check recertification documents against DTA notices
- **School Enrollment** (Track B): Verify BPS registration packet completeness

## Features

- Document upload (PDF, JPG, PNG)
- Blur detection pre-processing
- Gemma 4 E4B inference via Ollama
- Confidence visualization with color-coded results
- Plain-language action summaries

## Local Development

1. Install Ollama and pull Gemma 4 E4B:
```bash
ollama pull gemma4:e4b
```

2. Install Python dependencies:
```bash
pip install -r requirements.txt
```

3. Run the app:
```bash
python app.py
```

The app will be available at http://localhost:7860

## Deployment

This demo is designed for Hugging Face Spaces. Push to a Space with:
- SDK: Docker
- Port: 7860

## Privacy Notice

This demo processes documents on the server where it's hosted. For true
privacy with on-device inference, use the CivicLens mobile app.

## Architecture

- **Gradio**: Web UI framework
- **Ollama**: Local LLM inference
- **Gemma 4 E4B**: Multimodal document understanding
- **Blur detection**: Laplacian variance method

## Design System

Based on the CivicLens Institutional design system:
- Primary: #002444 (dark navy)
- Success: #10B981 (green)
- Warning: #F59E0B (amber)
- Error: #EF4444 (red)
- Font: Inter
