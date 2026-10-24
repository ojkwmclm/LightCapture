# Changelog

## v0.6.24 (2026-10-24)

- Publish automatic scrolling capture and saved quick-bar position from local v0.6.22–v0.6.23 builds.
- User confirmed acceptance of the installed v0.6.24 scrolling speed update.
- Reduce normal scroll settling delay from 750 ms to 220 ms and increase the scroll step from 45% to 62% of the selection (capped at 760 points).
- Back off to at least 600 ms when alignment is uncertain, then gradually recover normal pacing.
- Enable compiler optimization while retaining Debug assertions for self-test validation.
- Synthetic image matching benchmark: median 236.8 ms → 2.34 ms per alignment; this is not an end-to-end capture speed measurement.


## v0.6.23 (local build)

- Add automatic downward scrolling capture from a selected content region, with overlap registration and duplicate removal.
- Add Finish/Cancel controls, bottom detection, partial-result preservation and image-size limits.
- Add quick-bar, editor capture menu, file menu and status-menu entry points in Chinese and English.
- Keep the visible target in place without activating its app; stop when the target window moves, closes or is covered by another ordinary app window.


## v0.6.22 (local build)

- Save the quick capture toolbar position when moved and restore it on launch.
- Keep the toolbar visible when a display is disconnected or its layout changes.

## v0.6.21

Initial public release of the existing Mac app.

- Compact floating screenshot and recording toolbar.
- Left-button capture confirmation and right-button/Escape cancellation; fixes for real mouse click-through.
- Editable annotations, OCR, image export, pinned references and manual image combination.
- Recording scope, save destination and optional system/microphone audio.
- Chinese/English UI and contextual tooltips.
- Clipboard image import and editor Paste button beside Copy.
- Four-corner full-screen icon and revised quick-bar button order.
- Consistent editor icon layout with top padding and tighter icon-to-label spacing.
