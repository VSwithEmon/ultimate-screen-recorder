# Progress

Last updated: 2026-10-11 (recorder UX milestone, v0.2.0). Truthful status only; "done" means verified.

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

## Known gaps
- Landing page not yet reviewed against reference photos at matching viewport sizes (PRD requirement); first pass only.
- No favicon file or social preview image, only an inline SVG icon.
- Landing page has no GitHub link yet (no repo).

## Next smallest tasks
1. You: `gh auth login`, approve repo creation, then enable Pages and verify the URL.
2. You: choose stack (a) or (b) above.
3. You: grant permissions and run the Phase 0 manual QA, including the clap sync check.
