# Blackstock

Blackstock is a macOS workspace for the full YouTube workflow: discover what matters, understand why it matters, turn it into a project, edit, package, publish through official platform flows, and learn from real analytics.

The repository now has a clean Swift 6 foundation in `Sources/` rather than relying on generated UI as the product architecture.

## Build

```bash
swift test
swift build -c release
```

Requires macOS 13+ for the Blackstock app UI. Core ranking/cache/API logic is kept separate and testable.

## Product rules

See `docs/PRODUCT.md`. In particular: no opaque chance/virality scores, no fabricated metrics, and no fake upload completion states.
