# Validation scope

The v0.6.21 release targets arm64 macOS 15+. The packaged executable reports version 0.6.21 / build 40 and passes code-signature verification.

Self-tests cover image export, dimensions, opaque redaction, OCR, undo/redo, annotation movement/resizing/style/deletion, left/right capture selection, window hit order, coordinate conversion, nonzero selection alpha and isolated PNG/TIFF clipboard import. The generated JSON report lists the checks actually executed.

Prior manual verification covered actual screenshot generation, right-click cancellation, language switching and clipboard-dependent disabled controls. A user confirmed a physical left click successfully captured the selected window after the click-through fix. Later UI changes, including v0.6.21 toolbar spacing, were inspected in the running app.

Publication does not claim a new complete recording/audio acceptance run. Intel Macs, multiple physical displays and other machines have not been verified. Permissions depend on the machine and ad-hoc build identity; a settings toggle alone does not prove working capture access.

No personal screenshots, recordings, local logs or user-specific permission records are included in this repository or release package.

## v0.6.22 local validation

Version 0.6.22 / build 41 compiles and passes code-signature verification. The full self-test passes, including saved-position restoration, offscreen correction, negative-coordinate display placement and invalid-data fallback. A separate launch of the installed app restored seeded coordinates (240, 1100) exactly; the original position was restored after testing. CUA title-bar drags did not produce an observable position change, so manual mouse drag acceptance remains unverified. Multiple physical displays were not tested. This local build has not been published to GitHub Releases.

## v0.6.23 local validation

Version 0.6.23 / build 42 adds scrolling capture. Generated-image tests passed exact overlap alignment at a viewport height of 880 pixels (317, 317 and 73 pixel advances), pixel-identical stitching, unchanged frame detection, incompatible/unrelated frame rejection and one-shot cancellation completion. Existing full self-tests passed. The installed quick-bar entry, introductory dialog and cancellation were checked in the UI. Real automatic scrolling, Accessibility authorization, end-of-page detection and Finish/Cancel during a live capture still require desktop acceptance; these are not claimed as verified. No new GitHub release has been published.

### Desktop acceptance progress

Screen Recording and Accessibility entries were re-registered for the installed local build. Actual screen pixels were captured after registration. A multi-window Chrome test exposed window activation/occlusion problems; capture now preserves window ordering, validates the selected window by ID, and checks occlusion before capturing or scrolling. Regression tests cover target lookup when it is not first in the window list, occlusion, removal and movement. A standalone local WebKit fixture was started for the 24-section acceptance run. That run was interrupted and the editor later contained a user-edited clipboard image; the image was preserved and complete-page/Finish/Cancel desktop acceptance remains pending. No complete 24-section result has been verified.

### User-provided physical-mouse result (2026-10-24)

The user supplied a 1890 × 4925 PNG after the requested manual selection test. Visual inspection shows START and SECTION 01 through SECTION 24 once each, in order, with no obvious duplicate section seams. The bottom green footer is only partially visible and its END text is absent. This verifies a real multi-section stitched result, but not complete-page coverage, automatic-bottom completion, or live Finish/Cancel acceptance. A selection ending above the actual scrolling viewport bottom can omit the final tail once the page cannot scroll further; keep the whole desired viewport inside the selection.

### Complete user-provided result (2026-10-24)

A second user-supplied image (1898 × 5028) shows START, SECTION 01–24 once each in order, and the complete green END / ALL SECTIONS COMPLETE footer. Visual inspection confirms complete coverage and no obvious duplicate or missing section in this local WebKit fixture. This supersedes the earlier incomplete-footer result for this sample. It does not establish live early-Finish/Cancel behavior, automatic versus manual completion, or compatibility with every third-party application.

## v0.6.24 speed validation

Build 43 compiles with optimization and explicit Debug assertion configuration. Full self-test PASS includes 62%-height synthetic overlap and a shorter final step, pixel-identical composition, pacing below the 75% registration limit, and existing edit/export/selection tests. The synthetic 1200×900 matching benchmark decreased from a median 236.75 ms to 2.34 ms per alignment over three repetitions. See scroll-performance-v0.6.24.json. Normal fixed settling delay changed from 750 ms to 220 ms, with uncertainty backoff starting at 600 ms. The user subsequently confirmed acceptance of the installed v0.6.24 speed update. No timed end-to-end measurement was recorded; behavior on animation-heavy or slow-loading pages remains unverified.

## v0.6.24 publication

The release packages the same arm64 executable installed and accepted by the user (version 0.6.24 / build 43), with verified ad-hoc code signature. Screen Recording and Accessibility entries were refreshed before user acceptance. No additional recording/audio, Intel, or multiple-physical-display acceptance is implied. The public release includes scrolling capture and toolbar-position persistence developed since v0.6.21.

## v0.6.25 pointer zoom

Build 44 passes 38 self-test checks with Debug assertions enabled. Pointer-anchor tests cover two off-centre image points, zooming from fit to scrollable layout and back, repeated scaling, and 1%/400% limits with under-one-point anchor error. PNG data, annotation count and undo history remain unchanged. The app builds and its ad-hoc signature verifies. Real Control-wheel input is pending manual acceptance because desktop UI control returned SCStreamErrorDomain -3811; the running user editor was not closed. The release packages the same version 0.6.25 / build 44 executable installed locally.

## v0.6.27 canvas handles (local)

Build 46 passes 42 self-test checks. Resize tests exercise all eight handles inward/outward at 25%, 100% and 200%, compare every output pixel against the correctly translated/cropped source (including a redaction), and verify opaque white extension, no-op, Escape/right-click cancellation, dimension limits, single-step undo and redo restoring annotations. Handles remain outside exported pixels. In an isolated test app, CUA mouse drags changed a generated image from 800×500 to 840×500 and then 810×470; undo restored 840×500. Eight handles were visually inspected. The user subsequently confirmed acceptance of the installed v0.6.27 canvas-handle functionality on 2026-10-30. No new screenshot/recording permission regression is claimed. The installed user application was updated without closing its existing process. This version is committed to the repository; no v0.6.27 release package has been published.

## v0.6.29 publication

Version 0.6.29 / build 48 passes the full 42-check self-test with assertions enabled and verifies its ad-hoc signature. The release packages the same executable installed locally. It includes the user-accepted v0.6.27 canvas handles and the screenshot filename change, plus the v0.6.28 reminder window-level change and bilingual v0.6.29 settings-path correction. The user confirmed that enabling Device Control & Data Access resolved the permission reminder on this Mac; this is not a new cross-app or full-screen always-on-top acceptance test. No new recording/audio, Intel or multiple-physical-display acceptance run is implied.

## v0.6.30 rotation (local)

Build 49 passes the full 45-check self-test. Rotation checks cover every integer angle 1–359, exact 90/180/270 pixel mappings in both directions, opaque white corners, undo/redo including annotation restoration, 360° no-op, invalid-angle rejection and output-size limits. An isolated CUA UI check rotated a generated 800×500 image clockwise 45° to 920×920, visually confirmed whole-image coverage and white fill, restored 800×500 with Undo, and verified that 0° remains in the dialog with a validation message. The added toolbar entry and dialog were inspected in Chinese; English strings are present but a new English desktop layout acceptance run has not been performed. This version is not pushed or released.

## v0.6.31 rotation adjustment (local)

Build 50 passes 47 self-test checks, including signed/fractional angle validation, custom background output, automatic-crop containment over sampled angles and crop-corner pixel comparison within the same colour-managed bitmap. Tests retain all prior cardinal rotation, undo/redo and image editing checks. CUA inspected the before/after window and grid, typed 17.3° and observed slider/stepper synchronisation, toggled automatic crop to 747×290 for an 800×500 fixture, entered/exited full-screen preview, confirmed the same output dimensions and restored 800×500 with Undo. Cancel was checked to retain the original dimensions. Source preview is cached at a maximum 1400-pixel longest edge; final rendering uses full resolution. User physical-mouse acceptance and the English desktop layout remain pending. This build is committed to the repository; no v0.6.31 release package has been published.

## v0.6.33 clipboard capture default (local)

Build 52 passes 48 self-test checks. A named pasteboard test exercises the shared screenshot completion path: PNG is available for paste; no editor, quick bar or success dialog opens; existing editor image and name are retained; cancellation and invalid image data leave the prior clipboard value intact. The test does not write to the system clipboard. Region, window and full-screen capture route the native PNG through this path, as does the stitched scrolling result after PNG encoding. Live screen capture and cross-app paste were not exercised for this build.

## v0.6.34 quick bar after capture (local)

Build 53 passes 48 self-test checks. The shared screenshot completion check verifies that copying valid PNG data to an isolated pasteboard shows only the quick capture bar, leaves the editor image intact, and opens no success dialog. Live capture and cross-app focus were not retested.

## v0.6.35 region overlay recovery (local)

Inspected the reported stuck v0.6.34 state: a region-selection window was present and Escape restored the quick capture bar. Display diagnostics initially showed a 1470×956 primary and 1920×1080 secondary, then only the primary during isolated UI verification. Region capture now creates one non-hiding modal-capable overlay per display, maintains global drag coordinates, and cancels on display reconfiguration. An isolated UI check observed the primary-display prompt and successful Escape recovery; two simultaneously connected displays and physical-mouse capture have not been revalidated. Build 54 passes 49 checks, including cross-display overlay intersections, negative-origin Quartz mapping, cancellation and isolated clipboard completion. The running user application was preserved during installation.

## v0.6.36 single instance (local)

Build 55 passes 50 self-test checks. An independent child process verifies that a held instance lock rejects a second owner and a subsequent process can acquire it after release. Ordinary launches use a per-user, per-bundle file lock before constructing the application UI and registering shortcuts; later launches notify/reopen the existing instance. Self-tests bypass the ordinary instance gate and use isolated test locks. Live duplicate-launch foreground handoff has not been manually accepted. Older already-running binaries do not gain the lock until fully quit and restarted; installation preserves the existing user process.

## v0.6.37 focused editor shortcuts (local)

Build 56 passes 53 self-test checks. Synthetic Command-V/A/C key equivalents exercise an isolated named pasteboard through the key editor window, verify whole-image selection and identical PNG export without selection borders, and retain the canvas on non-image paste. Separate text-view and other-window focus tests verify that image actions do not run. Prior edit/capture/rotation/single-instance tests remain passing. System clipboard contents are not changed by the tests. Physical keyboard acceptance in the installed application remains pending.

## v0.6.38 direct copy (local)

Build 57 passes 54 self-test checks. Command-C copies the full annotated PNG in a focused editor even with whole-image selection cleared; empty-canvas copy remains unavailable. Existing text-input and inactive-editor guards remain tested. The focus-dependent test waits for AppKit activation before assertions. All clipboard tests use a named pasteboard rather than the system clipboard. Physical keyboard acceptance remains pending.

## v0.6.39 focused window capture (local)

Build 58 passes 55 assertion-enabled self-test checks and verifies its ad-hoc signature. Target-selection tests cover foreground application ownership, ignoring the capture bar, editor self-capture, transparent/tiny windows, focused bounds matching behind another window, and focused floating windows. Window capture now uses the selected window ID with screencapture rather than opening a picker. Existing Accessibility permission is used when available to match focused-window bounds; otherwise the frontmost normal window belonging to the foreground application is used. No new Accessibility prompt is requested. The tests use synthetic window metadata and isolated pasteboards; live focused-window capture remains pending user acceptance. Installation preserves the existing user process, so fully quitting and reopening is required to use the new build.
