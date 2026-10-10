# Native macOS Screen Recorder — Product Requirements Document and Build Prompt

Version: 1.0 | Status: Ready for implementation | Purpose: Personal use, free and offline-first

## 1. Product vision
Build a native macOS screen recording and editing app inspired by Screen Studio's workflow, using original code and original visual assets. The app records displays, windows and selected regions, with optional camera, microphone and system audio; preserves editable cursor and interaction metadata; offers a non-destructive editor with zoom, camera layout, masks, backgrounds, captions and audio; and exports watermark-free videos. No subscriptions, paid APIs, cloud accounts or telemetry.

### Success criteria
- Start a screen recording within three interactions after permission setup.
- Save screen, camera and audio as separate synchronized media streams, with cursor/click event metadata.
- Reopen a project and modify zoom, crop, camera, cursor and background without rerecording.
- Export H.264 MP4 at 1080p/30 fps and optionally 4K/60 fps on supported hardware, with accurate audio synchronization.
- Preview and export share the same rendering logic; changes persist after restart.
- All core functions work without an internet connection after any optional model downloads.

### Boundaries
This is a functional alternative, not a copy of Screen Studio's branding, proprietary assets, project format, sound packs or implementation. Screenshot-observed features are marked **Observed**; proposed extensions are **Proposed**. macOS-specific capture limits must be surfaced honestly.

## 2. User and environment
Single local user on an Apple Silicon or Intel Mac. Target macOS 14+ initially, with feature gates by operating system version. Universal build if practical. Local projects only. Use built-in Apple SDKs and permissively licensed open-source dependencies. No Apple Developer Program membership should be required for local development; signing/notarization for external distribution is out of scope.

## 3. User journey
1. Launch app; explain and request Screen Recording, Microphone, Camera, and optionally Accessibility/Input Monitoring permissions as required. Show precise permission status and recovery steps.
2. Choose Display, Window, Area, or Device (where supported). Choose camera, microphone and system-audio options.
3. Optionally adjust capture region, countdown and private speaker notes. Start recording.
4. Record with visible stop/pause affordance, elapsed time and safe interruption handling. Exclude the app's own overlays when possible; clearly state exceptions.
5. Stop recording; atomically finalize media and create a recoverable project. Open editor.
6. Review, trim, add/edit zooms, adjust camera, cursor, canvas, audio and masks; generate local transcript if desired.
7. Export to a user-selected folder, with resolution, aspect ratio, codec, frame rate, quality and filename options. Report progress and errors.

## 4. Feature inventory and requirements

### R01 Recording toolbar — Observed
Floating rounded dark toolbar with selected mode, camera selector, microphone selector, system-audio selector and settings. Modes: full display, selected window, rectangular area, connected device. Show device names and selected state. Close toolbar without discarding existing projects. Keyboard shortcuts must be configurable.

### R02 Area selection — Observed
Interactive rectangle with eight handles, draggable body, dimmed outside region, pixel width/height and X/Y fields, ratio/preset selector, saved areas, confirm/start button. Correctly convert between points and backing pixels for Retina and multiple displays, including negative-origin monitor arrangements. Clamp selection to available capture bounds.

### R03 Camera — Observed
Choose built-in, USB or Continuity Camera when provided by macOS; choose maximum supported resolution; hide preview independently from recording; disable recording. Keep camera in an independently editable time-aligned track. Provide camera access/error handling and fallback when disconnected.

### R04 Microphone — Observed
List available audio inputs, including virtual and Continuity devices; enable/disable capture; optional noise reduction and normalization; automatic gain control toggle only if supported by device. Record separate microphone stream and show clipping/level meter. Handle hot unplug and input changes.

### R05 System audio — Observed
Options: all-app audio, selected-app audio, none. Implement with ScreenCaptureKit when supported. Validate selected-app isolation per OS version; do not promise perfect per-app audio isolation where APIs cannot deliver it. Keep separate track; handle sample-rate changes and clock drift.

### R06 Recording preferences — Observed
Hide desktop icons in output (if feasible; never silently alter Finder preferences), hide Dock icon while recording, highlight capture area, open quick-share after stop, speaker notes excluded from recording, countdown, advanced settings. Implement safe fallbacks and mark OS-dependent limitations.

### R07 Editor shell and projects — Observed
Native editor with preview, top toolbar (project navigation, delete, undo/redo, presets, export), right contextual inspector, bottom timeline. Project contains original media plus edit metadata. Autosave with crash-safe writes, recoverable incomplete recordings, open recent projects, trash confirmation. Use a custom `.screenrecproj` package rather than Screen Studio's format.

### R08 Timeline — Observed
Main orange clip with waveform and duration/speed; independently selectable purple zoom segments; visible categories Zooms, Camera Layouts, Masks, Shortcuts. Playhead, scrubbing, play/pause, previous/next, trim/split, waveform, speed control, audio scrubbing toggle, zoom timeline horizontally, insert event, drag/move/resize event, undo/redo, snapping. Non-destructive time remapping and stable IDs for events.

### R09 Zoom engine — Observed
Automatic and manual zoom events; adjustable zoom magnitude, focal point, auto cursor tracking, apply magnitude to all events, instant-animation toggle, editable event boundaries. Proposed: ease curves, minimum/maximum zoom and dead-zone tracking. Automatic zoom should use click events and cursor activity to suggest keyframes, while preserving manual overrides. Keep cursor and camera composition consistent under zoom.

### R10 Cursor engine — Observed
Cursor size and style presets, always-pointer option, hide when idle, loop end position, hide cursor, click visual effects None/Circle/Ripple, click sounds None/alternative styles, rotation and rotate while moving, stop movement before recording ends, shake removal with threshold, optimize cursor changes. Implement metadata capture via permitted APIs; render cursor separately when available. Do not capture passwords/keystroke contents. If cursor events are unavailable, fall back to baked cursor and disable unsupported controls.

### R11 Camera editing — Observed
Nine-position anchor grid; dynamic layout events; camera size, roundness, Square/Horizontal/Vertical/Original aspect shapes, mirror horizontally, hide camera, camera size during zoom, fullscreen camera and combined screen/camera. Store camera transformations as timeline keyframes. Proposed: draggable custom position, optional border and shadow.

### R12 Canvas and crop — Observed
Canvas aspect ratios Auto, 16:9, 1:1, 4:3, 9:16, 3:4, 4:5. Crop editor: X/Y, width/height, preset ratio, draggable handles, reset, confirm/discard. Crop is non-destructive and may be applied before zoom calculations. Export canvas and preview must match.

### R13 Masks — Observed
Time-bounded sensitive-data mask and highlight mask; draggable geometry and resize handles. Sensitive masks can use solid opaque covering or pixelation/blur with a security warning: blur alone may not fully conceal sensitive text. Confirm exported frames contain no original unmasked pixels in covered regions. Proposed: ellipse and rectangle shapes, feathering for highlights.

### R14 Background styling — Observed
Wallpaper, Gradient, Color, Image; wallpaper thumbnail collections and random selection; background blur, padding and rounded corners. Bundle only properly licensed or original backgrounds; support imported image files. Proposed: drop shadow and background fit modes.

### R15 Transcription and captions — Partly observed
Observed transcription controls: Apple Speech Recognition, Whisper, auto/manual language, Base/Small/Medium model choices, custom vocabulary/prompt. Use local whisper.cpp or equivalent permissively licensed inference engine; Apple Speech Recognition offline only when available, with explicit disclosure if OS would require network. Download optional models with size, disk and license disclosures. Proposed: editable word-level transcript, caption overlay, subtitle styles, SRT/VTT export, transcript-driven cut editing in a later phase. Do not claim caption styling was screenshot-confirmed.

### R16 Audio editing — Observed
Mute microphone, improve microphone audio (denoise and normalization), background audio category browser, add music. Proposed: import royalty-free/user-owned tracks, separate mixer channels, fades, ducking, meters and per-clip gain. Do not ship proprietary Screen Studio audio tracks or brand-named sound recordings.

### R17 Export — User-described + proposed
User described resolution variants (including 4K), social presets, custom size and folder selection. Proposed detailed options: 720p/1080p/1440p/4K/custom, canvas presets for YouTube 16:9, vertical social 9:16, square 1:1, feed 4:5, classic 4:3; MP4 H.264, MOV HEVC when supported, optional GIF, 24/30/60 fps, quality/bitrate, audio toggle, filename and destination. Show estimated dimensions/file size, render progress, cancellation, completion and failure details. Export is local and watermark-free. 4K60 depends on device, source and codec capabilities.

### R18 Presets — Observed menu; contents proposed
Save/apply/reset named groups of canvas, cursor, zoom, camera, audio and export settings. Allow project-local and global presets; keep original code/assets.

## 5. Detailed technical architecture
- **App/UI**: SwiftUI for inspectors, lists and settings; AppKit for NSPanel, window overlays, selection geometry and precise keyboard/mouse interaction.
- **Capture**: ScreenCaptureKit SCStream for display/window video and eligible system audio; AVFoundation AVCaptureSession for webcam/mic where appropriate; CMSampleBuffer timestamps normalized to a monotonic project clock.
- **Cursor/event capture**: Capture mouse movement, button presses and pointer appearance where allowed using macOS event APIs and ScreenCaptureKit metadata as applicable; permissions and secure input restrictions are explicit. Save timestamps, normalized coordinates, button state and display transform.
- **Media persistence**: Store raw screen, camera and audio separately in a project package with metadata JSON, thumbnails, waveform cache, transcripts, render caches and autosave journal. Use atomic writes and versioned schema migrations.
- **Editor domain model**: Project -> Sources -> Tracks -> Clips/Events -> Keyframes. Events include Zoom, CameraLayout, Mask, Shortcut, Caption, Background and CursorOverride. Each uses stable UUID, start/end, parameters, interpolation and z-order.
- **Composition**: Build a deterministic render graph: source frame -> crop -> screen transform/zoom -> canvas/background -> masks -> cursor/click effects -> camera -> captions -> color conversion -> encode. Sensitive-data masking must be applied in a way that covers every output pixel even during zoom.
- **Preview**: Metal/Core Image composition with frame caching and audio sync. A single parameter evaluation engine must feed both interactive preview and offline export.
- **Export**: AVAssetWriter/VideoToolbox hardware encoders, robust audio mixdown, progress reporting and cancellation. Provide graceful CPU fallback if hardware capabilities differ.
- **Transcription**: optional local whisper.cpp models; transcripts stored in project, with clear language/model choice.
- **Privacy**: No login, no analytics, no cloud calls; no capture of raw typed passwords or key contents; explicit permission scopes; local-only media.

## 6. Example project schema
```json
{
  "schemaVersion": 1,
  "projectId": "UUID",
  "name": "Demo recording",
  "canvas": {"width": 1920, "height": 1080, "fps": 30, "background": {"type": "gradient", "id": "default"}},
  "sources": [{"id": "screen1", "type": "screen", "path": "Media/screen.mov"}, {"id": "camera1", "type": "camera", "path": "Media/camera.mov"}],
  "tracks": [{"id": "video", "kind": "source", "sourceId": "screen1"}, {"id": "zoom", "kind": "event", "events": [{"id": "zoom1", "start": 2.0, "end": 5.0, "type": "zoom", "scale": 1.8, "mode": "auto", "easing": "smooth"}]}],
  "cursorEventsPath": "Metadata/cursor.jsonl",
  "exportSettings": {"format": "mp4", "codec": "h264", "width": 1920, "height": 1080, "fps": 30}
}
```

## 7. Key interaction and error cases
- First launch without permissions; permissions revoked while recording.
- Multiple displays, different scaling factors, display unplugged, space/fullscreen changes, target window closed/minimized, protected/DRM content blacked out.
- Camera or microphone disconnected; muted input; Bluetooth audio latency; system sleep, low storage, overheating, interruption.
- Region partially offscreen; impossible custom export dimensions; source lower resolution than 4K output; high frame-rate unsupported.
- Cursor hidden by secure input; app cannot isolate a selected application's audio; unsupported device recording.
- Autosave crash during capture, partial media recovery, corrupt project version, missing source file.
- Export cancellation, disk full, codec failure, progress accuracy and no output corruption.

## 8. Delivery roadmap
**Phase 0 — Proof of feasibility:** Verify minimum macOS version, screen/window/area capture, microphone and system audio, timestamp synchronization, permission flows, and a local 1080p H.264 export. Prototype cursor event recording and note API limitations.

**Phase 1 — Reliable recorder:** Floating toolbar, display/window/area selection, device pickers, countdown, camera overlay, system audio choices, pause/stop, save and recovery. Automated smoke tests.

**Phase 2 — Non-destructive editor:** Project package, preview, clip timeline, waveform, trimming, scrubbing, undo/redo, canvas presets, backgrounds, crop, camera resizing/positioning, basic export.

**Phase 3 — Signature polish:** Cursor reconstruction, smoothing, click effects, automatic/manual zoom events, animation curves, nine-point camera layouts, timeline event editing, masks.

**Phase 4 — Audio and captions:** Noise reduction, normalization, imported background music, optional local Whisper, editable captions and SRT export.

**Phase 5 — Advanced parity:** Dynamic camera layout, shortcuts, presets, advanced cursor controls, social export presets, 4K60 optimization, accessibility and stability tests.

## 9. Acceptance tests
1. Record a 60-second display session with mic, system audio and camera; reopen and verify tracks are synchronized within a frame or documented tolerance.
2. Record a 1293x691 custom area, move/resize it, and verify exported region matches the selected pixels at native backing scale.
3. Add two zoom events, one automatic and one manual; change zoom level; export and compare representative frames with preview.
4. Apply ripple click effect and hide-idle cursor; verify correct timestamps and no duplicate cursor.
5. Move webcam between top-right and bottom-right mid-recording; verify transition and saved state after restart.
6. Apply a solid sensitive-data mask across a moving/zoomed section; verify every affected output frame is covered.
7. Change background to image, add padding and rounded corners; verify 16:9, 1:1 and 9:16 exports.
8. Generate local transcript from a microphone track with network disabled; edit captions and export SRT.
9. Export 1080p30 H.264 MP4 to chosen folder, confirm audio sync and no watermark; try 4K60 only when supported.
10. Simulate low disk space, revoked permission, camera unplug and forced app exit; confirm useful error messages and recoverable data.

## 10. Implementation prompt for Codex / Claude Code / Cursor

You are a senior macOS engineer and video-rendering specialist. Build an original, free, local-first native macOS screen recorder/editor based on the attached PRD. Work incrementally in a real Xcode/Swift Package project. Do not implement mock features that appear functional but do nothing. Do not copy Screen Studio source code, proprietary assets, sound packs, trademarks or project formats.

Hard constraints:
- Swift, SwiftUI, AppKit, ScreenCaptureKit, AVFoundation, Core Image/Metal, VideoToolbox; add permissively licensed OSS only when justified.
- No paid APIs, subscriptions, analytics, logins, watermark, required backend or cloud rendering.
- Target macOS 14+ initially and feature-gate APIs. Prefer Apple Silicon acceleration but do not assume it exists.
- Every claimed feature must have a working implementation, a test, or an explicit disabled/unsupported state.
- Project must build and launch locally with documented Xcode instructions.
- Separate screen, webcam, mic and system audio media when feasible, with stable timestamps; cursor/click metadata stored separately when capture is permitted.
- Preserve source media; all editing is non-destructive. Use a versioned local project schema and autosave/recovery.
- Render preview and export from the same composition graph.
- Write unit tests for timeline transforms, coordinate conversions, event interpolation and project persistence; write manual end-to-end QA steps for permission-dependent capture.

Execution protocol:
1. Inspect the environment and existing repository. Report macOS version, Xcode version, architecture, available SDKs and hardware limitations. Do not assume permissions or device availability.
2. Write an architecture decision record and a short implementation plan for Phase 0, including precise Apple APIs and fallbacks.
3. Implement and run Phase 0 end-to-end: permission onboarding, full display capture, mic/system audio if supported, save local recording, playback and H.264 MP4 export. Prove the output is playable and audio is in sync.
4. Implement Phase 1 capture UX and robust file finalization. Add window/area recording, camera, device menus and proper error states.
5. Implement Phase 2 project editor with timeline, crop, backgrounds and camera layout; verify preview/export equivalence.
6. Implement Phase 3 zoom/cursor/mask features, starting with manual zoom, then metadata-driven automatic zoom. Make limitations explicit where OS APIs cannot provide data.
7. Implement Phase 4 audio enhancement and optional offline transcription. Avoid shipping copyrighted third-party audio.
8. Implement Phase 5 advanced polish, presets and export presets. Benchmark memory, CPU/GPU, dropped frames and export speed.
9. At each phase: show changed files, exact build/test commands, passing/failing test results, known limitations and the next smallest task. Fix build errors before moving on. Never claim completion without running tests.

First task right now: perform Phase 0 feasibility and scaffold the repository with a compiling macOS app, permission screen, basic recording controller, local project persistence, and an export smoke test. If a required macOS API is unsupported, document it and implement a safe fallback instead of silently omitting it.
