# Changelog

## v0.6.34 (local build)

- Show the quick capture bar after a screenshot is copied. Keep the editor closed and omit the success prompt.

## v0.6.33 (local build)

- Copy successful region, window, full-screen and scrolling screenshots directly to the clipboard as PNG, without a success prompt or opening the editor.
- Keep the current editor image intact; use Paste or Clipboard Import to edit a capture.

## v0.6.32 (local build)

- Keep the scrolling-capture introduction above ordinary application windows, including while inactive; share the existing permission-reminder window policy.

## v0.6.31 (local build)

- Replace the basic rotation prompt with a side-by-side adjustment window: before/after preview, alignment grid, continuous angle slider, 0.1° numeric stepping, automatic crop, background colour, and full-screen preview.
- Support signed -360° to 360° angles; positive rotates clockwise. Preview changes apply only on confirmation; Cancel keeps the original.
- Automatically crop to a centred rectangle within the rotated source when enabled.

## v0.6.30 (local build)

- Add an editor Rotate command for integer angles 1–360°, clockwise or counterclockwise.
- Expand output bounds to keep the whole image, fill empty areas white, and support undo/redo. Rotation flattens annotations; undo restores them.
- Validate angles and enforce the 40000-pixel side / 60-megapixel output limits.

## v0.6.29 (2026-11-05)

- Publish canvas resize handles and the screenshot timestamp filename from v0.6.26–v0.6.27, plus the permission reminder improvements.
- Correct the scrolling permission reminder to use Device Control & Data Access, with Accessibility noted as the alternate name on some systems, in Chinese and English.

## v0.6.28 (local build)

- Keep the scrolling-capture Accessibility permission reminder above ordinary application windows, including when LightCapture is inactive, across Spaces and alongside full-screen apps.

## v0.6.27 (user accepted, 2026-10-30)

- Add eight canvas resize handles at image corners and edge midpoints. Drag inward to crop or outward to add opaque white space without scaling source pixels.
- Preview dimensions while dragging; Escape or right click cancels. A completed drag is one undoable edit, with annotations flattened as for cropping.
- Limit dimensions to 1–40000 pixels per side and 60 megapixels total.

## v0.6.26 (local build)

- Use `screenshot-yyyyMMdd-HHmmss.png` as the default image export filename in both languages.

## v0.6.25 (2026-10-25)

- Add Control + mouse-wheel zoom anchored to the pointer in the image editor (1%–400%).
- Preserve ordinary wheel scrolling and keep exported pixels, annotations and undo history unchanged.
- Add viewport margins during pointer zoom so the anchor stays fixed across fit-to-scroll transitions.

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
