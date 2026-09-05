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

## Milestone 02 — reliability

- Loopback-only playback proxy; LAN sharing requires an explicit file action and issues 24-hour random file grants. Cast server supports GET/HEAD and byte ranges. SMB inclusive/exclusive range boundary and reader cleanup corrected.
- Server passwords migrate to HarmonyOS Asset Store after successful writes, without plaintext fallback. **Older baseline builds cannot read migrated credentials; re-enter credentials if testing a pre-migration package.**
- Async library enumeration, cached modification times, revision-keyed video thumbnails and bounded thumbnail memory. Network modified-time sorting and disposed-page callbacks fixed.
- Sequential stream-cache writer with threshold-specific waiters; this growing-file playback path remains disabled.
- Removed unused external Chewie dependency (the app imports its embedded fork).
- Dart application analysis: no errors (archived examples and disabled SMB prototype excluded); 5 tests passed. HAP build passed with native Asset Store bridge. No device validation.

## Milestone 03 — network continuity

- Stable server/file identity, same-folder network queue and subtitle candidates. Saved network history reconnects the configured server and regenerates playback URLs.
- MPV awaits settings and queue initialization, restores after duration is available, checkpoints position every 5 seconds and on pause/background/exit. Player subscriptions are canceled before disposal.
- Opening media preserves existing progress; recent-list limits no longer delete long-term resume records.
- History toolbar links to Continue Watching / Listening with local/network filters, completed marker, and local-file relocation.
- Six tests passed including Unicode/percent/fragment filename identity; application Dart analysis has no errors; HAP build passed.

## Milestone 04 — playback tools

- Sleep timer across MPV, system video and both music services: 15/30/45/60/90 minutes or end of current item.
- MPV tools under player settings: subtitle/audio delay, language and track preference per media, named time bookmarks, saved AB segments, chapter navigation.
- Local subtitle matching respects episode boundaries and language preference; removed the delayed first-match callback.
- Eleven tests passed, including timer replacement/ownership, bookmark persistence and subtitle matching. Application Dart analysis has no errors; HAP build passed.

## Milestone 05 — persistent downloads

- Server page exposes a download task center. Network file downloads are persisted without passwords or proxy URLs; interrupted jobs restore paused.
- Sequential downloads support pause/resume/cancel/retry, source revision validation, free-space checks, partial-file isolation and atomic completion into Videos/Downloads or Audios/Downloads.
- Explicit LAN sharing action and stop-sharing action replace automatic LAN exposure on opening file options.
- Thirteen tests passed including a real temporary-file transfer that fails after 3 bytes and resumes from byte 3 to produce the exact 6-byte payload. Application analysis has no errors.
- First native build caught an SDK export naming mismatch (statvfs vs statfs); corrected to CoreFileKit.statfs and rebuilt successfully.
- No device is connected: long-running background transfer retention and public-library permissions still require device verification.

## Milestone 06 — indexed poster library and protocol regression

- Added SQLite-backed local poster library, incremental NFO/poster revision scanning, title/search/series filters and episode queues. Cancellation/inaccessible roots never prune existing records.
- Thumbnail requests are deduplicated and limited to two concurrent native operations.
- HTTP proxy shares the same range-capable source interface as downloads. Real loopback HTTP tests verify grants, suffix ranges, HEAD without file reads, and 416 handling.
- Sixteen tests passed; HAP build passed. Local NFO/poster support requires sidecar files already present beside the media; it does not download third-party metadata.

## Milestone 07 — Jellyfin / Emby

- Media-server entry supports login/edit/remove, secure access-token storage, paged browsing/search, authenticated posters, direct file playback and server progress reports. History reconnects by server/item identity.
- Playback URLs do not embed access tokens; headers carry authentication. Playback progress uses 10,000 ticks per millisecond.
- Eighteen tests passed, including a local mock server covering reverse-proxy URL prefixes, login headers, resume conversion, direct-stream construction and start/progress/stop reports. HAP build passed.
- Live streams and server-side transcoding are explicitly unsupported by this first connector; a real Jellyfin/Emby instance has not been exercised.
- Protocol references: https://dev.emby.media/doc/restapi/Video-Streaming.html and https://typescript-sdk.jellyfin.org/classes/generated-client.SessionApi.html .

## Milestone 08 — native picture-in-picture

- MPV settings now offer a system-PiP handoff page. It pauses the original decoder, creates one native XComponent/AVPlayer surface, carries the current position and HTTP authentication headers, and returns the position when leaving.
- The native view owns PiP controls, file descriptor and AVPlayer release; capability failure remains visible and the user can return to the original decoder.
- SDK compile corrected the exported name to ArkUI.PiPWindow. Native HAP build passed. **PiP has not been run on hardware; system decoding support differs from MPV and ASS effects are not carried into the native player.**

## Milestone 09 — continuity regression fixes

- Dedicated LAN listener and listener-scoped grants preserve loopback playback when sharing is toggled. WebDAV verifies Content-Range before returning bytes.
- SMB disconnect closes active range readers before releasing the native context. UI initialization and metadata editor no longer use asynchronous setState callbacks.
- Queue selection uses original source paths, avoiding Media URI normalization selecting the first item; files picked outside the queue are appended explicitly.
- PiP returns position and playback state, pauses its decoder before returning, and respects sleep-timer pauses even during preparation.
- Twenty tests passed, application analysis has no errors, native HAP build passed. Canonical unsigned HAP timestamp verified after build.
