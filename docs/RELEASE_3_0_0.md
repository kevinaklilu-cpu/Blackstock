# Blackstock 3.0.0 · Build 300

Internal release identifier; the interface remains Blackstock.

## Product changes

- Discovery now starts single-video projects. Removed multiple-selection controls and automatic multi-source suggestions; existing projects remain readable.
- Up to three search pages per action fill filtered results with distinct videos. Trend results retain search pagination. Time and format filters remain strict; API quotas and available results still apply.
- Dedicated Moments and Refinement workspaces, explicit Short/Video choice, optional captions.
- Speech-bounded candidate lengths (12–90 seconds for Shorts, 25–360 seconds for videos), whole-transcript candidate ranking and no implicit 45-second fallback when recognition fails.
- Optional Apple on-device model ranks measured candidate ranges by standalone clarity and payoff. Invalid model output falls back to deterministic ranking; the model cannot invent time ranges.
- Packaging derives from the selected clip transcript. Optional on-device generation creates original titles, description and relevant tags. Unavailable models retain extractive drafts; in-progress user edits are preserved.
- Corrected off-centre subject crop geometry. Dispersed faces can trigger full-frame fitting; automatic zooms are suppressed in that mode. This is sampled detection, not continuous tracking.
- Replaced Core Animation video postprocessing with timestamped frame composition for captions and overlays, with a bounded decoded-image cache. This fixes the previously observed CI scene replacement failure.

## Verification and limitations

Local debug build, 20 source-contract audits and synthetic export E2E pass. Export tests check scene pixels, audio and visible text. New regressions cover moment lengths, late-video candidates, metadata grounding, editorial response validation and portrait geometry. Full XCTest requires the Xcode CI toolchain; this Mac has Command Line Tools without XCTest.

No claim of guaranteed virality, flawless editing or equal results on every source. On-device speech recognition and Apple Intelligence availability depend on the Mac, installed language support and OS. Silent/unsupported content needs manual range selection. Captions remain optional. Public YouTube publishing is still subject to the existing API-project approval gate; this build does not bypass it. No live channel upload was performed as part of these checks.

Installer target: /Applications/Blackstock.app, universal arm64/x86_64. Without Apple Developer certificates the app is ad-hoc signed and the installer is not notarized.
