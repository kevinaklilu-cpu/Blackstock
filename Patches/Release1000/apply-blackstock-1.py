from pathlib import Path

ROOT = Path.cwd()


def replace_in(path: Path, old: str, new: str) -> None:
    if not path.exists():
        return
    text = path.read_text()
    if old in text:
        path.write_text(text.replace(old, new))


# Product identity: public release is Blackstock 1.0.
version_env = ROOT / "Build/version.env"
if not version_env.exists():
    raise SystemExit("Build/version.env fehlt")
lines = []
for line in version_env.read_text().splitlines():
    if line.startswith("APP_VERSION="):
        line = "APP_VERSION=1.0.0"
    elif line.startswith("BUILD_NUMBER="):
        line = "BUILD_NUMBER=100"
    lines.append(line)
version_env.write_text("\n".join(lines) + "\n")

# Keep generated release metadata, tests and audit aligned with the public version.
for relative in [
    "Sources/Blackstock/ReleaseInfo.swift",
    "Build/Release-Audit.sh",
    "Build/verify-release.zsh",
    "Build/build-app.zsh",
    "Build/create-dmg.zsh",
    "Tests/Release1000CoreTests.swift",
    "Tests/Release100CoreTests.swift",
    "Tests/ReleaseCoreTests.swift",
]:
    path = ROOT / relative
    replace_in(path, "1000.0.0", "1.0.0")
    replace_in(path, "100000", "100")
    replace_in(path, "Blackstock Next", "Blackstock 1.0")

# Remove the temporary generation codename from user-facing Swift source.
source_root = ROOT / "Sources/Blackstock"
if source_root.exists():
    for path in source_root.rglob("*.swift"):
        replace_in(path, "Blackstock Next", "Blackstock 1.0")

manifest = ROOT / "RELEASE_MANIFEST.txt"
manifest.write_text(
    "Blackstock 1.0.0 (Build 100)\n"
    "Product: Blackstock 1.0\n"
    "Bundle ID: de.blackstock.native\n"
    "Minimum macOS: 13.0\n"
    "Architectures: arm64 + x86_64\n"
    "Architecture: Creator Intelligence + Trends + Studio + Publishing + Analytics\n"
    "Creator flow: Channel -> Trends -> Preview -> Rights-aware Source -> Clip/Remix -> Studio -> Render -> Packaging -> Upload -> Analytics -> Learning\n"
)

print("BLACKSTOCK_1_PRODUCT_IDENTITY_OK")
