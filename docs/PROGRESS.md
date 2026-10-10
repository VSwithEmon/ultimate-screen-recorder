# Progress

Last updated: 2026-10-11. Truthful status only; "done" means verified.

## PRD v2 phase status
| # | Phase | Status | Evidence / gap |
|---|---|---|---|
| 1 | Landing page | **Done (needs your visual review)** | `site/index.html`; checked in the in-app browser at 375, 1280, 1440, 1920 px: no horizontal overflow, mobile layout fixed. Download buttons are disabled and say "Coming soon". Not yet compared pixel-by-pixel with the reference photos. |
| 2 | GitHub | **Repo live; Pages deploy being verified** | Public repo `VSwithEmon/ultimate-screen-recorder`, pushed over SSH. Pages source set to GitHub Actions. `gh` CLI login could not be saved because `~/.config` is root-owned; SSH + browser were used instead. |
| 3 | Recorder MVP (macOS) | **Prototype, not verified on real capture** | `apps/macos-native` (Swift). 16 automated tests pass, app builds and launches. Real capture still needs Screen Recording + Microphone permission and the manual QA in `apps/macos-native/docs/PHASE0.md`. |
| 4 | Editor MVP | Not started | |
| 5 | Signature features | Not started | Cursor events are recorded by the prototype; no smoothing/zoom yet. |
| 6 | Windows capture | Not started, untested | No Windows machine available here. |
| 7 | Advanced | Not started | |
| 8 | Distribution | Not started | No installers exist. |

## Decisions and deviations
- **Stack:** PRD recommends Tauri 2 + React/TypeScript. **Rust/cargo is not installed** on this Mac, so Tauri cannot be built yet. The only working capture code is native Swift, which stays as `apps/macos-native` for now. Decision needed from you: (a) install Rust and build the Tauri shell around native capture plugins, or (b) keep native SwiftUI for macOS and do a separate Windows app. Not decided; no code assumes either.
- **Reference photos:** 19 (not 26) found in `~/Downloads/IMG_2655–2673`. Not copied into the repo. See `docs/DESIGN_REFERENCE.md` for what they do and do not cover (recording toolbar, area picker, export dialog were not photographed).
- **Landing mockup:** original HTML/CSS drawing of the editor layout, labelled as a design concept, with original icons and a generic avatar. It is not a working UI.
- **Landing page uses system fonts** (no external requests).

## Known gaps
- Landing page not yet reviewed against reference photos at matching viewport sizes (PRD requirement); first pass only.
- No favicon file or social preview image, only an inline SVG icon.
- Landing page has no GitHub link yet (no repo).

## Next smallest tasks
1. You: `gh auth login`, approve repo creation, then enable Pages and verify the URL.
2. You: choose stack (a) or (b) above.
3. You: grant permissions and run the Phase 0 manual QA, including the clap sync check.
