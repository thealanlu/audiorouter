# Changelog

## Unreleased

- Rebuilt the menu-bar widget with Apps, Outputs, Setups, and EQ views, persistent system volume, live meters, profile switching, and direct access to shortcuts, settings, diagnostics, and updates.
- Added named setup saving, speaker volume and mute, Group Play controls, input selection, and the full 10-band equalizer to quick controls.
- Kept the selected app or speaker connected to the existing one-percent volume shortcuts and removed repeated audio-service startup when opening the widget.
- Fixed cached input/output selections so applying a setup restores both devices and their volume levels.

- Restore the main SwiftUI scene when reopening AudioRouter from the Dock after closing its window, including after an extended time in the background.
- Use the same window restoration path for Dock, Finder, menu-bar controls, and `Show AudioRouter`, without restarting audio routing.

## 1.1.5 - 2026-09-01

### Settings

- Added a dedicated Settings page to the main sidebar for appearance, launch behavior, Dock visibility, Demo Mode, playback protection, and automatic release updates.
- Made the menu-bar gear open Settings instead of Advanced and rebuilt the native `Command-,` window as a focused preferences view.
- Kept virtual input publishing, backend status, reliability, permissions, diagnostics, and reset tools grouped under Advanced.
- Added a Launch Services retry when the local build script needs to register a freshly rebuilt app bundle before opening it.

### Routed Audio Reliability

- Increased real-time route buffering and output queue headroom to keep routed playback stable while the Mac is under heavy media or CPU load.
- Reduced allocation and copying pressure in the live process-tap path while preserving 32-bit floating-point audio and source-rate-first rendering.
- Fixed a Swift exclusivity crash in the real-time PCM ring buffer when audio blocks wrapped or overflowed its storage.
- Added regression checks for wrapped and overflowing buffer copies and validated routed playback under sustained CPU load.

### Interface Performance

- Moved high-frequency audio meters into a dedicated lightweight observable snapshot instead of publishing them through the entire app store.
- Limited 10 Hz meter refreshes to the small meter components, preventing Dashboard, Devices, onboarding, and mixer controls from rebuilding on every audio tick.
- Coalesced source, device, system, and input levels into one update per meter frame and skipped identical snapshots.
- Changed public release packaging to use the compiler-optimized Release configuration instead of shipping a Debug binary.

### Window Lifecycle

- Changed the main scene to a single retained AudioRouter window so closing it does not stop routing or create duplicate windows.
- Made Dock, Finder, and normal app reopen events restore the Dashboard after the window is closed with `Command-W`.
- Added `Window` > `Show AudioRouter` with `Command-0` as an additional way to bring the main window forward.

## 1.1.4 - 2026-08-22

### Interface Refresh

- Unified the title bar and sidebar chrome so the navigation rail stays visually aligned with the window at every tab.
- Rebuilt the sidebar with stable icon, label, selection, and watermark alignment.
- Added a shared modern button system with clear primary, secondary, quiet, destructive, hover, pressed, and disabled states.
- Applied the refreshed controls across the Dashboard, Devices, EQ, Setups, onboarding, updates, and Advanced screens.
- Removed sidebar-row hover tracking, replaced the bordered native sidebar toggle, and aligned profile, AirPlay, and Group Play controls to one compact control grid.
- Removed the shared white outer frame and top highlight from every main app page.

### Interaction Accuracy

- Replaced the scroll-backed sidebar navigation with a stable top-aligned stack so pointer targets match the visible rows.
- Fixed Dashboard and Devices click alignment and preserved full-row navigation targets.
- Kept the native macOS sidebar control in the title bar while removing its extra bordered treatment.
- Aligned the Dashboard row with the main header and the profile control with the dashboard card edge.

## 1.1.3 - 2026-07-26

### AirPlay Backend Discovery

- Added a backend-level AirPlay/RAOP Bonjour discovery service so AudioRouter can see AirPlay route candidates such as TV and HomePod even when macOS does not expose them as Core Audio output devices.
- Added discovered AirPlay candidates to the Dashboard route builder, source-row output menus, and menu-bar Quick Router.
- Added local-network and Bonjour usage descriptions to the app bundle so macOS can ask for discovery permission cleanly.
- Added an `AudioRouterChecks --dump-airplay` diagnostic that verifies the AirPlay discovery layer separately from the Core Audio output list.
- AirPlay candidates are labeled as AirPlay handoff routes instead of fake live Core Audio devices; live routing still requires macOS to expose a real output UID or a future dedicated AirPlay sender backend.
- Unified duplicate AirPlay and RAOP discovery records and preserved compatibility with routes saved by earlier releases.
- Saved AirPlay routes now bind automatically when macOS exposes the matching destination as a real Core Audio output.

### Reliability And Interface

- Removed a blocking route-start wait that could freeze the interface for up to 750 milliseconds whenever an app route was assigned.
- Reduced source format probing while apps are idle and now show sample-rate badges only when Core Audio returns real data.
- Unified the Dashboard with the same studio-console header and surface language used throughout the app.
- Replaced ambiguous shortcut modifier checkboxes with clear Command and Option key controls.
- Fixed the updater so an already-downloaded release still presents the install prompt.
- Added a compatible SDK fallback for macOS 27 Command Line Tools installations that omit the matching SwiftUI macro plug-in.
- Removed persistent release staging folders that could make macOS discover a second AudioRouter app.

## 1.1.2 - 2026-07-03

### Website And Download Guide

- Updated the GitHub Pages site with a more interactive route demo, mobile navigation, a Windows compatibility section, and direct links to the user manual.
- Added `USER_MANUAL.md` plus a generated `AudioRouter-User-Manual.pdf` for the website and release ZIP.
- Updated release packaging so future macOS ZIP downloads include the PDF manual alongside the app, quick install guide, driver notes, and driver scripts.
- Added a distinct Platforms section that makes the downloadable macOS app and in-development Windows build track visually separate.
- Removed the extra interactive route-flow demo card from the website Routing section.
- Expanded the website's Windows area into a detailed roadmap with implementation phases, experimental driver path notes, and pre-release gates.
- Converted the GitHub Pages site into a multi-page product site with separate Home, Mac, Windows roadmap, Compatibility, and Download/Manual pages.
- Redesigned the Mac and Windows website pages so Mac feels like a polished available-now app page while Windows feels like a darker engineering roadmap.
- Added a persistent website dark-mode toggle with system-theme fallback, dark surface styling, and balanced hero layouts across every page.
- Refined the Mac page into a more professional product page, reframed the Windows page as a prototype/lab track, and rebuilt the PDF manual with a branded cover, route graphic, status legend, color callouts, and cleaner quick-start guidance.
- Integrated real app appearance preferences so AudioRouter can follow macOS or explicitly use Light or Dark mode, and added browser color-scheme metadata to the website.
- Redesigned the website hero sections with a shared signal-frame treatment, consistent proof chips, richer Compatibility and Download preview cards, and mobile-safe hero layouts.

### Windows Compatibility

- Added a sibling `windows/AudioRouter.Windows` WinUI 3/C++ project scaffold for a future Windows 11 version of AudioRouter.
- Added Windows Core Audio backend seams for MMDevice endpoint discovery, endpoint volume/mute, audio session discovery, per-session volume/mute, and process-loopback routing capability checks.
- Added a Windows backend smoke executable and VM workflow steps that compile and run the Windows Core Audio layer on GitHub Actions.
- Added shared JSON contract documentation so macOS and Windows can preserve compatible routes, profiles, EQ settings, shortcuts, and output groups.
- Added a Windows GitHub Actions build workflow that restores NuGet packages and builds the Windows solution on a Windows runner.

### Routing Workflow

- Added `Advanced` -> `Reliability` with a Route Reliability Center that summarizes route health across every source app, with refresh, permission probe, retry, and route test actions.
- Added route and output test tones so users can preview individual speakers, assigned app routes, and Group Play destinations.
- Changed route output pickers to show every live Core Audio output device, including display/HDMI monitors, virtual devices like VB-Cable, Bluetooth devices, and the system speaker.
- Added a public macOS AirPlay picker to the Dashboard and menu-bar popover for TV, HomePod, and other AirPlay destinations that macOS shows in Control Center before exposing them as Core Audio output devices.
- Added Device Change Guard to `Advanced` -> `Reliability` for Bluetooth/AirPods route protection and keep-playing controls.
- Expanded Group Play controls with group test, retry, and per-speaker volume controls.
- Redesigned the menu bar popover into a faster two-panel Quick Router with source selection, output target chips, selected-route gain/mute/retry/test controls, and a compact route list.

### Device Stability

- Added a playback-protection setting that defaults on and debounces Bluetooth/AirPods device-change notifications before AudioRouter refreshes devices or retries saved routes.
- Added an always-on media keep-alive watchdog that defaults on and repeatedly tells Spotify or Music to keep playing while AudioRouter is running.
- Added an immediate Spotify pause listener that reacts to Spotify playback-state notifications and sends a short resume burst when AirPods ear detection pauses playback.
- Extended the device-disconnect grace period while playback protection is enabled so temporary AirPods wear/remove re-enumeration does not immediately mark routes missing.
- Kept selected output/source state stable while macOS audio topology is settling.

### App Mixer Inputs

- Added experimental behind-the-scenes app input publishing: configured route apps can appear as selectable macOS input devices named like `AudioRouter Spotify Input` when Core Audio exposes a process tap.
- Added an Advanced setting to disable app mixer input publishing if another audio app should not see those temporary input devices.
- Added an experimental `AudioRouterHAL.driver` Core Audio HAL input device named `AudioRouter Virtual Input` for DAWs and mixer software that require real system input devices.
- Added a shared-memory bridge so active live process-tap routes can feed the HAL virtual input instead of leaving the driver silent.
- Added HAL driver build, install, and uninstall scripts plus in-app Advanced status for whether the driver is installed.

## 1.1.1 - 2026-06-03

### Profiles

- Added a top-right user profile menu in the main AudioRouter window with full-name display, profile switching, profile creation, renaming, and deletion.
- Scoped saved setups to the active profile so different users can keep separate preferred presets on the same Mac.
- Added a quit confirmation warning so users do not accidentally stop active routing controls.
- Changed the in-app updater so only published GitHub Releases count as app updates; ordinary commits no longer trigger update prompts.
- Refreshed Devices, EQ, Setups, Shortcuts, and Advanced with the same dark studio-console styling used by the Dashboard.

### EQ

- Added live 10-band EQ processing to AudioRouter process-tap routes, applying band changes to routed 32-bit floating-point PCM before output rendering.
- Made EQ slider changes dynamic for active routes.
- Fixed Custom EQ so Save Custom stores the current curve and selecting Custom recalls the saved bands.

### Audio Quality

- Kept live route AudioQueue client formats at the source tap sample rate, letting Core Audio handle device-side conversion instead of relabeling source frames as a different hardware rate.
- Reworked the live route pipe to buffer Float32 samples directly, reducing CPU churn that could cause routed playback dropouts.
- Added live source-quality refreshes so active route badges update when Core Audio reports a changed process-tap format.
- Snapped tiny persisted gain drift around 100% back to clean unity gain to avoid accidental limiting on normal playback.
- Source-quality badges now fetch the real Core Audio process-tap format through a lightweight unmuted tap probe when a live route is not already running.
- Simplified source-quality badges beside route app names to show only the live process-tap sample rate, such as `48k`, while keeping detailed format info in the tooltip.
- Added Core Audio nominal sample-rate range discovery for output devices.
- Centralized experimental route format selection so live routes keep 32-bit floating-point PCM, prefer the source tap sample rate when every selected output supports it, and otherwise choose the nearest shared hardware-supported rate.
- Added regression checks for route sample-rate, channel-count, and float-PCM quality decisions.
- Increased the route pipe and output queue guard depth to reduce short scheduling dropouts during live per-app and Group Play routes.

## 1.1.0 - 2026-06-02

### Selected Track Control

- Added selected-track gain control: click an app or route row, then press Command-= or Command-- to adjust that source by exactly 1% per press.
- Reworked app, device, and group gain controls into smoother fader-style controls with cleaner percent readouts.
- Removed the extra native slider track artifact under gain controls for a quieter pro-audio layout.
- Snapped saved volume values to clean 1% steps to avoid noisy decimal drift.

### Performance And Device Stability

- Debounced app-route volume saves and throttled Core Audio device-volume writes to reduce UI lag while dragging.
- Stopped bundle/package builds from quitting a running AudioRouter instance unless the script is explicitly launching or verifying the app.
- Prevented AudioRouter from forcing the old system output back when Bluetooth devices such as AirPods connect or disconnect.
- Added a short device-topology settling window so automatic route retries do not interrupt audio during Bluetooth, AirPlay, or USB device changes.

### Download And Onboarding

- Added `DOWNLOAD_AND_USE.md` to the release ZIP with install, first-run, routing, shortcut, and troubleshooting instructions.
- Updated release packaging so ZIP downloads extract into an `AudioRouter-macOS` folder containing both `AudioRouter.app` and the manual.
- Added regression checks for selected-source volume keyboard commands and non-disruptive device-change handling.

## 1.0.3 - 2026-06-01

### Routing And Group Play

- Added proactive System Audio Recording permission probing when a custom output is chosen, so macOS can prompt before the selected app starts playback.
- Added live experimental Group Play routing, allowing one process-tap route to fan out to multiple connected output devices.
- Redesigned the dashboard around a simpler Routes view with a prominent Group Play patch flow and secondary individual output rows.
- Added persistent real app icons, smoother gain controls, compact route rows, and clearer output sections under the main route list.
- Added automatic retry handling for saved routes and group routes when Core Audio exposes the source process.

## 1.0.2 - 2026-05-27

### Usability And Stability

- Reduced UI stalls by stopping passive refreshes from starting saved routes automatically.
- Shortened the process-tap route-start probe so failed route attempts return faster.
- Added a visual Route Builder for smoother source-app to output-device setup.
- Kept the dashboard routing area in a side-by-side input/output layout with clearer input and output labels, using horizontal scrolling instead of stacking when space is tight.
- Added first-run onboarding with visual routing steps, permission probing, and a Privacy Settings shortcut.
- Added source-app customization: hide default apps, restore defaults, add running apps, or browse for installed apps.
- Added persistent source-app ordering controls, drag-and-drop reordering, and clearer dashboard section dividers.
- Kept saved custom routes intact during Bluetooth/AirPods device-change bursts instead of immediately resetting them.
- Preserved the current system output when a newly connected device tries to become default, so adding AirPods does not interrupt existing playback.
- Smoothed meters with faster lightweight updates and refreshed Core Audio device changes less aggressively.
- Switched release packaging and updates from DMG to ZIP, while still refusing unsafe public archives unless Developer ID signing and Apple notarization are configured.

## 1.0.1 - 2026-05-26

### Audio Quality

- Improved the experimental route renderer to keep routed audio in 32-bit floating-point PCM with the source tap sample rate whenever available.
- Preserved the highest practical channel count supported by both the process tap and the selected output device, instead of forcing the route format to stereo.
- Raised Core Audio sub-tap drift compensation to high quality for transient route devices.
- Added soft peak limiting for boosted per-app route volume to reduce hard clipping while keeping normal-volume audio untouched.
- Increased the route pipe buffer slightly to reduce dropouts during short scheduling hiccups.

## 1.0.0 - 2026-05-26

AudioRouter 1.0.0 is the first large public release of the app.

### Highlights

- Native macOS menu-bar audio control app with a visual routing dashboard.
- Real Core Audio device discovery for input and output devices.
- System input/output switching, volume, mute, and balance where supported by the selected device.
- Visual app routing interface for Spotify, Apple Music, Chrome, and user-added apps.
- Experimental public Core Audio process-tap routing and metering path on supported macOS versions.
- Clear route health and backend status badges so users can see what is live, saved, simulated, or backend-required.
- Public release package.
- In-app GitHub updater that auto-fetches newer builds and prompts the user to install.
- Dark, production-console-inspired interface with accessibility labels, hints, values, keyboard commands, and Reduce Motion-aware meters.

### Important Notes

- The current public build is ad-hoc signed and not notarized yet.
- Some protected streams, apps, and device formats may not route through public macOS APIs.
- Production-grade per-app routing across all apps and multiple outputs still requires a dedicated audio backend or virtual audio driver.
