# Validation scope

The v0.6.21 release targets arm64 macOS 15+. The packaged executable reports version 0.6.21 / build 40 and passes code-signature verification.

Self-tests cover image export, dimensions, opaque redaction, OCR, undo/redo, annotation movement/resizing/style/deletion, left/right capture selection, window hit order, coordinate conversion, nonzero selection alpha and isolated PNG/TIFF clipboard import. The generated JSON report lists the checks actually executed.

Prior manual verification covered actual screenshot generation, right-click cancellation, language switching and clipboard-dependent disabled controls. A user confirmed a physical left click successfully captured the selected window after the click-through fix. Later UI changes, including v0.6.21 toolbar spacing, were inspected in the running app.

Publication does not claim a new complete recording/audio acceptance run. Intel Macs, multiple physical displays and other machines have not been verified. Permissions depend on the machine and ad-hoc build identity; a settings toggle alone does not prove working capture access.

No personal screenshots, recordings, local logs or user-specific permission records are included in this repository or release package.

## v0.6.22 local validation

Version 0.6.22 / build 41 compiles and passes code-signature verification. The full self-test passes, including saved-position restoration, offscreen correction, negative-coordinate display placement and invalid-data fallback. A separate launch of the installed app restored seeded coordinates (240, 1100) exactly; the original position was restored after testing. CUA title-bar drags did not produce an observable position change, so manual mouse drag acceptance remains unverified. Multiple physical displays were not tested. This local build has not been published to GitHub Releases.
