# FancyScroll

A tiny menu-bar app that gives your Force Touch trackpad haptic feedback while you scroll:

- **Scroll steps** — a light click every *N* points of scroll travel (adjustable 10–200 pt), like a ratchet or a scroll wheel with detents.
- **End of page** — a distinctly firmer bump (thud, double or triple) when you push into the top/bottom (or left/right) edge of whatever you're scrolling.
- Works system-wide in any app.

## Build & run

Requires macOS 13+ and the Xcode Command Line Tools (`xcode-select --install`). No Xcode needed.

```sh
./build.sh          # → build/FancyScroll.app
open build/FancyScroll.app
```

Install by copying `build/FancyScroll.app` to `/Applications`. Use **Launch at login** in the popover to keep it running.

## Permissions

| Feature | Permission |
|---|---|
| Scroll-step ticks | none |
| End-of-page bump | **Accessibility** (System Settings → Privacy & Security → Accessibility) |

End-of-page detection reads the scroll position of the view under your cursor through the Accessibility API; without the permission the steps still work and the popover shows a "Grant access…" button.

If you rebuild the app, macOS may treat it as a new binary and you'll need to re-tick it in the Accessibility list (remove and re-add if the toggle appears stuck).

## How it works

- `ScrollMonitor` listens to every scroll-wheel event with `NSEvent.addGlobalMonitorForEvents`, accumulates travel per axis and fires a tick each time it crosses the step size. Momentum (finger lifted) is skipped by default since you can't feel it.
- `ScrollEdgeDetector` resolves the scrollable container under the pointer at the start of each gesture and, while you scroll, checks whether you're pushing into an edge. It uses `AXVerticalScrollBar`/`AXHorizontalScrollBar` values (AppKit, Safari, most native apps) and falls back to comparing the content frame with the viewport frame for apps that don't expose scroll bars.
- `Haptics` drives the trackpad. By default it talks to the actuator directly through the private `MultitouchSupport` framework (stronger, more distinct clicks; works while the finger is lifted) and falls back to the public `NSHapticFeedbackManager` if that fails. Switch to "System haptics only" in the popover if you prefer.

## Debugging

```sh
/usr/bin/log stream --predicate 'subsystem == "com.plexy.fancyscroll"' --level debug
```

## Known limitations

- Chromium-based apps (Chrome, Electron apps) expose very little scroll geometry to Accessibility, so end-of-page bumps there are best-effort. Safari, Finder, Mail, Xcode, Notes, Preview, etc. work through their scroll bars.
- Haptics can only be felt while a finger is on the trackpad; that's physics, not a bug.
- The direct-actuator engine uses a private framework; it's fine for personal use but not App Store material.
# fancyscroll
