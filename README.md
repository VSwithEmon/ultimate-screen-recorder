# Ultimate Screen Recorder

Record beautifully. Edit effortlessly. Share anywhere. A free, local-first screen recorder and editor for macOS and Windows, **in development**. No installers exist yet.

- `site/`: landing page (static HTML, no build step). Preview: `python3 -m http.server 4173 --directory site`
- **Download and test:** https://vswithemon.github.io/ultimate-screen-recorder/#install (Mac, Apple Silicon and Intel)
- `apps/macos-native/`: Swift Phase 0 recorder prototype (capture, project package, MP4 export; 16 tests)
- `docs/PRD_v2.md`: product requirements. `docs/DESIGN_REFERENCE.md`: reference-photo matrix. `docs/PROGRESS.md`: current status
- `.github/workflows/pages.yml`: deploys `site/` to GitHub Pages once a GitHub repo exists

No claim of release availability until builds are tested.
