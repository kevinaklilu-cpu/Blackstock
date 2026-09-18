# BLACKSTOCK — Master Requirements

## Canonical authority

This repository is being rebuilt against the **FINAL CANONICAL MASTER PROMPT** supplied on 2026-09-18.

Canonical payload SHA-256:

`23c51e7d90ca653c92b04b19a7b65615fdf420f581caa16024725c4935bde827`

The canonical prompt contains **218 numbered sections (0–217)**. Earlier prompts, addenda, product assumptions, generated release claims and architecture decisions have no authority when they conflict with that prompt.

## Non-negotiable engineering rules

1. Blackstock is a native macOS Creator Intelligence, Research, Production, Publishing & Growth Operating System for YouTube.
2. Final installation artifact: `Blackstock.pkg`; installation target: `/Applications/Blackstock.app`.
3. UI visibility is capability-driven. A user-facing function is hidden until real implementation, real data, authorization, policy, quality and end-to-end test gates all pass.
4. Product language is German; content language is an independent project-level model.
5. Evidence and provenance are mandatory. Trends, metrics, progress, publication state and revenue must never be fabricated.
6. Research time semantics must distinguish `PUBLISHED_IN_WINDOW`, `OBSERVED_IN_WINDOW`, `ANALYTICS_PERIOD` and `EXTERNAL_TREND_PERIOD`.
7. Editing is non-destructive and must converge through Vorschau → Storyboard → Timeline with reversible operations.
8. Production media access must be authorized. Blackstock must not become a hidden downloader.
9. Publication uses deterministic preflight checks. The target channel invariant is a hard stop.
10. Remote high-impact actions require deterministic checks and appropriate user confirmation.
11. Requirement status is restricted to `PASS`, `FAIL`, `BLOCKED_EXTERNAL`. Missing code, tests, UX or documentation are `FAIL`, never `BLOCKED_EXTERNAL`.
12. Market readiness is reached only when the complete real user journey and all critical gates pass on a clean supported Mac.
13. Stable release pipeline: BUILD → LINT → TEST → ARCHIVE → SIGN → HARDENED RUNTIME VERIFY → PACKAGE → INSTALLER SIGN → NOTARIZE → NOTARY LOG → STAPLE → GATEKEEPER VERIFY → CLEAN INSTALL → E2E → CHECKSUM → RELEASE.

## Required domains

The canonical requirement namespace includes:
`BS-ONB-*`, `BS-STRAT-*`, `BS-LANG-*`, `BS-UX-*`, `BS-GUIDE-*`, `BS-API-*`, `BS-SEARCH-*`, `BS-RESEARCH-*`, `BS-TIME-*`, `BS-DISC-*`, `BS-MEDIA-*`, `BS-RIGHTS-*`, `BS-PROD-*`, `BS-CAPTURE-*`, `BS-EDIT-*`, `BS-AUDIO-*`, `BS-CAPTION-*`, `BS-PACK-*`, `BS-RENDER-*`, `BS-PUB-*`, `BS-LIVE-*`, `BS-COMMENT-*`, `BS-ANA-*`, `BS-REV-*`, `BS-GROWTH-*`, `BS-SEC-*`, `BS-PRIV-*`, `BS-A11Y-*`, `BS-REL-*`.

## Current status

**STATUS: NOCH NICHT MARKTREIF**

This status may only change when all critical requirements and release gates are demonstrably `PASS`.
