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
