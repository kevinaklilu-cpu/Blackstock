#!/usr/bin/env python3
"""Fetch pinned upstream binaries, verify SHA-256, and prepare universal macOS helpers."""
import hashlib
import pathlib
import subprocess
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / '.build' / 'download-tools'
OUT.mkdir(parents=True, exist_ok=True)
ASSETS = [
    ('yt-dlp', 'https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.19/yt-dlp_macos', '0f192b7ec147ab6288885d6351d9ab67367640029b4377576ef46dd79cf7b202'),
    ('deno-arm64.zip', 'https://github.com/denoland/deno/releases/download/v2.9.7/deno-aarch64-apple-darwin.zip', '5cd46d6268f6f78f5d88bdc7159d20bd44cdaa4b3303474839f87ec6fe7ae25c'),
    ('deno-x86_64.zip', 'https://github.com/denoland/deno/releases/download/v2.9.7/deno-x86_64-apple-darwin.zip', '95daaff11c116a52ad54785e7914c8e9c9cdcaba793c5ed929c74ca2d8e6259a'),
]
for name, url, digest in ASSETS:
    path = OUT / name
    if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        temporary = path.with_suffix('.download')
        subprocess.run(['curl', '--fail', '--location', '--retry', '3', url, '-o', str(temporary)], check=True)
        if hashlib.sha256(temporary.read_bytes()).hexdigest() != digest:
            temporary.unlink()
            raise SystemExit(f'Checksum mismatch: {name}')
        temporary.replace(path)
    print(f'Verified {name}')
    if name.endswith('.zip'):
        arch = name.removeprefix('deno-').removesuffix('.zip')
        with zipfile.ZipFile(path) as archive:
            (OUT / f'deno-{arch}').write_bytes(archive.read('deno'))
subprocess.run(['lipo', '-create', str(OUT / 'deno-arm64'), str(OUT / 'deno-x86_64'), '-output', str(OUT / 'deno')], check=True)
for name in ('yt-dlp', 'deno'):
    (OUT / name).chmod(0o755)
print(OUT)
