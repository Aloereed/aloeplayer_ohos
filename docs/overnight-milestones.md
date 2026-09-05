# Overnight implementation — 2026-09-06

This document records the first round (00–16). Follow-up fixes, UI changes and FSR (17–28) are in [round2-milestones.md](round2-milestones.md). The newest packages and current checks are linked from [morning-verification.md](morning-verification.md).

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

Start with the newest signed HAP. Keep existing app data when comparing versions; the supplied deploy script uses API 23+ bm install -r -d for debug-signed downgrade installation. A different target device may require re-signing. Do not uninstall casually: it can remove history and server credentials. Unsigned HAPs require signing before installation.

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

## Milestone 10 — bounded caches and background audio indexing

- Video revision thumbnails have a 256 MiB disk budget, serialized atomic writes and least-recently-used eviction. Only hash-named cache JPEGs are owned; user posters and media are not removed. Local shortcut revisions track their target.
- Audio tag parsing runs in worker isolates with revision caching. Full-library indexes no longer retain every embedded cover; visible items load covers through a bounded queue/memory cache and limited decoded image width. Superseded scans cannot overwrite the latest folder.
- A real WAV regression uncovered a self-waiting Future in pending-task cleanup, fixed for video thumbnails and audio work. **If testing milestones 06–09 and thumbnails remain blank, compare milestone 10 or newer.**
- Twenty-two tests passed, including real WAV parsing/invalidation and disk-cache eviction. Application analysis has no errors; HAP build passed and canonical timestamp verified. No measured device performance claims are made.

## Milestone 11 — migration safety and explicit resume

- Serialized configuration read-modify-write across service instances for SMB, WebDAV and media servers. Failed operations do not poison later work.
- Credential regression checks verify a failed keystore migration retains original data, a successful migration removes plaintext, concurrent saves retain both servers, and removal deletes the matching secret.
- Continue Watching explicitly supplies its saved position; network subtitle selection respects stored language preference.
- Twenty-four tests passed, application analysis has no errors, HAP build passed and canonical timestamp verified.

## Milestone 12 — system background downloads

- Downloads request a HarmonyOS data-transfer continuous task and release only their own task ID. If denied, the task center explains foreground-only operation; a system cancellation pauses active/queued work for later resume.
- Cleanup closes streams, writers and connections even when an individual release fails. Finished-record cleanup preserves downloaded files; duplicate concurrent additions are rejected.
- Twenty-six tests passed, including pause/cancel during an open stream and release completion before returning. Native HAP build passed and canonical timestamp verified.
- Background task APIs compile against the configured HarmonyOS SDK; notification authorization, OS cancellation and long-duration retention still require device validation.

## Milestone 13 — effective SMB security and metadata boundaries

- SMB encryption/signing now call the native seal/sign controls; required signing includes the enabled bit. Added a 30-second native operation timeout. Exported functions were checked in the exact packaged libsmb2.so.
- libsmb2 stat fields are Unix seconds/nanoseconds, not Windows FILETIME. Corrected timestamps and added a fractional-revision regression. Existing SMB download tasks created with the old incorrect revision may report source changes; cancel/re-add those jobs rather than bypassing revision protection.
- Server pages guard disposed callbacks; catalog scans reject overlapping starts; metadata editing validates numeric fields and reports write failures.
- Twenty-seven full-suite tests passed, HAP build passed and canonical timestamp verified. A separate worker-isolate scaffold test also passed; that scaffold is integrated in the next milestone.

## Milestone 14 — SMB worker isolation

- SMB browsing, stat, connection and range reads now run in a dedicated worker isolate. One worker owns one native context and serializes native operations; credentials remain in the main-isolate secure store.
- Pull-based TransferableTypedData chunks preserve stream backpressure. Cancel closes the worker reader; disconnect releases readers/context and ends the isolate; reconnect creates a new owner.
- Twenty-nine tests passed. Worker tests simulate a blocking backend while a main-isolate timer keeps running, exercise range/cancellation/error/reconnect, and check inclusive FileService boundaries through the actual adapter. HAP build passed and canonical timestamp verified.
- Mock backend tests do not validate real NAS behavior. Compare milestone 13 if a device-specific SMB worker issue occurs.

## Milestone 15 — reproducible dependencies and artifact checks

- Pinned direct package versions and direct/transitive Git forks to the implementations already in pubspec.lock. A before/after lock comparison confirmed no package version or resolved Git implementation changed.
- build.ps1 accepts -Offline, -Locked and -NoVersionBump. HAP success now also requires a refreshed canonical unsigned output timestamp.
- Archiving cross-checks embedded HAP versionCode against pubspec.yaml and records bundle/API versions, SDK identity and lock-file hash.
- Twenty-nine tests passed; application analysis has no errors; an offline, enforced-lockfile HAP build passed with canonical timestamp verification.

## Milestone 16 — native bridge and PiP checkpoints

- Verified current Flutter OHOS StandardMessageCodec decodes creation parameters as Map. PiP, cast, HDR and FFmpeg native views now read Map entries; PiP converts nested authentication headers to the system MediaSource format.
- PiP emits progress checkpoints every five seconds and on playback state changes, so history/server progress can survive leaving the app. Lock-screen play/pause/seek controls target the active native decoder; next/previous are held while PiP owns playback.
- Browser callbacks and catalog retry feedback received final lifecycle guards.
- Twenty-nine tests passed, application analysis has no errors; offline/locked native HAP build passed and canonical timestamp verified. **For PiP validation use milestone 16 or newer; earlier PiP archives used the incorrect creation-parameter access.**
- PiP currently uses system decoding at normal speed; MPV subtitle rendering/rate preferences are not carried into that decoder.


## Handoff verification

- 17 archived milestones (00 is the pre-existing baseline), 34 HAP files. All archived file sizes and SHA-256 hashes verified.
- Recommended application build: 16-native-bridge-final, version 3.1.1+164, source commit 55ac5ee.
- Deployment helper dry-run passed. It selects one device explicitly when multiple devices exist, verifies the local HAP hash, and uses a hash-specific remote filename to avoid deploying a stale different milestone after a failed transfer.
- No device deployment was performed. Current packages retain the project's existing debug signing and API 23 minimum.
- Installation index: build/milestones/README.md. Chinese device workflow: docs/morning-verification.md. Analysis and feature scope: docs/repository-review-2026-09-06.md.
