# LightCapture

A compact screenshot, annotation and recording utility written in Swift / AppKit for Apple Silicon Macs, with Chinese and English interfaces.

[简体中文](README.md) · [Download v0.6.24](https://github.com/ojkwmclm/LightCapture/releases/tag/v0.6.24)

## Features

- Floating capture bar with clipboard import, window/region/primary-display capture, recording and editor controls.
- Left-click a window or left-drag a region to capture; right-click or Escape cancels.
- Editable arrows, rectangles, ellipses, freehand strokes, highlights, text, step markers and opaque redaction. Move, resize, restyle, delete and undo/redo annotations.
- PNG/JPEG/PDF export, image copy, crop, zoom, pinned references, manual vertical image combination and local Chinese/English OCR.
- Region/window/display MP4 recording with system audio, microphone, both or neither. Reopen from the Dock to access Stop.
- Clipboard import and the editor Paste button are enabled only when a readable image is available.

## Requirements and installation

**Apple Silicon (arm64), macOS 15 or later.** Intel builds are not provided or verified.

Download `LightCapture-v0.6.24-macOS-arm64.zip` from [Releases](https://github.com/ojkwmclm/LightCapture/releases), extract it and move the app into Applications.

The app is ad-hoc signed and has not been Developer ID signed or notarized. macOS may warn that the developer cannot be verified. Screen Recording permission is required for capture/recording; microphone recording needs microphone permission. Updating an ad-hoc build may require re-registering its permission entry.

Select the recording target and MP4 destination before starting. The quick bar hides during recording; reopen from the Dock or use the menu bar to stop.

## Scrolling capture

Use the down-arrow button on the quick bar or Capture → Scrolling Capture in the editor. Scroll to the desired starting point and select the scrolling content, excluding fixed headers and scrollbars. The app scrolls down, removes matching overlaps, and opens the result in the editor. Finish early with Escape, Finish, or the menu-bar Scrolling Capture / Finish action. Cancel discards the capture.

Extend the selection to the bottom of the scrolling viewport. If it ends above that edge, content below the selection cannot be included once the page reaches its scroll limit.

Screen Recording and Accessibility access are required. Keep the target window still and visible. It may remain in the background; moving it or covering the scroll point stops capture. Keep the entire region visible: partial occlusions may appear in the screenshot. Uncertain alignment stops with the successfully stitched result preserved. Limits: 80 sections, 40000 pixels high, or 60 megapixels. Select at least 100 × 100 points within one display. Fixed headers, animation and repeated content can prevent alignment.

## Shortcuts

| Action | Shortcut |
| --- | --- |
| Open image | ⌘O |
| Import clipboard image | ⌥⌘V |
| Region screenshot | ⌥⌘2 |
| Primary-display screenshot | ⌥⌘3 |
| Window screenshot | ⌥⌘4 |
| Save image | ⌘S |
| Copy annotated image | ⇧⌘C |
| Undo / redo | ⌘Z / ⇧⌘Z |

Switch languages from the gear or app menu. System-owned dialogs follow macOS language settings.

## Build and self-test

Install Xcode Command Line Tools, then run:

```sh
chmod +x build.sh
./build.sh
```

The script generates the app in the repository directory for `arm64-apple-macos15.0` using AppKit, Vision, ScreenCaptureKit, AVFoundation and Carbon.

In a macOS desktop session:

```sh
LIGHTCAPTURE_TEST_OUTPUT=/tmp/lightcapture-selftest.png "./轻截 LightCapture.app/Contents/MacOS/LightCapture" --self-test --test-exit
```

Clipboard tests use an isolated named pasteboard and do not write to the system clipboard. Physical mouse behavior, permissions and recording audio need separate acceptance tests. See [validation scope](docs/VALIDATION.md).

## Limitations

This is a 0.x release. Editable project files, recording pause, webcam overlays and video editing are not implemented. Image combination retains overlaps. Exports and cropping flatten annotations; crop supports undo. Window screenshots include visible overlaps. Full-screen screenshots currently use the primary display.

LightCapture independently implements a compact workflow inspired by FastStone Capture. It is not affiliated with FastStone and contains no FastStone binaries, resources or decompiled artifacts.
