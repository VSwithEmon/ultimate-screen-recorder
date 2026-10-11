# Progress

Last updated: 2026-10-11 (v0.4.0: optional share links). Truthful status only; "done" means verified.

## PRD v2 phase status
| # | Phase | Status | Evidence / gap |
|---|---|---|---|
| 1 | Landing page | **Done (needs your visual review)** | `site/index.html`; checked in the in-app browser at 375, 1280, 1440, 1920 px: no horizontal overflow, mobile layout fixed. Download buttons are disabled and say "Coming soon". Not yet compared pixel-by-pixel with the reference photos. |
| 2 | GitHub | **Repo live; Pages deploy being verified** | Public repo `VSwithEmon/ultimate-screen-recorder`, pushed over SSH. Pages source set to GitHub Actions. `gh` CLI login could not be saved because `~/.config` is root-owned; SSH + browser were used instead. |
| 3 | Recorder MVP (macOS) | **Built; real capture NOT yet verified** | Display + system audio + mic + camera capture to separate synced files, cursor/click metadata, crash-safe project package. Needs Screen Recording / Mic / Camera permission to test; manual QA in `apps/macos-native/docs/PHASE0.md`. Floating recorder with Display / Window / Area modes, device menus, camera preview, mic meter, countdown, saved areas, hide-desktop-icons, speaker notes (v0.2.0). Not built: iPhone/iPad (Device) capture, per-app audio, pause, recovery screen, mic noise reduction, configurable shortcuts. |
| 4 | Editor MVP | **Built; verified on synthetic projects, not on a real recording** | Native SwiftUI editor (`apps/macos-native`): live preview and export share one renderer (`FrameRenderer`); backgrounds (wallpaper/gradient/colour/image), padding, rounded corners, shadow, aspect presets, crop, trim, undo/redo, autosave, presets, timeline with waveform. Verified by 40 tests (rendered-pixel checks + real MP4 export) and by running the app on a demo project. |
| 5 | Signature features | **Mostly built (macOS)** | Cursor smoothing, click effects (Circle/Ripple), hide-when-idle, manual and automatic zoom from clicks, 3×3 camera layout, sensitive/highlight masks (solid verified to cover pixels under zoom). Not built: camera layouts over time, click sounds, cursor rotation, loop-cursor. |
| 6 | Windows capture | Not started, untested | No Windows machine available here. |
| 7 | Advanced | Not started | |
| 8 | Distribution | Not started | No installers exist. |

## Decisions and deviations
- **Stack:** PRD recommends Tauri 2 + React/TypeScript. **Rust/cargo is not installed** on this Mac, so Tauri cannot be built yet. The only working capture code is native Swift, which stays as `apps/macos-native` for now. Decision needed from you: (a) install Rust and build the Tauri shell around native capture plugins, or (b) keep native SwiftUI for macOS and do a separate Windows app. Not decided; no code assumes either.
- **Reference photos:** 19 (not 26) found in `~/Downloads/IMG_2655–2673`. Not copied into the repo. See `docs/DESIGN_REFERENCE.md` for what they do and do not cover (recording toolbar, area picker, export dialog were not photographed).
- **Landing mockup:** original HTML/CSS drawing of the editor layout, labelled as a design concept, with original icons and a generic avatar. It is not a working UI.
- **Landing page uses system fonts** (no external requests).

## What is verified vs not
- Verified (automated): geometry, project persistence, zoom/cursor engines, renderer output pixels (padding, corners, crop, zoom, masks, cursor, camera), MP4 export (1080p30 H.264, audio offset alignment, trim, cancel, aspect), schema back-compat. 40 tests.
- Verified (manual, this session): app builds, launches, opens a project, auto-zoom/mask inserted via menu, playhead scrub renders zoomed preview.
- Verified (automated, v0.2.0): area geometry (handles, ratio lock, Retina px, clamping, saved areas), cursor mapping into an area region. 51 tests total.
- **Not verified:** window/area/display picking with a mouse, a real screen recording on your Mac (permissions), mic/screen sync on real hardware, camera capture, drag interactions with a mouse (resize/move events), export via the Save dialog, 4K60 performance.
- Not built: Windows (all), window/area capture, pause, captions/Whisper, noise reduction, music, shortcut overlays, installers/DMG, signing.

## v0.3.0 fixes (from real use)
- **Editor hang after recording (root cause):** the camera file's first frame carried a stale timestamp near zero, so the file was ~374,000 s long and the editor built a 104-hour timeline. Fixed at capture (implausible device timestamps are dropped; every file now ends at the true stop time, which also stops static screens being cut short) and on load (older recordings are repaired by skipping the stale frame). Regression tests added; verified on the user's real recordings (4.6 s / 60.6 s / 22.9 s timelines).
- **Cursor log was nearly empty:** global event monitors are unreliable; now polled at 90 Hz with no special permission.
- Playback no longer redraws the whole editor 30 times a second (playhead and time label only).
- Loading screen text was nearly invisible; fixed.
- Recorder windows (timer, preview, notes, toolbar) are created before capture starts, hidden from screen sharing and excluded as an app, so they cannot appear in a recording.
- New after-recording window: Open in editor, Restart recording (moves the take to the Trash and starts again with the same settings), Discard, Close. It appears after capture has stopped.
- App icon added (from the supplied logo) to the app, DMG contents and site.

## v0.4.0: optional share links (EXPERIMENTAL, live hosts unverified)
- "Get shareable link" in the after-recording window and "Share link" in the editor: exports 1080p (falls back to 720p/480p to fit the host's limit) to a temp MP4, uploads it, copies the link, deletes the temp file. Opt-in only: a consent checkbox is required and nothing is uploaded otherwise.
- Hosts: Litterbox (24 h / 72 h expiring, up to 1 GB) and Catbox (permanent, up to 200 MB). Free, no account. They are third parties we don't control: links are public to anyone who has them, and files can be removed.
- **Verified:** multipart body (fields + exact file bytes), https-only link parsing, size limits checked before anything is sent, error handling, full export-then-upload flow with a stub uploader (70 tests, no network).
- **NOT verified:** the live Litterbox/Catbox APIs. The environment blocked probing third-party upload hosts, so the request format follows each service's public documentation and has not been run against the real servers. The first real upload will confirm or fail visibly ("Couldn't create a link"; nothing is shared and the recording is untouched).
- Not built: your own storage (S3/Cloudflare R2), password-protected or view-limited links, analytics. A private link host would need a server and an account; ask if you want that.

## v0.3.1
- Restart button on the recording timer (two-step: first click arms "Discard & restart?"); stops, trashes the take and starts again with the same target and settings.
- Toolbar labels were dark-on-dark when macOS was in light appearance (panels followed the system appearance). All recorder panels and their menus are now forced to dark appearance; text and icon colours lightened further (still AA-tested).
- Toolbar and pickers can be screenshotted again (only windows that are on screen during recording stay hidden from capture).
- New Record menu (Open Recorder ⇧⌘R, Stop Recording ⇧⌘.) works from anywhere.

## Accessibility (WCAG 2.1 AA)
- App and site colour tokens re-tuned and measured: all text pairs >= 4.5:1 on every surface, control borders >= 3:1, white-on-fill text >= 4.5:1. The app enforces this with `AccessibilityTests` (contrast of every token pair), so a colour change that breaks AA fails the build.
- Text raised to >= 12 pt; overlay text sits on solid cards instead of the desktop; skip link and visible 3 px focus ring on the site.
- Not yet audited: full VoiceOver pass, keyboard-only operation of the timeline and overlay pickers, Increase Contrast / Reduce Motion settings in the app.

## Known gaps
- Landing page not yet reviewed against reference photos at matching viewport sizes (PRD requirement); first pass only.
- No favicon file or social preview image, only an inline SVG icon.
- Landing page has no GitHub link yet (no repo).

## Next smallest tasks
1. You: `gh auth login`, approve repo creation, then enable Pages and verify the URL.
2. You: choose stack (a) or (b) above.
3. You: grant permissions and run the Phase 0 manual QA, including the clap sync check.
