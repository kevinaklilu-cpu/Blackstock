# Release Gates

Status vocabulary is restricted to: **PASS**, **FAIL**, **BLOCKED_EXTERNAL**.

| Gate | Current status | Evidence required before PASS |
| --- | --- | --- |
| PRODUCT | FAIL | Complete canonical product journey implemented and tested |
| GUIDED EXPERIENCE | FAIL | 20-step guided journey acceptance passes |
| STRATEGY | FAIL | Versioned strategy model + UI + persistence + tests |
| LANGUAGE | FAIL | German product language + independent content language model |
| TERMINOLOGY | FAIL | Current YouTube/macOS terminology audit passes |
| RESEARCH | FAIL | Multi-source research system passes grounded E2E tests |
| TEMPORAL RESEARCH | FAIL | Required windows and time semantics pass real-data tests |
| GROUNDING | FAIL | Claim/source/timecode provenance and factuality gates pass |
| DISCOVERY | FAIL | Personalized diversified discovery passes |
| MEDIA | FAIL | Authorized media capability model and continuity pass |
| RIGHTS | FAIL | Rights ledger and publication rights gate pass |
| CAPTURE | FAIL | Camera/mic/screen/system-audio capture passes |
| EDITING | FAIL | Preview/storyboard/timeline + EditGraph + undo/redo pass |
| AUDIO | FAIL | Required professional audio toolset passes |
| CAPTIONS | FAIL | Required caption pipeline passes |
| PACKAGING | FAIL | Titles/thumbnails/description/chapters/review pass |
| VIDEO QUALITY | FAIL | Automated QC passes |
| 4K | FAIL | Verified 4K render path passes |
| PUBLISHING | FAIL | Official upload + publication preflight passes |
| WRONG CHANNEL | FAIL | Hard-stop E2E test passes |
| UPLOAD/RESUME | FAIL | Persisted resumable upload survives network failure |
| ANALYTICS | FAIL | Real authorized analytics only |
| COMMENTS | FAIL | Real comment workflows and safeguards pass |
| SECURITY | FAIL | Threat model and security tests pass |
| PRIVACY | FAIL | Disconnect/revoke/export/delete/retention pass |
| ACCESSIBILITY | FAIL | VoiceOver/keyboard/focus/reduced motion/contrast/text scaling pass |
| RECOVERY | FAIL | Crash/restart/sleep/network/token recovery pass |
| MIGRATION | FAIL | Migration suite protects older projects |
| INSTALLER | FAIL | Clean-machine Blackstock.pkg install passes |
| SIGNING | BLOCKED_EXTERNAL | Valid Apple Developer ID credentials and signed build |
| NOTARIZATION | BLOCKED_EXTERNAL | Apple notarization credentials/service result |
| GATEKEEPER | BLOCKED_EXTERNAL | Signed/notarized artifact verified by Gatekeeper |
| UPDATER | FAIL | Signed update path tested |
| CLEAN-MACHINE-E2E | FAIL | Full canonical clean-machine scenario passes |

A green compile, attractive UI, working login, render, upload, or existence of a package file is not sufficient for market readiness.
