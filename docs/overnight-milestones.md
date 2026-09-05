# Overnight implementation — 2026-09-06

All HAP builds use the installed Flutter 3.41 OHOS SDK at `E:\source\flutter_327`, outside the sandbox. No debugging device is connected.

Artifacts are kept in `build/milestones/<milestone>/` with unsigned/signed HAPs when produced, timestamps, SHA-256 hashes, source commit and worktree state. The canonical build output remains `ohos/entry/build/default/outputs/default/entry-default-unsigned.hap`.

## Work sequence

1. Baseline and reproducible milestone packaging.
2. Network proxy, casting ranges, credentials, library cache/scanning and sorting fixes.
3. Stable media identity, network queue/resume and playback persistence.
4. Playback tools: sleep timer, subtitle/audio preferences, chapters and bookmarks.
5. Persistent downloads, continue-watching and media-library extensions.
6. Regression checks, final packages and device verification guide.

Each completed milestone is committed separately. Build success is not a substitute for device validation. Device-dependent capabilities and any remaining work are recorded here before handoff.

## Installation

Start with the newest signed HAP. Keep existing app data when comparing versions; a version downgrade may require the deployment tool's replacement/downgrade option or re-signing for the target device. Do not uninstall casually: it can remove history and server credentials. Unsigned HAPs require signing before installation.
