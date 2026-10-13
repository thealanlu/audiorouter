# AudioRouter

AudioRouter is a native SwiftUI macOS menu-bar app for visual audio control. It manages real Core Audio devices, attempts live app-to-output routing through public process taps on supported macOS versions, and keeps unsupported routing features clearly labeled instead of pretending they are live.

## Website

AudioRouter has a GitHub Pages website at:

[https://alanlu439.github.io/audiorouter/](https://alanlu439.github.io/audiorouter/)

The site source lives in `docs/` and is deployed by `.github/workflows/pages.yml`. If the page is not live yet, open the repository's GitHub `Settings` -> `Pages` screen and set the build and deployment source to `GitHub Actions`.

## Windows Compatibility

AudioRouter now includes the start of a sibling Windows implementation at:

```text
windows/AudioRouter.Windows
```

The Windows app is not a SwiftUI/Core Audio port. It is a native Windows 11 path using WinUI 3, Windows App SDK, and a C++/WinRT backend so it can talk directly to Windows Core Audio APIs.

What the Windows scaffold includes:

- WinUI 3 dashboard shell with tray-icon support.
- MMDevice endpoint discovery for input and output devices.
- Endpoint volume and mute through `IAudioEndpointVolume`.
- Audio session discovery through `IAudioSessionManager2`.
- Per-session volume and mute through `ISimpleAudioVolume`.
- Capability flags for process-loopback capture and driver-required routing.
- Shared JSON contract documentation in `shared/contracts/`.
- Windows GitHub Actions build workflow in `.github/workflows/windows-build.yml`.

What is still future Windows work:

- A finished process-loopback route renderer.
- Production-grade app-to-device routing.
- App-as-input virtual devices.
- Signed Windows driver/service distribution.
- Public Windows release ZIP or MSIX packaging.

Build on Windows:

```powershell
msbuild .\windows\AudioRouter.Windows\AudioRouter.Windows.sln /restore /p:Configuration=Release /p:Platform=x64
```

Windows requirements:

- Windows 11
- Visual Studio 2022 with Desktop development with C++
- Windows App SDK support
- Windows 10/11 SDK

## Download

Download the latest stable build from GitHub Releases:

[Download AudioRouter macOS ZIP](https://github.com/alanlu439/audiorouter/releases/latest/download/AudioRouter-macOS.zip)

After downloading:

1. Open `AudioRouter-macOS.zip`.
2. Open the extracted `AudioRouter-macOS` folder.
3. Read `AudioRouter-User-Manual.pdf` or `DOWNLOAD_AND_USE.md` for install, first-run, routing, and shortcut instructions.
4. Move `AudioRouter.app` to `/Applications`.
5. Control-click or right-click `AudioRouter.app`, choose `Open`, then confirm.

The current public ZIP is not Apple-notarized yet. On first launch, macOS can show a verification warning. Use the Control-click/right-click `Open` flow above, or open `System Settings` -> `Privacy & Security` -> `Open Anyway` if macOS still blocks it. Keep Gatekeeper enabled.

Local development bundles in `dist/AudioRouter.app` are also ad-hoc signed for testing and can trigger the same first-launch warning.

There is no public Windows release download yet. The Windows implementation is now scaffolded for development and CI, and release packaging should be added after the Windows build is validated on a Windows machine.

## How To Run AudioRouter

### Run the GitHub download

1. Download `AudioRouter-macOS.zip` from the latest GitHub Release.
2. Open the ZIP.
3. Open the extracted `AudioRouter-macOS` folder.
4. Read `AudioRouter-User-Manual.pdf` for the guided walkthrough or `DOWNLOAD_AND_USE.md` for quick install notes.
5. Move `AudioRouter.app` to `/Applications`.
6. Control-click or right-click `AudioRouter.app`.
7. Choose `Open`, then confirm.
8. Approve the macOS System Audio Recording prompt when AudioRouter asks for routing or meter access.

If macOS still blocks the app, open `System Settings` -> `Privacy & Security`, click `Open Anyway` beside the AudioRouter warning, then Control-click `AudioRouter.app` and choose `Open` again.

### Run from source

Requirements:

- macOS 14.2 or newer
- Xcode command line tools
- Swift 5.10 or newer

Build and open the app bundle:

```bash
./script/build_and_run.sh
```

Build the app bundle without opening it:

```bash
./script/build_and_run.sh --bundle
```

The local app bundle is created at:

```text
dist/AudioRouter.app
```

Run validation checks:

```bash
./script/build_and_run.sh --bundle
./script/run_checks.sh
./script/run_checks.sh --dump-airplay
plutil -lint dist/AudioRouter.app/Contents/Info.plist
```

## License

AudioRouter source code is available under the custom [AudioRouter Noncommercial License 1.0](LICENSE) with required attribution to Alan Lu.

You may use, copy, modify, publish, and distribute AudioRouter for noncommercial purposes only, provided that the license and required notices are preserved. Commercial use is not permitted without prior written permission from Alan Lu.

Because commercial use is restricted, AudioRouter is source-available rather than OSI open source.

The AudioRouter name, logo, app icon, and branding assets are not licensed for commercial use and may not be used in a way that suggests endorsement without prior written permission.

## What Works Now

- Menu bar popover, main visual dashboard, and AudioRouter Settings window.
- Real input and output device discovery through Core Audio.
- Current default input/output detection.
- Switching the system output device and system input device.
- Output volume, input volume, mute, and balance where a device exposes those controls.
- Core Audio hardware change observation plus a refresh fallback for Bluetooth, USB, HDMI, virtual, aggregate, and built-in device changes.
- A public macOS AirPlay picker in the Dashboard and menu-bar popover for TV, HomePod, and other AirPlay destinations that may not appear as Core Audio outputs until macOS activates them.
- Backend-level AirPlay/RAOP discovery through Bonjour so TV, HomePod, and other AirPlay route candidates can appear in the route UI even before macOS exposes them as Core Audio devices.
- Running audio-capable app discovery through Core Audio process objects, with a running-app fallback.
- Experimental live per-app routes on macOS 14.2+ using public Core Audio process taps, transient aggregate devices, and an IO callback.
- High-quality experimental route rendering using 32-bit floating-point PCM, source-rate-first AudioQueue client formats, Core Audio output conversion, high-quality drift compensation, and clean unity-gain snapping to avoid accidental limiting near 100%.
- Source-quality badges beside route app names, dynamically refreshed from the real Core Audio process-tap format when macOS exposes the source, with `Pending` shown only until a tap probe or live route can read the format.
- Experimental app-as-input publishing: configured route apps can appear in macOS and mixer software as selectable inputs such as `AudioRouter Spotify Input` when Core Audio exposes that app's process tap.
- Experimental HAL driver: `AudioRouterHAL.driver` publishes a real stereo macOS input named `AudioRouter Virtual Input`, and AudioRouter can feed active live process-tap routes into it through a shared-memory bridge.
- Experimental group play: route one app to an output group so the captured source is rendered to multiple connected speakers through separate `AudioQueue` outputs.
- `Advanced` -> `Reliability` with route health, exact failure reasons, permission probe, retry, and route test actions in one place.
- Output and route test tones for previewing individual speakers, app route assignments, and Group Play destinations.
- Device Change Guard in `Advanced` -> `Reliability` for AirPods/Bluetooth protection and keep-playing controls.
- Expanded Group Play controls with source assignment, group test, retry, and per-speaker level controls.
- Per-route volume, mute, and live meters while an experimental process-tap route is active.
- Live 10-band EQ processing for AudioRouter process-tap routes, with dynamic slider updates and a saved Custom preset.
- Smoother fader-style volume controls with clean 1% steps, visible percent readouts, and selected-track keyboard gain control with `Command =` and `Command -`.
- Backend readiness panel in the popover, dashboard, and Advanced settings so the app shows whether routes are ready, live, saved, or waiting for playback.
- Custom route apps: add running apps from the visual picker or browse for an installed `.app`, then assign that app to an output.
- Customizable source-app dashboard: hide default source apps, restore defaults, drag to reorder the app list, or add your own route apps visually.
- Top-right user profiles with full display names, so saved setups can be separated by person.
- First-run visual onboarding with a route setup walkthrough, permission probe, and Privacy Settings shortcut.
- Playback-protected device-change handling that waits through Bluetooth/AirPods re-enumeration bursts before refreshing routes or marking a route missing, without forcing another system-output switch during connect or disconnect events.
- Always-on keep-alive playback for Spotify and Music, using macOS Automation to reassert play while AudioRouter is running, plus an immediate Spotify pause listener for AirPods ear-detection pauses.
- Menu-bar quick controls with Apps, Outputs, Setups, and EQ views, always-visible system volume, selected app/speaker volume shortcuts, AirPlay, Group Play, microphone selection, named setup saving, profile switching, and access to settings, shortcuts, diagnostics, and updates.
- Route health diagnostics showing app detection, playback activity, output availability, backend readiness, and exact failure reasons.
- VoiceOver-friendly labels, values, hints, keyboard commands, and Reduce Motion-aware meters across the main audio controls.
- Built-in GitHub release update checking with a persistent latest-download link.
- Persistent route preferences, EQ settings, shortcuts, setup cards, and visual output groups.
- Live Mode for real device control, and Demo Mode for UI testing with mock apps/devices/meters.

## Profiles And Setups

Use the profile button in the top-right corner of the main window to switch users, add a profile, rename it, or delete the current profile. The control displays the active profile's full name so the current setup owner is always visible.

Saved setups in the Setups tab belong to the active profile. Existing setups from older builds are kept under `Default Profile`, and new profiles start with an empty setup list so each user can keep their own preferred routing, EQ, volume, and mute presets.

## Live Versus Demo

Live Mode uses public macOS APIs for real device state, system controls, and experimental process-tap routes. It does not animate fake meters. If no live process-tap route is active, the UI shows “Meter unavailable.”

Demo Mode is only for previews and visual testing. It uses mock apps, devices, routes, output groups, and animated meters, and it is always labeled as Demo.

## Backend Architecture

AudioRouter is split into layers:

- `AudioDeviceService`: real Core Audio device management.
- `RunningAppService` and `ProcessAudioMonitor`: running app detection and process-tap probing.
- `ProcessTapRoutingEngine`: experimental public-API routing path using `CATapDescription`, a private process tap, a transient aggregate capture device, PCM ring buffers, and one or more `AudioQueue` renderers pinned to selected output devices.
- `AppInputDevicePublisher`: experimental public process-tap aggregate devices that expose configured app audio as selectable macOS input devices for mixer software while AudioRouter is running.
- `AudioRouterHAL.driver`: experimental Core Audio HAL/AudioServerPlugIn virtual input driver for mixer-visible input selection.
- `HALVirtualInputBridge`: shared-memory bridge that writes active live route audio into the HAL driver.
- `AudioRoutingManager`: route preference persistence and status calculation.
- `PublicAPIAudioRoutingBackend`: real public-API support for devices, app discovery, system controls, and experimental process-tap routing.
- `FutureRoutingPluginBackend`: stub architecture for a future audio backend that could own streams and render them to chosen outputs.

## Core Audio APIs Used

- `AudioObjectGetPropertyData`
- `AudioObjectSetPropertyData`
- `AudioObjectAddPropertyListenerBlock`
- `kAudioHardwarePropertyDevices`
- `kAudioHardwarePropertyDefaultOutputDevice`
- `kAudioHardwarePropertyDefaultInputDevice`
- `kAudioHardwarePropertyProcessObjectList`
- `kAudioDevicePropertyVolumeScalar`
- `kAudioDevicePropertyMute`
- `kAudioDevicePropertyStreamConfiguration`
- `kAudioDevicePropertyAvailableNominalSampleRates`
- `kAudioDevicePropertyDeviceNameCFString`
- `kAudioDevicePropertyDeviceUID`
- `AudioHardwareCreateProcessTap` and `AudioHardwareDestroyProcessTap` on macOS 14.2+
- `AudioHardwareCreateAggregateDevice` and `AudioHardwareDestroyAggregateDevice`
- `AudioDeviceCreateIOProcIDWithBlock`, `AudioDeviceStart`, and `AudioDeviceStop`
- `AudioQueueNewOutputWithDispatchQueue`, `kAudioQueueProperty_CurrentDevice`, `AudioQueueStart`, and `AudioQueueStop`

## What Requires A Real Audio Backend

AudioRouter now has an experimental public-API route path. It can attempt a selected app route such as Spotify to a selected Bluetooth speaker when macOS exposes a process object, grants System Audio Recording permission, and the selected device can be used in the transient aggregate device.

A production-grade version still needs a dedicated audio backend for reliability across all apps/devices, lower latency, effects, and sample-locked multi-output groups:

- Audio Server Driver Plug-in or virtual audio device.
- Process audio capture.
- Audio processing graph.
- Per-device render outputs.
- Permission-aware capture helper.
- Low-latency buffer scheduling and cleanup.

When the experimental route starts successfully, the UI marks it “Live.” If macOS denies capture, the app is not producing a tap-able stream, or the aggregate route cannot start, AudioRouter saves the desired route and marks it “Requires Audio Backend.” Output groups can fan out one live route to multiple devices, but independent Bluetooth/AirPlay/USB devices may have latency differences or drift without a production routing backend.

AudioRouter keeps its internal live route path lossless where public APIs allow it: captured audio is rendered as 32-bit floating-point PCM, the source tap sample rate is preserved as the AudioQueue client format, and Core Audio performs any device-side conversion required by the selected output. Bluetooth, AirPlay, and some USB devices can still apply their own codec, firmware, latency, or hardware sample-rate limits outside AudioRouter.

App mixer inputs have two layers. The app-only layer in `Advanced` -> `System` -> `Publish mixer inputs` can still try public aggregate inputs when Core Audio exposes a process tap, but some DAWs do not show those temporary devices. The stronger path is the experimental HAL driver. Install `AudioRouterHAL.driver`, reopen your mixer app, then select `AudioRouter Virtual Input`. AudioRouter feeds that driver from active live process-tap routes through a shared-memory bridge. The current driver exposes one stereo virtual input, not one independent input per app.

The backend readiness panel is the fastest way to see what to do next:

- `Devices`: confirms connected macOS outputs such as speakers, monitors, AirPlay devices, Bluetooth devices, and virtual audio devices are available.
- `Route Apps`: confirms configured route apps have Core Audio process objects while playing audio.
- `Process Taps`: shows whether the public capture path is available on this macOS version.
- `Custom Routes`: shows whether any selected app-to-output route is live or saved for retry.

## EQ And Effects

The 10-band EQ UI, presets, curve preview, and Custom preset are saved settings. When a source is routed through AudioRouter's live process-tap route engine, EQ bands are applied to the captured 32-bit floating-point PCM stream before it is rendered to the selected output device. EQ changes are dynamic, so moving a slider updates active routes without restarting playback.

Public Core Audio device APIs still do not apply arbitrary EQ to system audio that is not routed through AudioRouter. Full system-wide EQ remains future backend work.

## Permissions

The generated app bundle includes `NSAudioCaptureUsageDescription`. AudioRouter does not use private TCC APIs. The Advanced screen has a process-tap probe button, and choosing a custom output now starts a public Core Audio global tap probe immediately so macOS can ask for System Audio Recording permission before the selected app has started playback. If the app process is not visible yet, AudioRouter saves the route and retries automatically when Core Audio exposes the process.

macOS system prompts cannot be auto-approved by AudioRouter or any normal app. AudioRouter instead shows visual instructions, opens Privacy & Security when requested, and keeps routes saved while you approve the prompt yourself.

## Updates And Releases

AudioRouter checks GitHub Releases from the app. Release updates auto-fetch the newest ZIP when a newer version is available and prompt you to install once the download is ready. Ordinary commits are not treated as app updates; users are notified only when a new GitHub Release is published. Automatic checks run at launch and continue about every 15 minutes while AudioRouter is open when enabled, and the last check time is saved across app launches. The Updates card and Advanced settings both include a visual auto-check toggle. The updater uses the latest release API, follows `v`-prefixed semantic version tags, times out quickly on network problems, and shows readable errors if GitHub cannot be reached.

This is a lightweight public-release updater, not a silent in-place installer. The Install button opens the downloaded ZIP so you can move the app to Applications. Future work can replace it with Sparkle once a Developer ID signing and update-feed workflow is ready.

Public release builds produce a ZIP only. The recommended path is Developer ID signing and Apple notarization:

```bash
export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
export NOTARYTOOL_PROFILE="AudioRouterNotary"
export NOTARIZE=1
./script/package_release.sh
```

`NOTARYTOOL_PROFILE` should be created with `xcrun notarytool store-credentials`. The script signs the app with `DEVELOPER_ID_APPLICATION`, submits a ZIP to Apple's notary service, staples the notarization ticket to the app, validates the staple, runs Gatekeeper assessment with `spctl`, then recreates the final ZIP with the stapled app inside.

To intentionally publish the current unnotarized ZIP, use:

```bash
ALLOW_UNNOTARIZED_PUBLIC_ZIP=1 ./script/package_release.sh
```

That creates `dist/AudioRouter-macOS.zip` and includes `AudioRouter-User-Manual.pdf`, `DOWNLOAD_AND_USE.md`, and `DRIVER_INSTALL.md` with the first-launch Control-click/Open instructions. Users can run it, but macOS can show an Apple verification warning because the app is not notarized yet.

For a local-only test image that is expected to be blocked after download, use:

```bash
LOCAL_TEST_ZIP=1 ./script/package_release.sh
```

That creates `dist/AudioRouter-macOS-local-untrusted.zip`. Do not upload that file to GitHub Releases. The updater and README download link use only `AudioRouter-macOS.zip`.

Each release ZIP extracts to an `AudioRouter-macOS` folder containing `AudioRouter.app`, `AudioRouter-User-Manual.pdf`, `DOWNLOAD_AND_USE.md`, `DRIVER_INSTALL.md`, and driver helper scripts so users have install and first-run instructions directly inside the download.

## Build From Source

Use this path if you want to build AudioRouter locally instead of using the release download.

Requirements:

- macOS 14.2 or newer for process-tap capture.
- Xcode Command Line Tools or Xcode with SwiftPM support.
- Bluetooth speakers or headphones already paired and connected in macOS System Settings.

Build and open the app:

```bash
./script/build_and_run.sh
```

The script builds the SwiftPM product, stages `dist/AudioRouter.app`, writes the app bundle `Info.plist`, copies `Resources/AppIcon.icns`, and launches the app bundle.

## How To Use

1. Connect your Bluetooth speaker, AirPods, or other output device in macOS first.
2. Open AudioRouter from the menu bar.
3. Keep the app in Live Mode.
4. Start playback in Spotify, Apple Music, Chrome, or another app you added.
5. To customize sources, open the Routing Dashboard, click `Add App`, pick a running app, browse for an installed `.app`, drag input rows to reorder them, or hide apps you do not want from the source row menu.
6. Use the Route Builder, pick an output from an app row, or drag the app card onto an output device card.
7. If a TV, HomePod, or AirPlay speaker appears as an `AirPlay` candidate, select it to save the route preference, press the `AirPlay` button, choose that route in macOS, then refresh AudioRouter.
8. When macOS asks for System Audio Recording permission, allow AudioRouter.
9. If a route starts successfully, the route badge changes to `Live` and the meter begins moving.
10. Select a route/app row, then press `Command =` or `Command -` to adjust that track's gain by exactly 1% per press. The source card fader and mute button also work when the route backend supports per-app control.
11. Use `Follow System Output` to remove a custom route and send the app back to the normal system output.

To use an app as an input in mixer software:

1. Install the HAL driver with `./script/install_hal_driver.sh`.
2. Reopen AudioRouter and your mixer software.
3. Start playback in the source app, such as Spotify.
4. Create a live route for that app in AudioRouter.
5. In your mixer software, choose `AudioRouter Virtual Input`.

If the input is not listed yet, confirm `Advanced` -> `System` says the HAL driver is installed, then reopen the mixer app. If the input is listed but silent, make sure the app route is `Live`; the driver outputs silence when no live AudioRouter route is feeding it.

If the backend panel says `Saved Only`, leave the source app playing and click `Retry Route`. If it says `Requires Backend`, the chosen app/device pair could not be made live through public Core Audio process taps, but the route preference is saved for a future routing backend.

AudioRouter starts with Spotify, Apple Music, and Chrome as source apps. You can add more apps from the Routing Dashboard. Output choices include every live macOS output device, including built-in speakers, monitors, HDMI/DisplayPort outputs, AirPlay/TV/HomePod devices, Bluetooth devices, and virtual devices such as VB-Cable.

HomePod and TV outputs appear after macOS exposes them as audio devices, usually after selecting the device once from Control Center, the macOS Sound output menu, or System Settings.

AudioRouter also includes `Advanced` -> `System` -> `Protect playback`, which is on by default. It debounces Bluetooth and AirPods device-change notifications before refreshing devices or retrying routes, so temporary wear/remove re-enumeration is less likely to disturb active playback. `Always keep media playing` is also on by default. While AudioRouter is running, it periodically tells Spotify and Music to keep playing, and it listens for Spotify playback-state pause notifications so Spotify can resume faster when macOS sends an AirPods ear-detection pause event. macOS may ask for Automation permission the first time this runs.

## Status Badges

- `Live`: AudioRouter started a process-tap route and is rendering it to the selected output.
- `Working`: The source is following the normal macOS system output.
- `Saved Only`: AudioRouter saved the route and will try to restore it when the app/device is available.
- `Requires Audio Backend`: macOS public APIs could not start that route. The route choice is saved, but a production audio backend is needed for reliable routing.
- `Device Missing`: The selected output is disconnected.

## Troubleshooting

- If the route does not start, make sure the source app is actively playing audio, then click `Retry Route`.
- If permission was denied, open System Settings, grant AudioRouter System Audio Recording permission, then quit and reopen AudioRouter.
- If `AudioRouter Virtual Input` does not appear in mixer software, install the HAL driver with `./script/install_hal_driver.sh`, approve the administrator prompt, then reopen the mixer app.
- If `AudioRouter Virtual Input` appears but is silent, start playback in the source app and make the route live in AudioRouter. The virtual input is fed by active live process-tap routes.
- If the selected Bluetooth speaker is missing, connect it in macOS System Settings first.
- If Spotify or Music pauses when you take AirPods out of your ears, keep `Advanced` -> `System` -> `Protect playback` and `Always keep media playing` enabled, then approve the macOS Automation prompt. AudioRouter cannot block the AirPods pause command itself; it resumes supported media apps after the pause. For zero pause from AirPods sensors, turn off Automatic Ear Detection in macOS Bluetooth settings for your AirPods.
- If the app still plays through the original output, remove the route with `Follow System Output`, start playback again, and reassign the output.
- Some protected streams and device formats may not be routable through public macOS APIs.

## Verify

```bash
./script/build_and_run.sh --bundle
./script/run_checks.sh
./script/build_and_run.sh --verify
LOCAL_TEST_ZIP=1 ./script/package_release.sh
plutil -lint dist/AudioRouter.app/Contents/Info.plist
codesign --verify --deep --strict dist/AudioRouter.app
```

This Command Line Tools install does not include `XCTest` or Swift's `Testing` module, so the package includes `AudioRouterChecks` as a small executable check suite for persistence, routing status, shortcuts, and model behavior.

In a logged-in macOS graphical session, run `./script/run_window_checks.sh` to check closed-window release, repeated reopening, delayed scene creation, and activation recovery. These checks create temporary test windows without starting the audio engine. Also verify the packaged app by closing it with `Command-W`, waiting several minutes, then clicking its Dock icon; the main window should return without restarting the app or creating duplicate windows.

## Future Work

- Harden the experimental process-tap aggregate-device IO pipeline across more devices and formats.
- Sparkle-based automatic in-place updates after the notarized Developer ID release workflow is in place.
- Routing plugin or virtual audio device for production-grade per-app output routing.
- Broader EQ processing through a future backend for audio that is not routed through AudioRouter.
- Sample-locked output group sync across independent devices.
- Production launch-at-login behavior.
