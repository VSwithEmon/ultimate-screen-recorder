# Phase 0 status

## Commands
```bash
swift build                  # compile app + core
swift test                   # 16 unit/smoke tests (no permissions needed)
./scripts/build_app.sh       # -> "build/Ultimate Screen Recording.app"
open "build/Ultimate Screen Recording.app"
```

## Automated coverage (passing)
- Geometry: AppKit→top-left flip, negative-origin displays, clamp, Retina outward pixel rounding, 1293×691 area, even dimensions, normalised cursor on a negative-origin display.
- Project persistence: round trip, in-progress marker lifecycle, newer-schema rejection, missing manifest/sources, cursor JSONL round trip.
- Export: 1080p30 H.264 + AAC from synthetic media, audio offset 0.5 s ⇒ 2.5 s output (alignment), video-only, odd-size rejection, cancellation leaves no output or partial file.

## Manual QA (requires permissions)
1. `./scripts/build_app.sh && open "build/Ultimate Screen Recording.app"`. Click **Request** for Screen Recording; enable Ultimate Screen Recording in System Settings → Privacy & Security → Screen & System Audio Recording; **quit and reopen** the app. Request Microphone.
2. Play a YouTube/audio clip, talk, and click a few times. Record ~60 s, press **Stop**.
3. Verify the player shows the video; open the package (`~/Movies/ScreenRec/*.screenrecproj`, right-click → Show Package Contents): `Media/screen.mov`, `system.m4a`, `mic.m4a`, `Metadata/cursor.jsonl`, `project.json`; no `recording.inprogress` file.
4. **Sync check:** clap once while a visible flash/click happens; **Export MP4…**, play the result in QuickTime, confirm the clap lines up within ~1 frame. Record the observed offset here.
5. Export, then check: `ffprobe`/QuickTime reports 1920×1080, 30 fps, H.264 + AAC, no watermark.
6. Failure paths: revoke the permission mid-record (expect an error and kept media), force-quit during recording (package keeps `recording.inprogress`).

## Known gaps → next smallest task
Phase 1 start: window/area selection (`sourceRect` using `Geometry`), pause/resume, camera track, and a recovery screen that lists packages still holding `recording.inprogress`.
