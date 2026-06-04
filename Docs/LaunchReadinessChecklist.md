# Launch Readiness Checklist

## 1) Device Performance Profiling

- List devices: `xcrun xctrace list devices`
- Run profiler script:
  - `cd "AproposMagazinev2"`
  - `./Scripts/profile-device.sh <DEVICE_UDID> 25`
- Record and compare these flows:
  - Cold launch to Home ready
  - Open an article and scroll top -> bottom
  - Start podcast, background app, lock/unlock, return to app
  - Home vertical scroll with mini-player active

## 2) Image Pipeline Quality Gates

- Thumbnails in rails use mobile image first.
- Hero image uses large image first.
- Preload budget kept low (`perf_home_image_preload_limit`).
- No section should trigger large full-width image decodes while scrolling a rail.

## 3) Article Rendering Stability

- `HTMLTextView` reload guard active (same HTML is not reloaded repeatedly).
- Validate long article + embeds do not cause frame drops while podcast is playing.
- Confirm no layout jumping during image load.

## 4) Audio UX Completeness

- Lock screen now playing card visible with title/artist/progress.
- Control Center and headset controls:
  - play/pause
  - seek / skip
- Route changes:
  - unplug headphones pauses playback
- Interruption recovery:
  - call/Siri interruption resumes correctly when system allows resume.

## 5) Release Safety Rails

- Feature flags registered at launch (`FeatureFlags.registerDefaults()`):
  - `perf_home_image_preload_limit`
  - `perf_player_background_publish_threshold`
  - `perf_player_foreground_publish_threshold`
  - `perf_enable_html_diff_guard`
- Validate app behavior with default values before App Store build.

## 6) Pre-Release Smoke Test (Device)

- Open app from terminated state.
- Navigate all tabs.
- Open 3-5 articles rapidly.
- Start podcast, lock phone, unlock phone, continue playback.
- Verify mini-player + full-player + queue.
- Verify no visible stutter in Home vertical scroll.
