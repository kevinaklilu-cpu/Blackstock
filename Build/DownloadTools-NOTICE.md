# Download components

Blackstock bundles unmodified yt-dlp 2026.08.19 macOS release binaries and Deno 2.9.7.

- yt-dlp source and licenses: https://github.com/yt-dlp/yt-dlp/tree/2026.08.19
  The macOS PyInstaller executable includes GPLv3+ components. See upstream LICENSE
  and THIRD_PARTY_LICENSES.txt, and the corresponding source release:
  https://github.com/yt-dlp/yt-dlp/releases/tag/2026.08.19
- Deno source and MIT license: https://github.com/denoland/deno/tree/v2.9.7
  Third-party notices: https://github.com/denoland/deno/blob/v2.9.7/third_party.txt

Build/prepare_download_tools.py pins upstream assets and SHA-256 hashes.
The helpers run as separate processes. No cookies or browser credentials are read.
