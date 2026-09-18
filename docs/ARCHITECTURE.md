# Architecture

## Architectural direction

Blackstock is native macOS-first: Swift, SwiftUI, AppKit, Foundation, ScreenCaptureKit, WKWebView, AVFoundation, VideoToolbox, Metal, Core Image, Security/Keychain and Swift Concurrency where appropriate.

## Core layers

1. **Blackstock App** — German native UI, Blackstock Stage and user guidance.
2. **Domain Core** — strategies, projects, research, provenance, EditGraph, packaging, publication, analytics, insights.
3. **Capability Layer** — central CapabilityRegistry. No UI is rendered for a capability unless authorization, policy, region, channel, data, quality and test state pass.
4. **Provider Layer** — official Google/YouTube first; documented alternatives only when legally, technically and commercially acceptable.
5. **Media Layer** — authorized production sources, proxies, non-destructive editing, rendering, QC and continuity.
6. **Action Broker** — risk classification and deterministic checks before external side effects.
7. **Persistence & Recovery** — autosave, migrations, crash recovery, offline-capable local work.
8. **Control Plane** — server-side secrets, provider gateway, OAuth configuration, quota, background jobs, watchlists, notifications, feature flags, provider health and audit log where needed.
9. **Observability** — structured privacy-safe logs, correlation IDs, traces, error classes and performance signals.

## Hard invariants

- No fabricated data or state.
- No production capability exposed before real E2E validation.
- HistoricalChannelProfile and ChannelStrategy are separate.
- Product language and content language are separate.
- Publication target channel equality is mandatory.
- External content is untrusted input and cannot directly trigger remote actions.
- Remote high-impact actions require deterministic checks and user confirmation.
- Rights and provenance survive through the production and publication chain.
