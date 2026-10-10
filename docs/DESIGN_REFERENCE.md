# Design reference matrix

Source: 19 phone photos of a reference editor (not 26 as the PRD says), taken 2026-10-11 09:22–09:25, stored by the user in `~/Downloads/IMG_2655.JPG … IMG_2673.JPG`. **The photos are not committed to this repo** (they show a third-party app, a person's face and room). Identifiers below are the file numbers. Statuses: `todo` = not built yet, `landing` = represented in the landing-page concept mockup only (not a working app).

## Global chrome (visible in every photo)
| Element | Observed | Our component | Status |
|---|---|---|---|
| Header, left | Window controls; folder icon (tooltip "Show previous projects", 2667); trash icon | `Toolbar` | landing |
| Header, centre | Project name `Google Chrome 2026-10-1…` + extension; ⌘ shortcuts-sheet icon; undo / redo (redo disabled) | `Toolbar` | landing |
| Header, right | **Presets ▾** (sparkle icon); eye icon; gauge icon; **Export** (filled accent button, upload icon) | `Toolbar`, `ExportDialog` trigger | landing |
| Preview tools | Above preview: aspect dropdown (`Auto ▾`), `Crop`, `Mask` | `PreviewCanvas` toolbar | landing |
| Preview | Large 16:10 canvas: wallpaper bg, padded rounded screen, rounded camera bubble bottom-right (2655) / top-right (2666, 2673) | `PreviewCanvas` | landing |
| Right icon rail | 7 icons: canvas/background, cursor, camera, captions/transcript, audio, shortcuts ⌘, smoothing/path. Active icon tinted with a dot | `InspectorRail` | landing (cursor shown) |
| Inspector | Slim dark panel, scrolls, 12–13 px labels, grey helper text, toggles right-aligned, `Reset` greyed text buttons | `InspectorPanel`, `InspectorRow` | landing |
| Floating **+** | Round accent button left of preview (insert event) | `InsertEventButton` | landing |
| Transport | Left: `1 visible timeline ▾`. Centre: prev, play, next. Right: scissors (split/trim), audio-scrubber toggle, zoom-magnifier, `1×` speed + slider | `Transport` | landing |
| Timeline | Ruler `0:05`, `0:10`; orange clip with waveform, label `Clip · 15s · 1×`; blue rounded zoom blocks labelled `Zoom · 🔍1× · Auto`; playhead with round handle | `Timeline`, `TimelineEvent` | landing |

## Per-photo matrix
| ID | Panel / state | Visible controls and exact behaviour | Component | Status | Intentional differences |
|---|---|---|---|---|---|
| 2655 | Canvas ▸ Background ▸ **Image** | Segmented tabs Wallpaper / Gradient / Color / **Image**; "Background Image" drop zone ("Click to select, drop image, or press ⌘V while hovering"); Background blur slider; Padding slider + Reset; Rounded corners slider. Preview bg is an indigo gradient | `SegmentedControl`, `SliderWithValue`, drop zone | todo | Blue accent; no proprietary wallpapers |
| 2656 | Canvas ▸ Background ▸ **Wallpaper** | Category chips (★ favourites, macOS, Spring, Sunset, Radial… scrolls horizontally); "Pick random wallpaper" button; 7-per-row thumbnail grid with selected ring; Background blur; Padding | `SegmentedControl`, thumbnail grid | todo | Original/licensed wallpapers only; no "macOS" named set |
| 2657 | Audio | Microphone: Mute microphone toggle; "Improve microphone audio — reduce noise and normalize volume" toggle; Background audio chips (Lo-Fi, Commercial, Electronic, Instrumental, Sunny Lo-Fi, Lean Groove, Bright Lounge); "Add background audio" button | `InspectorPanel` | todo | Our own royalty-free/user-imported tracks and category names |
| 2658 | Captions ▸ Generate transcript | Transcript method: Apple Speech Recognition / Whisper; copy "No data will be sent to the server"; Language `Auto ▾`; AI model Base / Small / Medium with size text ("Will download 466MB on first use…"); Prompt textarea | `SegmentedControl`, `DropdownMenu` | todo | Real sizes come from the whisper.cpp models we ship |
| 2659 | Same + toolbar tooltip | Tooltip "Disable audio scrubber" over the active scrubber toggle (toggle highlighted) | `Tooltip` | todo | — |
| 2660 | Cursor (top) | Cursor size slider + Reset; Cursor style: 5 swatches (arrow outline, arrow selected, dot, filled arrow, outline arrow; scrolls); Always use pointer cursor (toggle + helper); Hide cursor if not moving; Loop cursor position (helper: moves back to initial position near end); Hide cursor (eye-off icon) | `InspectorRow` | landing | Original cursor art |
| 2661 | **Crop modal** | Full-editor modal: header `Size 1920 × 958`, ratio dropdown `Any ▾`, `Position 0 0`, `Reset`, keyboard-shortcut icon; image with 8 handles and rule-of-thirds guides; **Confirm changes ↵** (accent) and Discard changes | `Modal`, `CropEditor` | todo | — |
| 2662 | **Mask** menu | Popover under Mask: "Add sensitive data mask", "Add highlight mask" | `DropdownMenu` | landing | — |
| 2663 | **Aspect** menu | List with ✓ on Auto; Wide 16:9, Square 1:1, Classic 4:3, Vertical 9:16, Tall 3:4, Portrait 4:5; shape glyph per row | `DropdownMenu` | todo | — |
| 2664 | `1 visible timeline ▾` menu | Checklist of track categories with numeric shortcuts: Zooms ✓ 1, Camera Layouts 2, Masks 4, Shortcuts 3 | `DropdownMenu` | todo | Keys remappable |
| 2665 | Camera (top) | Header "Dynamic camera layout ▾"; Camera position 3×3 dot grid (selected = filled accent dot, bottom-right); Camera size slider + Reset; Roundness slider + Reset; Shape (cut off) | `InspectorPanel`, `PositionGrid` | todo | — |
| 2666 | Camera (scrolled) | Shape: Square / Horizontal / Vertical / **Original**; Mirror horizontally; Hide camera (eye-off icon); "Camera size during zoom ▾" collapsible. Camera shown top-right in preview | `SegmentedControl` | todo | — |
| 2667 | Header tooltip | Folder icon tooltip "Show previous projects" | `Tooltip` | landing | — |
| 2668 | **Zoom editor** (block selected) | "← Close Zoom editor"; Zoom level slider with helper "How close to zoom on the cursor during this zoom phase" + Reset; "Apply zoom level to all other zooms" button; Zoom mode **Auto** / Manual (helper: "automatically try to keep the mouse cursor visible"); Instant animation toggle. Selected block has white outline and edge handles | `InspectorPanel`, `TimelineEvent` | todo | — |
| 2669 | Cursor (scrolled) | Collapsible rows (chevrons): Click effect, Click sound, Rotation, Advanced | `Collapsible` | todo | — |
| 2670 | Cursor ▸ Click effect/sound/Rotation open | Click effect: None / Circle / Ripple. Click sound: None plus two sets named after mouse brands. Rotation: Rotate cursor slider + Reset; "Rotate cursor while moving" toggle (helper: tilts when moving horizontally) | `SegmentedControl` | todo | **Do not ship brand-named sounds**; use generic "Soft click / Crisp click" |
| 2671 | Cursor ▸ Advanced | "Stop cursor movement at the end of the video" slider; "Remove cursor shakes" toggle (on) + threshold slider; "Optimize cursor changes" toggle (on) | `InspectorRow` | todo | — |
| 2672 | **+ insert menu** | Sections: Zoom (Automatic zoom, Manual zoom); Dynamic camera layout (Fullscreen camera layout, Hide webcam, Show both camera and screen); Mask (Sensitive data mask, Highlight mask) | `DropdownMenu` | todo | — |
| 2673 | Split tool active | Scissors toggle highlighted; cursor over clip shows scissors glyph at playhead; camera top-right | `Timeline` tool state | todo | — |

## 13 feature groups vs photos
| # | Group (PRD §B) | Photo evidence | Gap |
|---|---|---|---|
| 1 | Floating recording toolbar | **none** | not observed; built from PRD text only |
| 2 | Area picker | none | not observed |
| 3 | Camera preview window | none (camera bubble inside editor only: 2655…) | not observed |
| 4 | Editor frame | all | — |
| 5 | Preview tools (Auto/Crop/Mask) | 2661–2663 | — |
| 6 | Timeline | all, 2664, 2673 | — |
| 7 | Zoom inspector | 2668, 2672 | — |
| 8 | Cursor inspector | 2660, 2669–2671 | — |
| 9 | Camera inspector | 2665, 2666 | fullscreen/both-layout only as menu items (2672) |
| 10 | Canvas/background | 2655, 2656, 2661 | Gradient and Color tab bodies not photographed |
| 11 | Masks | 2662, 2672 | mask editing UI not photographed |
| 12 | Audio / transcription | 2657–2659 | — |
| 13 | Export dialog | **none** (Export button only) | proposed by PRD, not observed |

## Not photographed — must be designed from PRD text only
Recording toolbar and its menus, area picker, floating camera preview, export dialog, Presets menu, Gradient/Color tabs, mask editing, empty/error/loading states.

## Design observations to calibrate tokens
Reference uses near-black panels, ~12 px radii on controls, indigo-to-violet accent (`≈#3B2FF0` filled buttons and zoom blocks, lavender slider thumbs). We keep the PRD's blue tokens (`#2563EB` primary) and keep the orange source clip.
