# ADR-0001: Capture architecture and project layout (Phase 0)

Status: accepted · Target: macOS 14+ (developed on macOS 26.5, Xcode 26.6, Swift 6.3, arm64)

## Decisions
1. **SwiftPM package, not a hand-made Xcode project.** `ScreenRecCore` (pure logic, unit-tested without permissions) + `ScreenRecApp` (SwiftUI/AppKit). `scripts/build_app.sh` assembles and ad-hoc signs `"build/Ultimate Screen Recording.app"`. `open Package.swift` in Xcode also works.
2. **Screen + system audio: `SCStream`** (`SCContentFilter(display:excludingApplications:)`, own app excluded). Screen frames accepted only when `SCFrameStatus == .complete`.
3. **Microphone: `AVCaptureSession`**, not `SCStream.captureMicrophone` (macOS 15+ only), so macOS 14 works. A feature gate can switch to the SCStream path on 15+ later.
4. **One file per stream** (`screen.mov` H.264, `system.m4a`, `mic.m4a` AAC), each through its own `AVAssetWriter` on its own queue. No stream blocks another.
5. **Shared clock.** All timestamps are host-clock (mach) time. `t0` is read from `CMClockGetHostTimeClock()` at session creation; each source stores `startOffset = firstPTS - t0` in `project.json`. The exporter aligns streams with these offsets. `NSEvent.timestamp` is on the same clock, so cursor events are `t = event.timestamp - t0`.
6. **Cursor metadata:** global `NSEvent` monitor for mouse move/drag/down/up only, stored as JSONL with display-normalised coordinates. No key events are observed. Pointer *appearance* (arrow/I-beam/…) is **not** captured in Phase 0.
7. **Cursor fallback:** the cursor engine is Phase 3, so Phase 0 bakes the OS cursor into the video (`showsCursor = true`, recorded in `CaptureInfo.cursorBakedIntoVideo`). Turning it off leaves a cursor-less video plus metadata.
8. **Crash safety:** the package is created with `Metadata/recording.inprogress`; it is removed only after successful finalize. Manifests are written atomically. Exports go to a hidden `.partial.mp4` and are moved into place on success.
9. **Export:** `AVMutableComposition` (offset alignment) → `AVAssetReaderVideoCompositionOutput` (aspect-fit) + `AVAssetReaderAudioMixOutput` → `AVAssetWriter` H.264 High / AAC 192 kbps MP4. VideoToolbox hardware encoding is used implicitly by AVAssetWriter. The composition graph becomes the shared preview/export graph in Phase 2.

## Feasibility findings / limits (Phase 0)
| Item | Status |
|---|---|
| Display capture, system audio, mic, H.264 export | Implemented; export verified by tests on synthetic media |
| Real capture on this machine | **Needs the user to grant Screen Recording + Microphone** (cannot be automated; modifying privacy settings is the user's call) |
| Mic/screen sync | Designed on the shared host clock; **must be verified manually** (QA steps in PHASE0.md). Bluetooth mics add device latency that timestamps may not reflect |
| Per-app system audio isolation | Not implemented; `SCContentFilter` with a single app/window may isolate audio, to be validated per OS in Phase 1 |
| Hide desktop icons | Not implemented (no silent Finder pref changes) |
| Pointer appearance metadata | Not available from `NSEvent`; needs private/accessibility-adjacent APIs - deferred |
| Camera, window/area capture, pause | Phase 1 |
| Rebuilds reset TCC grants | Ad-hoc signature changes per build; use a stable local signing cert via `SIGN_ID` |
