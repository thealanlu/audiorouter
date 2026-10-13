import AudioRouterCore
import Combine
import CoreAudio
import Foundation
import SwiftUI

func dumpRealOutputDevices() throws {
    let devices = try AudioDeviceManager().refreshDevices()
    let rawOutputs = devices.filter { $0.kind == .output }
    let menuOutputs = AudioRouterStore.routeOutputDevices(from: devices)

    print("Raw Core Audio outputs (\(rawOutputs.count)):")
    for device in rawOutputs {
        print("- \(device.name) | uid=\(device.uid) | transport=\(device.transport.rawValue) | alive=\(device.isAlive) | default=\(device.isDefault) | channels=\(device.channelCount)")
    }

    print("")
    print("AudioRouter output menu options (\(menuOutputs.count)):")
    for device in menuOutputs {
        print("- \(device.name) | uid=\(device.uid) | transport=\(device.transport.rawValue) | default=\(device.isDefault) | channels=\(device.channelCount)")
    }
}

func dumpAirPlayRouteCandidates(seconds: TimeInterval = 6) {
    let discoveryService = AirPlayRouteDiscoveryService()
    var latestCandidates: [AirPlayRouteCandidate] = []
    let cancellable = discoveryService.$candidates.sink { candidates in
        latestCandidates = candidates
    }

    discoveryService.start()
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    let discoveredCandidates = latestCandidates
    discoveryService.stop()
    _ = cancellable

    print("Discovered AirPlay route candidates (\(discoveredCandidates.count)):")
    for candidate in discoveredCandidates {
        let endpoint = [candidate.hostName, candidate.port.map(String.init)].compactMap { $0 }.joined(separator: ":")
        print("- \(candidate.name) | type=\(candidate.serviceType) | target=\(candidate.routeTargetID) | endpoint=\(endpoint.isEmpty ? "unresolved" : endpoint)")
    }
}

@MainActor
func runChecks() throws {
    checkEQPresets()
    checkThemePreferenceMapping()
    checkSettingsNavigation()
    try checkMeterStateIsolation()
    try checkPresetPersistence()
    try checkUserProfilePresetScoping()
    checkShortcutPersistence()
    try checkSelectedSourceVolumeCommandStep()
    try checkSelectedOutputVolumeCommandStep()
    try checkNamedSetupRestoresDevicesAndVolume()
    checkDeviceModelIDs()
    checkAirPlayRouteCandidateModel()
    checkAirPlayRouteDeviceMatching()
    checkAllAliveOutputFiltering()
    checkRouteBackwardCompatibility()
    try checkRoutingManagerRoutesAndFallback()
    try checkSupportedBackendFailuresStaySaved()
    try checkOutputGroupRoutesFanOut()
    checkRouteAudioQualityPolicy()
    try checkSourceAudioQualityDisplay()
    try checkDeviceChangesDoNotSwitchSystemOutput()
    try checkCustomRouteAppPersistence()
    try checkFocusedSourceIconsStayWithConfiguredApps()
    checkUpdateVersionComparison()
    checkAutomaticUpdateCheckPersistence()
    checkPlaybackProtectionPersistence()
    checkPlaybackKeepAliveCandidates()
    checkAppInputPublishingMetadata()
    try checkRouteHealthDiagnostics()
}

@MainActor
func checkMeterStateIsolation() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = AudioRouterStore(
        deviceManager: FakeDeviceManager(devices: []),
        settings: AppSettingsStore(defaults: UserDefaults(suiteName: "AudioRouterChecks-\(UUID().uuidString)")!),
        audioRoutingManager: AudioRoutingManager(
            backend: FakeRoutingBackend(),
            fileURL: directory.appendingPathComponent("routes.json")
        ),
        outputGroupsURL: directory.appendingPathComponent("groups.json"),
        appSourcesURL: directory.appendingPathComponent("sources.json"),
        hiddenDefaultSourcesURL: directory.appendingPathComponent("hidden-defaults.json"),
        sourceOrderURL: directory.appendingPathComponent("source-order.json")
    )

    var storeChangeCount = 0
    var meterChangeCount = 0
    let storeCancellable = store.objectWillChange.sink { storeChangeCount += 1 }
    let meterCancellable = store.meterState.objectWillChange.sink { meterChangeCount += 1 }

    store.meterState.update(
        systemOutput: 0.6,
        input: 0.2,
        sources: ["spotify": 0.75],
        devices: ["speakers": 0.6]
    )
    precondition(meterChangeCount == 1, "A meter snapshot should publish one lightweight view update")
    precondition(storeChangeCount == 0, "Meter ticks must not invalidate the entire AudioRouter interface")
    precondition(store.meterState.snapshot.sourceMeters["spotify"] == 0.75, "Meter snapshot should retain source levels")

    store.meterState.update(
        systemOutput: 0.6,
        input: 0.2,
        sources: ["spotify": 0.75],
        devices: ["speakers": 0.6]
    )
    precondition(meterChangeCount == 1, "Identical meter snapshots should not publish duplicate updates")
    _ = storeCancellable
    _ = meterCancellable
}

func checkSettingsNavigation() {
    let sections = SettingsSection.allCases
    precondition(sections.contains(.settings), "The main sidebar should include a dedicated Settings page")
    precondition(
        sections.firstIndex(of: .settings)! < sections.firstIndex(of: .advanced)!,
        "Everyday Settings should appear before Advanced tools"
    )
    precondition(SettingsSection.settings.systemImage == "gearshape", "Settings should use the standard gear icon")
}

func checkThemePreferenceMapping() {
    let suiteName = "AudioRouterChecks-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = AppSettingsStore(defaults: defaults)
    settings.theme = .system
    precondition(settings.effectiveColorScheme == nil, "System theme should follow macOS color scheme")
    precondition(settings.theme.appKitAppearanceName == nil, "System theme should not force an AppKit appearance")

    settings.theme = .light
    precondition(settings.effectiveColorScheme == .light, "Light theme should request SwiftUI light mode")
    precondition(settings.theme.appKitAppearanceName == .aqua, "Light theme should request Aqua appearance")

    settings.theme = .dark
    precondition(settings.effectiveColorScheme == .dark, "Dark theme should request SwiftUI dark mode")
    precondition(settings.theme.appKitAppearanceName == .darkAqua, "Dark theme should request Dark Aqua appearance")

    let reloaded = AppSettingsStore(defaults: defaults)
    precondition(reloaded.theme == .dark, "Theme preference should persist")

    settings.reset()
    precondition(settings.theme == .system, "Reset should return appearance to System")
}

func checkEQPresets() {
    precondition(EQPreset.allCases.count == 7, "Expected seven EQ presets")
    precondition(EQPreset.music.bands.count == 10, "Music preset should expose ten bands")
    precondition(EQPreset.custom.bands.count == 10, "Custom preset should expose ten bands")

    let suiteName = "AudioRouterChecks-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let manager = EQManager(defaults: defaults)
    manager.applyPreset(.music)
    manager.setBand(index: 0, gain: 7)
    manager.saveCustomPreset()
    manager.applyPreset(.flat)
    precondition(manager.state.bands == EQPreset.flat.bands, "Flat EQ should load flat bands")
    manager.applyPreset(.custom)
    precondition(manager.state.bands.first == 7, "Custom EQ should recall saved custom bands")

    let reloaded = EQManager(defaults: defaults)
    precondition(reloaded.state.customBands.first == 7, "Saved custom EQ should persist")
}

func checkAirPlayRouteCandidateModel() {
    let displayName = AirPlayRouteCandidate.displayName(from: "70-35-60-AA-BB-CC@Living Room HomePod")
    precondition(displayName == "Living Room HomePod", "RAOP service names should show the human device name")

    let candidate = AirPlayRouteCandidate(
        id: AirPlayRouteCandidate.stableID(name: displayName, serviceType: "_raop._tcp.", domain: "local."),
        name: displayName,
        serviceType: "_raop._tcp.",
        domain: "local."
    )
    precondition(candidate.routeTargetID.hasPrefix(AirPlayRouteCandidate.routeTargetPrefix), "AirPlay candidates should produce route target ids")
    precondition(AirPlayRouteCandidate.isRouteTargetID(candidate.routeTargetID), "AirPlay route target ids should be recognizable")
    precondition(candidate.kindDescription == "AirPlay audio", "RAOP candidates should be labeled as AirPlay audio")

    let airPlayID = AirPlayRouteCandidate.stableID(
        name: displayName,
        serviceType: "_airplay._tcp.",
        domain: "local."
    )
    precondition(candidate.id == airPlayID, "AirPlay and RAOP discovery should keep one stable route target")

    let legacyTarget = "\(AirPlayRouteCandidate.routeTargetPrefix)\(candidate.id)|_raop._tcp.|local."
    precondition(
        AirPlayRouteCandidate.normalizedTargetKey(forRouteTargetID: legacyTarget) == candidate.id,
        "Saved AirPlay targets from older releases should remain matchable"
    )
}

func checkAirPlayRouteDeviceMatching() {
    let candidateID = "\(AirPlayRouteCandidate.routeTargetPrefix)living room"
    let output = AudioDevice(
        audioObjectID: 55,
        uid: "airplay-output",
        name: "Living Room",
        kind: .output,
        channelCount: 2,
        transport: .airPlay,
        isDefault: false,
        isAlive: true
    )
    let matched = AudioRouterStore.airPlayOutputDevice(
        forRouteTargetID: candidateID,
        outputs: [output]
    )
    precondition(matched?.uid == output.uid, "AirPlay route candidates should bind to matching Core Audio outputs")

    let legacyID = "\(AirPlayRouteCandidate.routeTargetPrefix)living room|_airplay._tcp.|local."
    let legacyMatch = AudioRouterStore.airPlayOutputDevice(
        forRouteTargetID: legacyID,
        outputs: [output]
    )
    precondition(legacyMatch?.uid == output.uid, "Legacy AirPlay route ids should bind to matching Core Audio outputs")
}

func checkPresetPersistence() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let manager = PresetManager(fileURL: directory.appendingPathComponent("presets.json"))
    let preset = AudioPreset(
        name: "Desk",
        outputDeviceUID: "output-1",
        inputDeviceUID: "input-1",
        systemVolume: 0.7,
        inputVolume: 0.4,
        systemMuted: false,
        appVolumes: ["music": 0.8],
        mutedApps: ["music": false],
        appOutputAssignments: ["music": "output-1"],
        eqPreset: .music
    )
    manager.savePreset(preset)

    let reloaded = PresetManager(fileURL: directory.appendingPathComponent("presets.json"))
    precondition(reloaded.presets.first?.name == "Desk", "Preset name did not persist")
    precondition(reloaded.presets.first?.eqPreset == .music, "Preset EQ did not persist")

    let exported = reloaded.exportJSON()
    let imported = PresetManager(fileURL: directory.appendingPathComponent("imported.json"))
    imported.importJSON(exported)
    precondition(imported.presets.first?.name == "Desk", "Preset JSON import did not restore setup")
}

func checkUserProfilePresetScoping() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let profileManager = UserProfileManager(fileURL: directory.appendingPathComponent("profiles.json"))
    let presetManager = PresetManager(fileURL: directory.appendingPathComponent("presets.json"))
    presetManager.setActiveProfileID(profileManager.activeProfileID)

    presetManager.savePreset(AudioPreset(
        name: "Default Desk",
        outputDeviceUID: nil,
        inputDeviceUID: nil,
        systemVolume: nil,
        inputVolume: nil,
        systemMuted: false,
        appVolumes: [:],
        mutedApps: [:],
        appOutputAssignments: [:],
        eqPreset: .flat
    ))

    let secondProfile = profileManager.addProfile(named: "Alan")
    presetManager.setActiveProfileID(secondProfile.id)
    precondition(presetManager.presets.isEmpty, "New profiles should not see another user's setup presets")

    presetManager.savePreset(AudioPreset(
        name: "Alan Music",
        outputDeviceUID: nil,
        inputDeviceUID: nil,
        systemVolume: nil,
        inputVolume: nil,
        systemMuted: false,
        appVolumes: [:],
        mutedApps: [:],
        appOutputAssignments: [:],
        eqPreset: .music
    ))
    precondition(presetManager.presets.map(\.name) == ["Alan Music"], "Active profile should see its own presets")

    presetManager.setActiveProfileID(UserProfile.defaultProfileID)
    precondition(presetManager.presets.map(\.name) == ["Default Desk"], "Switching profiles should restore that user's presets")
}

func checkShortcutPersistence() {
    let suite = UserDefaults(suiteName: "AudioRouterChecks-\(UUID().uuidString)")!
    let manager = ShortcutManager(defaults: suite)
    precondition(manager.shortcut(for: .increaseVolume).displayValue == "⌘=", "Selected track volume up should default to Command =")
    precondition(manager.shortcut(for: .decreaseVolume).displayValue == "⌘-", "Selected track volume down should default to Command -")
    manager.update(action: .muteSystem, key: "x", modifiers: [.command])
    let reloaded = ShortcutManager(defaults: suite)
    precondition(reloaded.shortcut(for: .muteSystem).key == "x", "Shortcut key did not persist")

    let oldDefaults = UserDefaults(suiteName: "AudioRouterChecks-\(UUID().uuidString)")!
    let oldVolumeDefaults = [
        ShortcutBinding(action: .increaseVolume, key: "=", modifiers: [.command, .option]),
        ShortcutBinding(action: .decreaseVolume, key: "-", modifiers: [.command, .option])
    ]
    oldDefaults.set(try! JSONEncoder().encode(oldVolumeDefaults), forKey: "AudioRouter.Shortcuts")
    let migrated = ShortcutManager(defaults: oldDefaults)
    precondition(migrated.shortcut(for: .increaseVolume).displayValue == "⌘=", "Old volume up shortcut should migrate to Command =")
    precondition(migrated.shortcut(for: .decreaseVolume).displayValue == "⌘-", "Old volume down shortcut should migrate to Command -")
}

@MainActor
func checkSelectedSourceVolumeCommandStep() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let settings = AppSettingsStore(defaults: UserDefaults(suiteName: "AudioRouterChecks-\(UUID().uuidString)")!)
    settings.demoMode = true
    let store = AudioRouterStore(
        settings: settings,
        audioRoutingManager: AudioRoutingManager(
            backend: FakeRoutingBackend(),
            fileURL: directory.appendingPathComponent("routes.json")
        ),
        outputGroupsURL: directory.appendingPathComponent("groups.json"),
        appSourcesURL: directory.appendingPathComponent("sources.json"),
        hiddenDefaultSourcesURL: directory.appendingPathComponent("hidden-defaults.json"),
        sourceOrderURL: directory.appendingPathComponent("source-order.json")
    )

    store.refresh(silent: true)
    guard let source = store.audioSources.first else {
        preconditionFailure("Expected a demo source for selected volume command")
    }
    store.selectedSourceID = source.id
    store.setSourceVolume(source: source, volume: 0.50)
    store.changeSelectedSourceVolume(by: 0.01)
    precondition(abs((store.audioSources.first { $0.id == source.id }?.volume ?? 0) - 0.51) < 0.0001, "Command = should increase selected track volume by one percent")
    store.changeSelectedSourceVolume(by: -0.01)
    precondition(abs((store.audioSources.first { $0.id == source.id }?.volume ?? 0) - 0.50) < 0.0001, "Command - should decrease selected track volume by one percent")
}

@MainActor
func checkSelectedOutputVolumeCommandStep() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let settings = AppSettingsStore(defaults: UserDefaults(suiteName: "AudioRouterChecks-\(UUID().uuidString)")!)
    settings.demoMode = true
    let store = AudioRouterStore(
        settings: settings,
        audioRoutingManager: AudioRoutingManager(
            backend: FakeRoutingBackend(),
            fileURL: directory.appendingPathComponent("routes.json")
        ),
        outputGroupsURL: directory.appendingPathComponent("groups.json"),
        appSourcesURL: directory.appendingPathComponent("sources.json"),
        hiddenDefaultSourcesURL: directory.appendingPathComponent("hidden-defaults.json"),
        sourceOrderURL: directory.appendingPathComponent("source-order.json")
    )

    store.refresh(silent: true)
    guard let output = store.outputDevices.first(where: { $0.canSetVolume }) else {
        preconditionFailure("Expected a demo output for selected output volume command")
    }
    store.selectOutputDevice(output)
    precondition(store.selectedOutputDeviceID == output.uid, "Selecting an output should make it the shared volume shortcut target")
    precondition(store.selectedSourceID == nil, "Selecting an output should clear the selected app target")
    store.setDeviceVolume(output, volume: 0.25)
    store.changeSelectedVolume(by: 0.01)
    precondition(abs((store.outputDevices.first { $0.uid == output.uid }?.volume ?? 0) - 0.26) < 0.0001, "Command = should increase selected output volume by one percent")
    store.changeSelectedVolume(by: -0.01)
    precondition(abs((store.outputDevices.first { $0.uid == output.uid }?.volume ?? 0) - 0.25) < 0.0001, "Command - should decrease selected output volume by one percent")
}

@MainActor
func checkNamedSetupRestoresDevicesAndVolume() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let suite = "AudioRouterChecks-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettingsStore(defaults: defaults)
    settings.demoMode = true
    let presetURL = directory.appendingPathComponent("presets.json")
    let store = AudioRouterStore(
        settings: settings,
        eqManager: EQManager(defaults: defaults),
        presetManager: PresetManager(fileURL: presetURL),
        userProfileManager: UserProfileManager(fileURL: directory.appendingPathComponent("profiles.json")),
        audioRoutingManager: AudioRoutingManager(backend: FakeRoutingBackend(), fileURL: directory.appendingPathComponent("routes.json")),
        outputGroupsURL: directory.appendingPathComponent("groups.json"),
        appSourcesURL: directory.appendingPathComponent("sources.json"),
        hiddenDefaultSourcesURL: directory.appendingPathComponent("hidden.json"),
        sourceOrderURL: directory.appendingPathComponent("order.json")
    )
    store.refresh(silent: true)
    let input = store.currentInput!
    let originalOutput = store.currentOutput!
    let speaker = store.outputDevices.first { !$0.isDefault }!
    store.setDefaultDevice(speaker)
    precondition(store.currentInput?.uid == input.uid, "Changing output must preserve the input selection")
    store.setDefaultDevice(input)
    precondition(store.currentOutput?.uid == speaker.uid, "Changing input must preserve the output selection")
    store.setSystemOutputVolume(0.37)
    store.setInputVolume(0.46)
    store.saveCurrentSetup(named: "  Studio Mix  ")
    let reloaded = PresetManager(fileURL: presetURL)
    let preset = reloaded.presets.first!
    precondition(preset.name == "Studio Mix", "Named setups must persist a trimmed name")
    precondition(preset.outputDeviceUID == speaker.uid && preset.inputDeviceUID == input.uid, "Setups must retain both device selections")
    store.setDefaultDevice(originalOutput)
    store.setSystemOutputVolume(0.20)
    store.setInputVolume(0.10)
    store.applyPreset(preset)
    precondition(store.currentOutput?.uid == speaker.uid && store.currentInput?.uid == input.uid, "Applying a setup must restore both device selections")
    precondition(abs((store.currentOutput?.volume ?? 0) - 0.37) < 0.0001, "Applying a setup must restore its output volume after selecting input")
    precondition(abs((store.currentInput?.volume ?? 0) - 0.46) < 0.0001, "Applying a setup must restore input volume")
    store.saveCurrentSetup()
    precondition(store.presetManager.presets.first?.name == "Setup 2", "Existing unnamed setup saving must remain compatible")
}

func checkDeviceModelIDs() {
    let output = AudioDevice(
        audioObjectID: 1,
        uid: "abc",
        name: "Speaker",
        kind: .output,
        channelCount: 2,
        transport: .builtIn,
        isDefault: true,
        isAlive: true
    )
    let input = AudioDevice(
        audioObjectID: 1,
        uid: "abc",
        name: "Mic",
        kind: .input,
        channelCount: 1,
        transport: .builtIn,
        isDefault: true,
        isAlive: true
    )
    precondition(output.id != input.id, "Input and output identities must not collide")
}

func checkAllAliveOutputFiltering() {
    let devices = [
        AudioDevice(audioObjectID: 1, uid: "built-in", name: "MacBook Speakers", kind: .output, channelCount: 2, transport: .builtIn, isDefault: true, isAlive: true),
        AudioDevice(audioObjectID: 2, uid: "airpods", name: "AirPods", kind: .output, channelCount: 2, transport: .bluetoothLE, isDefault: false, isAlive: true),
        AudioDevice(audioObjectID: 3, uid: "living-room", name: "Living Room AirPlay", kind: .output, channelCount: 2, transport: .airPlay, isDefault: false, isAlive: true),
        AudioDevice(audioObjectID: 4, uid: "homepod", name: "Kitchen HomePod", kind: .output, channelCount: 2, transport: .unknown, isDefault: false, isAlive: true),
        AudioDevice(audioObjectID: 5, uid: "benq", name: "BenQ MA270U", kind: .output, channelCount: 2, transport: .displayPort, isDefault: false, isAlive: true),
        AudioDevice(audioObjectID: 6, uid: "vb-cable", name: "VB-Cable", kind: .output, channelCount: 2, transport: .virtual, isDefault: false, isAlive: true),
        AudioDevice(audioObjectID: 7, uid: "hdmi", name: "HDMI", kind: .output, channelCount: 2, transport: .hdmi, isDefault: false, isAlive: true),
        AudioDevice(audioObjectID: 8, uid: "old-speaker", name: "Old Speaker", kind: .output, channelCount: 2, transport: .bluetooth, isDefault: false, isAlive: false),
        AudioDevice(audioObjectID: 9, uid: "mic", name: "Mic", kind: .input, channelCount: 1, transport: .builtIn, isDefault: true, isAlive: true)
    ]
    let routedOutputs = AudioRouterStore.routeOutputDevices(from: devices)
    precondition(
        routedOutputs.map(\.uid) == ["built-in", "airpods", "living-room", "homepod", "benq", "vb-cable", "hdmi"],
        "Every connected macOS output should be shown, including display, virtual, AirPlay, Bluetooth, HomePod, and system speaker outputs"
    )

    let currentDefaultOutputs = [
        AudioDevice(audioObjectID: 10, uid: "built-in", name: "MacBook Speakers", kind: .output, channelCount: 2, transport: .builtIn, isDefault: false, isAlive: true),
        AudioDevice(audioObjectID: 11, uid: "selected-homepod", name: "Bedroom HomePod", kind: .output, channelCount: 2, transport: .unknown, isDefault: true, isAlive: true)
    ]
    precondition(AudioRouterStore.routeOutputDevices(from: currentDefaultOutputs).map(\.uid) == ["selected-homepod", "built-in"], "The current default output should remain selectable even when macOS reports it with an unknown transport")
}

func checkRouteBackwardCompatibility() {
    let json = """
    [{"sourceAppID":"spotify","outputDeviceID":"speaker","volume":0.8,"isMuted":false,"routeMode":"customDevice"}]
    """
    let routes = try! JSONDecoder().decode([AudioRoute].self, from: Data(json.utf8))
    precondition(routes.first?.routeMode == .customOutput, "Old customDevice route mode should migrate")
    precondition(routes.first?.status == .requiresBackend, "Migrated custom routes should be backend-required by default")
}

func checkRoutingManagerRoutesAndFallback() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let fileURL = directory.appendingPathComponent("routes.json")
    let manager = AudioRoutingManager(backend: FakeRoutingBackend(), fileURL: fileURL)

    let sources = manager.getActiveAudioSources()
    precondition(sources.first?.appName == "Spotify", "Expected fake Spotify source")
    manager.assignOutputDevice(sourceID: "spotify", deviceID: "speaker")

    let customRoute = manager.route(for: "spotify")
    precondition(customRoute.routeMode == .customOutput, "Route should be custom after output assignment")
    precondition(customRoute.status == .requiresBackend, "Public backend routes should be marked backend-required")
    precondition(customRoute.outputDeviceID == "speaker", "Route did not save the selected output")

    let reloaded = AudioRoutingManager(backend: FakeRoutingBackend(), fileURL: fileURL)
    precondition(reloaded.route(for: "spotify").outputDeviceID == "speaker", "Route did not persist")

    reloaded.handleDeviceDisconnected(deviceID: "speaker")
    precondition(reloaded.route(for: "spotify").routeMode == .customOutput, "Disconnected route should keep the saved custom route")
    precondition(reloaded.route(for: "spotify").status == .deviceMissing, "Disconnected route should be marked missing instead of reset")
    reloaded.handleDeviceReconnected(deviceID: "speaker")
    precondition(reloaded.route(for: "spotify").status == .savedOnly, "Reconnected route should be ready to retry")
}

func checkSupportedBackendFailuresStaySaved() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let manager = AudioRoutingManager(
        backend: FakeFailingSupportedRoutingBackend(),
        fileURL: directory.appendingPathComponent("routes.json")
    )

    manager.assignOutputDevice(sourceID: "spotify", deviceID: "speaker")
    let route = manager.route(for: "spotify")
    precondition(route.routeMode == .customOutput, "Failed supported route should keep the custom route")
    precondition(route.status == .savedOnly, "Recoverable supported-backend failures should be saved-only, not backend-required")
    precondition(manager.routeMessage(for: "spotify")?.contains("saved") == true, "Failed supported route should explain that the preference was saved")
}

func checkOutputGroupRoutesFanOut() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let backend = FakeGroupRoutingBackend()
    let manager = AudioRoutingManager(
        backend: backend,
        fileURL: directory.appendingPathComponent("routes.json")
    )

    let outputs = [
        AudioDevice(audioObjectID: 1, uid: "speaker-a", name: "Speaker A", kind: .output, channelCount: 2, transport: .bluetooth, isDefault: false, isAlive: true),
        AudioDevice(audioObjectID: 2, uid: "speaker-b", name: "Speaker B", kind: .output, channelCount: 2, transport: .bluetoothLE, isDefault: false, isAlive: true)
    ]
    manager.assignOutputGroup(sourceID: "spotify", groupID: "group:studio", outputDevices: outputs)

    let route = manager.route(for: "spotify")
    precondition(route.outputDeviceID == "group:studio", "Group route should save the group target id")
    precondition(route.status == .active, "Supported group route should become active")
    precondition(backend.routedOutputUIDs == ["speaker-a", "speaker-b"], "Backend should receive every output in the group")
    precondition(manager.routeMessage(for: "spotify")?.contains("2 outputs") == true, "Group route should report fan-out count")
}

func checkRouteAudioQualityPolicy() {
    let tapFormat = AudioStreamBasicDescription(
        mSampleRate: 96_000,
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagsNativeEndian,
        mBytesPerPacket: 6 * UInt32(MemoryLayout<Float32>.size),
        mFramesPerPacket: 1,
        mBytesPerFrame: 6 * UInt32(MemoryLayout<Float32>.size),
        mChannelsPerFrame: 6,
        mBitsPerChannel: 32,
        mReserved: 0
    )
    let studioInterface = AudioDevice(
        audioObjectID: 11,
        uid: "studio",
        name: "Studio Interface",
        kind: .output,
        channelCount: 8,
        transport: .usb,
        isDefault: false,
        isAlive: true,
        sampleRate: 48_000,
        availableSampleRateRanges: [AudioSampleRateRange(minimum: 44_100, maximum: 192_000)]
    )
    let bluetoothSpeaker = AudioDevice(
        audioObjectID: 12,
        uid: "speaker",
        name: "Bluetooth Speaker",
        kind: .output,
        channelCount: 2,
        transport: .bluetooth,
        isDefault: false,
        isAlive: true,
        sampleRate: 48_000,
        availableSampleRateRanges: [AudioSampleRateRange(minimum: 48_000, maximum: 48_000)]
    )

    let sourceRateFormat = RouteAudioQualityPolicy.playbackFormat(from: tapFormat, outputDevices: [studioInterface])
    precondition(sourceRateFormat.mSampleRate == 96_000, "Route quality should preserve the source tap sample rate when the output supports it")
    precondition(sourceRateFormat.mFormatID == kAudioFormatLinearPCM, "Route quality should use linear PCM")
    precondition((sourceRateFormat.mFormatFlags & kAudioFormatFlagIsFloat) != 0, "Route quality should keep 32-bit float samples")
    precondition(sourceRateFormat.mBitsPerChannel == 32, "Route quality should keep 32-bit samples")
    precondition(sourceRateFormat.mChannelsPerFrame == 6, "Route quality should keep the highest practical shared channel count")
    precondition(RouteAudioQualityPolicy.normalizedGain(1.006) == 1, "Route gain should snap tiny persisted over-unity drift back to clean 100%")

    let sharedOutputFormat = RouteAudioQualityPolicy.playbackFormat(
        from: tapFormat,
        outputDevices: [studioInterface, bluetoothSpeaker]
    )
    precondition(sharedOutputFormat.mSampleRate == 96_000, "Group routes should keep the source tap rate and let Core Audio convert at the output renderer")
    precondition(sharedOutputFormat.mChannelsPerFrame == 2, "Group routes should use the highest channel count shared by every output")

    let highBandwidthFormat = AudioStreamBasicDescription(
        mSampleRate: 192_000,
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagsNativeEndian,
        mBytesPerPacket: 8 * UInt32(MemoryLayout<Float32>.size),
        mFramesPerPacket: 1,
        mBytesPerFrame: 8 * UInt32(MemoryLayout<Float32>.size),
        mChannelsPerFrame: 8,
        mBitsPerChannel: 32,
        mReserved: 0
    )
    let highBandwidthBufferSize = RouteAudioQualityPolicy.outputBufferByteSize(for: highBandwidthFormat)
    let minimumHighBandwidthBufferSize = UInt32(
        ceil(highBandwidthFormat.mSampleRate * RouteAudioQualityPolicy.outputBufferDurationSeconds)
    ) * highBandwidthFormat.mBytesPerFrame
    precondition(
        highBandwidthBufferSize >= minimumHighBandwidthBufferSize,
        "High-rate multichannel routes should keep the full output-buffer duration instead of shrinking into callback-heavy chunks"
    )
    precondition(RouteAudioQualityPolicy.outputQueueBufferCount >= 8, "Live routes should retain enough queued buffers for short CPU spikes")
    precondition(RouteAudioQualityPolicy.outputQueueHeadroomSeconds >= 0.15, "Live routes should keep at least 150 ms of output headroom")
    precondition(RouteAudioQualityPolicy.routePipeBufferSeconds >= 3, "Live routes should retain source audio through longer scheduler stalls")
    precondition(
        RouteAudioQualityPolicy.validateRealtimeBufferCopying(),
        "Realtime route buffers should copy wrapped and overflowing sample blocks without an exclusivity conflict"
    )
}

func checkSourceAudioQualityDisplay() throws {
    let quality = SourceAudioQuality(sampleRate: 44_100, bitDepth: 32, channelCount: 2, isFloatPCM: true)
    precondition(quality.compactDisplayLabel == "44.1k", "Source quality should show only the sample rate in route rows")
    precondition(
        quality.accessibilityDescription == "44.1 kHz, floating point 32-bit, 2 channels",
        "Source quality should keep a readable expanded accessibility description"
    )

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let manager = AudioRoutingManager(
        backend: FakeQualityRoutingBackend(),
        fileURL: directory.appendingPathComponent("routes.json")
    )
    precondition(
        manager.sourceAudioQuality(for: "spotify")?.compactDisplayLabel == "44.1k",
        "AudioRoutingManager should expose backend source quality"
    )
}

@MainActor
func checkDeviceChangesDoNotSwitchSystemOutput() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let builtIn = AudioDevice(
        audioObjectID: 1,
        uid: "speaker",
        name: "MacBook Speakers",
        kind: .output,
        channelCount: 2,
        transport: .builtIn,
        isDefault: true,
        isAlive: true
    )
    let airPods = AudioDevice(
        audioObjectID: 2,
        uid: "airpods",
        name: "AirPods",
        kind: .output,
        channelCount: 2,
        transport: .bluetoothLE,
        isDefault: true,
        isAlive: true
    )

    let deviceManager = FakeDeviceManager(devices: [builtIn])
    let settings = AppSettingsStore(defaults: UserDefaults(suiteName: "AudioRouterChecks-\(UUID().uuidString)")!)
    let routingManager = AudioRoutingManager(
        backend: FakeRoutingBackend(),
        fileURL: directory.appendingPathComponent("routes.json")
    )
    routingManager.assignOutputDevice(sourceID: "spotify", deviceID: "speaker")
    let store = AudioRouterStore(
        deviceManager: deviceManager,
        settings: settings,
        audioRoutingManager: routingManager,
        outputGroupsURL: directory.appendingPathComponent("groups.json"),
        appSourcesURL: directory.appendingPathComponent("sources.json"),
        hiddenDefaultSourcesURL: directory.appendingPathComponent("hidden-defaults.json"),
        sourceOrderURL: directory.appendingPathComponent("source-order.json")
    )

    store.refresh(silent: true)
    precondition(store.currentOutput?.uid == "speaker", "Initial current output should be the built-in speaker")

    deviceManager.devices = [airPods]
    store.refresh(silent: true)
    precondition(deviceManager.defaultOutputSetRequests.isEmpty, "AudioRouter should not switch outputs while the previous output is temporarily absent")

    deviceManager.devices = [
        AudioDevice(
            audioObjectID: builtIn.audioObjectID,
            uid: builtIn.uid,
            name: builtIn.name,
            kind: builtIn.kind,
            channelCount: builtIn.channelCount,
            transport: builtIn.transport,
            isDefault: false,
            isAlive: builtIn.isAlive
        ),
        airPods
    ]
    store.refresh(silent: true)

    precondition(deviceManager.defaultOutputSetRequests.isEmpty, "AudioRouter should not switch system output during Bluetooth add/remove events")
    precondition(store.currentOutput?.uid == "airpods", "AudioRouter should reflect macOS's current output instead of forcing another switch")
    precondition(routingManager.route(for: "spotify").outputDeviceID == "speaker", "Existing custom route should remain assigned")
    precondition(routingManager.route(for: "spotify").routeMode == .customOutput, "Existing custom route should not reset on device addition")
}

func checkUpdateVersionComparison() {
    precondition(UpdateManager.releaseAssetName == "AudioRouter-macOS.zip", "Updater should fetch the ZIP release asset")
    precondition(UpdateManager.defaultAutomaticCheckInterval == 900, "Automatic update checks should poll often enough for release update notices")
    precondition(UpdateManager.isVersion("0.1.2", newerThan: "0.1.1"), "Patch update should compare newer")
    precondition(UpdateManager.isVersion("0.2.0", newerThan: "0.1.9"), "Minor update should compare newer")
    precondition(UpdateManager.isVersion("v0.1.10", newerThan: "0.1.9"), "Version tags with v prefixes should compare correctly")
    precondition(UpdateManager.isVersion("0.1.3-beta", newerThan: "0.1.2"), "Version tags with suffixes should compare by numeric parts")
    precondition(!UpdateManager.isVersion("0.1.1", newerThan: "0.1.1"), "Same version should not compare newer")
    precondition(!UpdateManager.isVersion("0.1.0", newerThan: "0.1.1"), "Older version should not compare newer")
    precondition(UpdateManager.displayVersion(from: " v0.1.2 ") == "0.1.2", "Display version should trim whitespace and v prefix")
}

@MainActor
func checkAutomaticUpdateCheckPersistence() {
    let suiteName = "AudioRouterChecks-\(UUID().uuidString)"
    let suite = UserDefaults(suiteName: suiteName)!
    defer { suite.removePersistentDomain(forName: suiteName) }

    let date = Date(timeIntervalSince1970: 1_779_966_000)
    suite.set(date, forKey: UpdateManager.lastAutomaticCheckDefaultsKey)
    let manager = UpdateManager(
        defaults: suite,
        automaticCheckInterval: 60,
        currentVersionProvider: { "1.0.0" }
    )

    precondition(manager.lastCheckedAt == date, "Automatic update check timestamp should persist across launches")
    precondition(manager.currentVersion == "1.0.0", "Injected current version should be used for update checks")
}

func checkPlaybackProtectionPersistence() {
    let suiteName = "AudioRouterChecks-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = AppSettingsStore(defaults: defaults)
    precondition(settings.protectPlaybackDuringDeviceChanges, "Bluetooth playback protection should default on")
    precondition(settings.keepMediaPlayingDuringDeviceChanges, "Media keep-alive should default on")
    settings.protectPlaybackDuringDeviceChanges = false
    settings.keepMediaPlayingDuringDeviceChanges = false

    let reloaded = AppSettingsStore(defaults: defaults)
    precondition(!reloaded.protectPlaybackDuringDeviceChanges, "Bluetooth playback protection toggle should persist")
    precondition(!reloaded.keepMediaPlayingDuringDeviceChanges, "Media keep-alive toggle should persist")
    reloaded.reset()

    let reset = AppSettingsStore(defaults: defaults)
    precondition(reset.protectPlaybackDuringDeviceChanges, "Reset should turn Bluetooth playback protection back on")
    precondition(reset.keepMediaPlayingDuringDeviceChanges, "Reset should turn media keep-alive back on")

    let legacyDefaultsSuiteName = "AudioRouterChecks-\(UUID().uuidString)"
    let legacyDefaults = UserDefaults(suiteName: legacyDefaultsSuiteName)!
    defer { legacyDefaults.removePersistentDomain(forName: legacyDefaultsSuiteName) }
    legacyDefaults.set(false, forKey: "AudioRouter.resumeMediaAfterDeviceChanges")
    precondition(!AppSettingsStore(defaults: legacyDefaults).keepMediaPlayingDuringDeviceChanges, "Keep-alive should migrate the previous media resume toggle")
}

func checkPlaybackKeepAliveCandidates() {
    let sources = [
        AudioSource(
            id: "spotify",
            appName: "Spotify",
            bundleIdentifier: "com.spotify.client",
            processID: 42,
            icon: nil,
            isProducingAudio: true
        ),
        AudioSource(
            id: "music",
            appName: "Apple Music",
            bundleIdentifier: "com.apple.Music",
            processID: 43,
            icon: nil,
            isProducingAudio: true
        ),
        AudioSource(
            id: "chrome",
            appName: "Chrome",
            bundleIdentifier: "com.google.Chrome",
            processID: 44,
            icon: nil,
            isProducingAudio: true
        )
    ]

    let candidates = PlaybackKeepAliveService.keepAliveCandidateBundleIdentifiers(
        from: sources,
        requireRunning: false
    )
    precondition(candidates == ["com.spotify.client", "com.apple.Music"], "Only scriptable media apps should be keep-alive candidates")
    precondition(
        PlaybackKeepAliveService.isSpotifyPausedPlaybackState(userInfo: ["Player State": "Paused"]),
        "Spotify paused notifications should trigger immediate keep-alive"
    )
    precondition(
        !PlaybackKeepAliveService.isSpotifyPausedPlaybackState(userInfo: ["Player State": "Playing"]),
        "Spotify playing notifications should not trigger keep-alive bursts"
    )
}

func checkAppInputPublishingMetadata() {
    let suiteName = "AudioRouterChecks-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = AppSettingsStore(defaults: defaults)
    precondition(settings.publishAppInputsAsSystemDevices, "App mixer input publishing should default on")
    settings.publishAppInputsAsSystemDevices = false
    precondition(!AppSettingsStore(defaults: defaults).publishAppInputsAsSystemDevices, "App mixer input publishing toggle should persist")

    let source = AudioSource(
        id: "com.spotify.client",
        appName: "Spotify",
        bundleIdentifier: "com.spotify.client",
        processID: 42,
        audioObjectID: 99,
        icon: nil,
        isProducingAudio: true
    )
    precondition(
        AppInputDevicePublisher.inputDeviceUID(for: source) == "com.local.AudioRouter.input.com.spotify.client",
        "Published app input UID should be stable for mixer software"
    )
    precondition(
        AppInputDevicePublisher.inputDeviceName(for: source) == "AudioRouter Spotify Input",
        "Published app input name should be clear in mixer software"
    )
}

@MainActor
func checkRouteHealthDiagnostics() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let settings = AppSettingsStore(defaults: UserDefaults(suiteName: "AudioRouterChecks-\(UUID().uuidString)")!)
    let store = AudioRouterStore(
        settings: settings,
        audioRoutingManager: AudioRoutingManager(backend: FakeRoutingBackend(), fileURL: directory.appendingPathComponent("routes.json")),
        outputGroupsURL: directory.appendingPathComponent("groups.json"),
        appSourcesURL: directory.appendingPathComponent("sources.json"),
        hiddenDefaultSourcesURL: directory.appendingPathComponent("hidden-defaults.json"),
        sourceOrderURL: directory.appendingPathComponent("source-order.json")
    )
    store.refresh()
    guard let source = store.audioSources.first else {
        preconditionFailure("Expected at least one fake source")
    }
    let health = store.routeHealthItems(for: source)
    precondition(health.contains { $0.id == "configured" }, "Route health should include configured app check")
    precondition(health.contains { $0.id == "backend" }, "Route health should include backend check")
    store.assignSourceOutput(source: source, uid: "speaker")
    precondition(store.routeFailureReason(for: source)?.contains("backend") == true
        || store.routeFailureReason(for: source)?.contains("route") == true,
        "Custom route should expose a useful failure reason")
}

@MainActor
func checkCustomRouteAppPersistence() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let fakeAppURL = directory.appendingPathComponent("WaveLab.app", isDirectory: true)
    let contentsURL = fakeAppURL.appendingPathComponent("Contents", isDirectory: true)
    try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
    let plist: [String: String] = [
        "CFBundleIdentifier": "com.example.WaveLab",
        "CFBundleName": "WaveLab",
        "CFBundlePackageType": "APPL"
    ]
    let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try plistData.write(to: contentsURL.appendingPathComponent("Info.plist"))

    let settingsSuite = UserDefaults(suiteName: "AudioRouterChecks-\(UUID().uuidString)")!
    let settings = AppSettingsStore(defaults: settingsSuite)
    settings.demoMode = true

    let appSourcesURL = directory.appendingPathComponent("app-sources.json")
    let routesURL = directory.appendingPathComponent("routes.json")
    let outputGroupsURL = directory.appendingPathComponent("output-groups.json")
    let hiddenDefaultSourcesURL = directory.appendingPathComponent("hidden-defaults.json")
    let sourceOrderURL = directory.appendingPathComponent("source-order.json")
    let store = AudioRouterStore(
        settings: settings,
        audioRoutingManager: AudioRoutingManager(backend: FakeRoutingBackend(), fileURL: routesURL),
        outputGroupsURL: outputGroupsURL,
        appSourcesURL: appSourcesURL,
        hiddenDefaultSourcesURL: hiddenDefaultSourcesURL,
        sourceOrderURL: sourceOrderURL
    )

    precondition(store.routeAppDisplayNames.contains("Spotify"), "Default route apps should be visible")
    store.refresh()
    guard let spotify = store.audioSources.first(where: { $0.bundleIdentifier == "com.spotify.client" }) else {
        preconditionFailure("Default Spotify source should be present in demo mode")
    }
    store.removeRouteApp(spotify)
    precondition(!store.routeAppDisplayNames.contains("Spotify"), "Default route app should be hideable")
    store.restoreDefaultRouteApps()
    precondition(store.routeAppDisplayNames.contains("Spotify"), "Hidden default route apps should be restorable")

    store.addRouteApp(bundleURL: fakeAppURL)
    precondition(store.routeAppDisplayNames.contains("WaveLab"), "Added app should appear in route app list")
    precondition(store.routeAppDisplayNames.last == "WaveLab", "New route apps should be added after default apps")
    precondition(store.audioSources.contains { $0.bundleIdentifier == "com.example.WaveLab" }, "Added app should appear as an audio source")

    let countAfterFirstAdd = store.routeAppDisplayNames.count
    store.addRouteApp(bundleURL: fakeAppURL)
    precondition(store.routeAppDisplayNames.count == countAfterFirstAdd, "Adding the same app twice should not duplicate it")

    guard let waveLab = store.audioSources.first(where: { $0.bundleIdentifier == "com.example.WaveLab" }) else {
        preconditionFailure("Added route app should be available for ordering")
    }
    while store.canMoveRouteApp(waveLab, offset: -1) {
        store.moveRouteApp(waveLab, offset: -1)
    }
    precondition(store.routeAppDisplayNames.first == "WaveLab", "Custom app order should be editable")
    precondition(
        store.reorderRouteApp(draggedSourceID: waveLab.id, targetSourceID: "com.google.Chrome"),
        "Drag/drop route app ordering should accept source and target IDs"
    )
    precondition(store.routeAppDisplayNames.last == "WaveLab", "Drag/drop route app ordering should move the dragged app")

    let reloadedSettings = AppSettingsStore(defaults: settingsSuite)
    reloadedSettings.demoMode = true
    let reloaded = AudioRouterStore(
        settings: reloadedSettings,
        audioRoutingManager: AudioRoutingManager(backend: FakeRoutingBackend(), fileURL: routesURL),
        outputGroupsURL: outputGroupsURL,
        appSourcesURL: appSourcesURL,
        hiddenDefaultSourcesURL: hiddenDefaultSourcesURL,
        sourceOrderURL: sourceOrderURL
    )
    precondition(reloaded.routeAppDisplayNames.contains("WaveLab"), "Added route app should persist")
    precondition(reloaded.routeAppDisplayNames.last == "WaveLab", "Custom route app order should persist")

    reloaded.refresh()
    guard let customSource = reloaded.audioSources.first(where: { $0.bundleIdentifier == "com.example.WaveLab" }) else {
        preconditionFailure("Reloaded route app should become a source")
    }
    reloaded.removeRouteApp(customSource)
    precondition(!reloaded.routeAppDisplayNames.contains("WaveLab"), "Removed route app should leave the configured list")
}

@MainActor
func checkFocusedSourceIconsStayWithConfiguredApps() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let settings = AppSettingsStore(defaults: UserDefaults(suiteName: "AudioRouterChecks-\(UUID().uuidString)")!)
    let store = AudioRouterStore(
        deviceManager: FakeDeviceManager(devices: []),
        settings: settings,
        audioRoutingManager: AudioRoutingManager(
            backend: FakeChromeHelperOnlyBackend(),
            fileURL: directory.appendingPathComponent("routes.json")
        ),
        outputGroupsURL: directory.appendingPathComponent("groups.json"),
        appSourcesURL: directory.appendingPathComponent("sources.json"),
        hiddenDefaultSourcesURL: directory.appendingPathComponent("hidden-defaults.json"),
        sourceOrderURL: directory.appendingPathComponent("source-order.json")
    )

    store.refresh(silent: true)

    guard let spotify = store.audioSources.first(where: { $0.bundleIdentifier == "com.spotify.client" }),
          let chrome = store.audioSources.first(where: { $0.bundleIdentifier == "com.google.Chrome" }) else {
        preconditionFailure("Default focused sources should be present")
    }

    precondition(spotify.processID == 0, "Spotify should not borrow Chrome's helper process")
    precondition(spotify.icon == "/Applications/Spotify.app", "Spotify should keep its configured real app icon")
    precondition(chrome.processID == 99, "Chrome should match its helper process")
    precondition(chrome.icon == "/Applications/Google Chrome.app", "Chrome should keep its configured app icon")
}

private final class FakeRoutingBackend: AudioRoutingBackend {
    let supportsPerAppRouting = false
    let backendName = "Fake"

    func listAudioSources() throws -> [AudioSource] {
        [
            AudioSource(
                id: "spotify",
                appName: "Spotify",
                bundleIdentifier: "com.spotify.client",
                processID: 42,
                icon: nil,
                isProducingAudio: true
            )
        ]
    }

    func listOutputDevices() throws -> [AudioDevice] {
        [
            AudioDevice(
                audioObjectID: 1,
                uid: "speaker",
                name: "Bluetooth Speaker",
                kind: .output,
                channelCount: 2,
                transport: .bluetooth,
                isDefault: false,
                isAlive: true
            )
        ]
    }

    func routeSourceToDevice(sourceID: String, deviceID: String?) throws {}
    func setSourceVolume(sourceID: String, volume: Double) throws {}
    func muteSource(sourceID: String, muted: Bool) throws {}
}

private final class FakeFailingSupportedRoutingBackend: AudioRoutingBackend {
    let supportsPerAppRouting = true
    let backendName = "Failing Supported Fake"

    func listAudioSources() throws -> [AudioSource] {
        [
            AudioSource(
                id: "spotify",
                appName: "Spotify",
                bundleIdentifier: "com.spotify.client",
                processID: 42,
                audioObjectID: 99,
                icon: nil,
                isProducingAudio: true
            )
        ]
    }

    func listOutputDevices() throws -> [AudioDevice] {
        [
            AudioDevice(
                audioObjectID: 1,
                uid: "speaker",
                name: "Bluetooth Speaker",
                kind: .output,
                channelCount: 2,
                transport: .bluetooth,
                isDefault: false,
                isAlive: true
            )
        ]
    }

    func routeSourceToDevice(sourceID: String, deviceID: String?) throws {
        throw AudioRoutingBackendError.unsupported("Start playback, refresh, then retry.")
    }

    func setSourceVolume(sourceID: String, volume: Double) throws {}
    func muteSource(sourceID: String, muted: Bool) throws {}
}

private final class FakeGroupRoutingBackend: AudioRoutingBackend {
    let supportsPerAppRouting = true
    let backendName = "Group Fake"
    private(set) var routedOutputUIDs: [String] = []

    func listAudioSources() throws -> [AudioSource] {
        [
            AudioSource(
                id: "spotify",
                appName: "Spotify",
                bundleIdentifier: "com.spotify.client",
                processID: 42,
                audioObjectID: 99,
                icon: nil,
                isProducingAudio: true
            )
        ]
    }

    func listOutputDevices() throws -> [AudioDevice] { [] }

    func routeSourceToDevice(sourceID: String, deviceID: String?) throws {
        routedOutputUIDs = deviceID.map { [$0] } ?? []
    }

    func routeSourceToDevices(sourceID: String, outputDevices: [AudioDevice]) throws {
        routedOutputUIDs = outputDevices.map(\.uid)
    }

    func setSourceVolume(sourceID: String, volume: Double) throws {}
    func muteSource(sourceID: String, muted: Bool) throws {}
}

private final class FakeQualityRoutingBackend: AudioRoutingBackend {
    let supportsPerAppRouting = true
    let backendName = "Quality Fake"

    func listAudioSources() throws -> [AudioSource] { [] }
    func listOutputDevices() throws -> [AudioDevice] { [] }
    func routeSourceToDevice(sourceID: String, deviceID: String?) throws {}
    func setSourceVolume(sourceID: String, volume: Double) throws {}
    func muteSource(sourceID: String, muted: Bool) throws {}

    func sourceAudioQuality(sourceID: String) -> SourceAudioQuality? {
        sourceID == "spotify"
            ? SourceAudioQuality(sampleRate: 44_100, bitDepth: 32, channelCount: 2, isFloatPCM: true)
            : nil
    }
}

private final class FakeChromeHelperOnlyBackend: AudioRoutingBackend {
    let supportsPerAppRouting = true
    let backendName = "Chrome Helper Fake"

    func listAudioSources() throws -> [AudioSource] {
        [
            AudioSource(
                id: "com.google.Chrome.helper",
                appName: "Google Chrome Helper",
                bundleIdentifier: "com.google.Chrome.helper",
                processID: 99,
                audioObjectID: 101,
                icon: "/Applications/Google Chrome.app",
                isProducingAudio: true
            )
        ]
    }

    func listOutputDevices() throws -> [AudioDevice] { [] }
    func routeSourceToDevice(sourceID: String, deviceID: String?) throws {}
    func setSourceVolume(sourceID: String, volume: Double) throws {}
    func muteSource(sourceID: String, muted: Bool) throws {}
}

private final class FakeDeviceManager: AudioDeviceManaging {
    var devices: [AudioDevice]
    private(set) var defaultOutputSetRequests: [String] = []

    init(devices: [AudioDevice]) {
        self.devices = devices
    }

    func refreshDevices() throws -> [AudioDevice] {
        devices
    }

    func listOutputDevices() throws -> [AudioOutputDevice] {
        devices.filter { $0.kind == .output }
    }

    func listInputDevices() throws -> [AudioDevice] {
        devices.filter { $0.kind == .input }
    }

    func getDefaultOutputDevice() throws -> AudioOutputDevice? {
        try listOutputDevices().first { $0.isDefault }
    }

    func getDefaultInputDevice() throws -> AudioDevice? {
        try listInputDevices().first { $0.isDefault }
    }

    func setDefaultOutputDevice(deviceID: String) throws {
        try setDefaultDevice(uid: deviceID, kind: .output)
    }

    func setDefaultInputDevice(deviceID: String) throws {
        try setDefaultDevice(uid: deviceID, kind: .input)
    }

    func setDefaultDevice(uid: String, kind: AudioDeviceKind) throws {
        if kind == .output {
            defaultOutputSetRequests.append(uid)
        }
        devices = devices.map { device in
            AudioDevice(
                audioObjectID: device.audioObjectID,
                uid: device.uid,
                name: device.name,
                kind: device.kind,
                channelCount: device.channelCount,
                transport: device.transport,
                isDefault: device.kind == kind && device.uid == uid,
                isAlive: device.isAlive,
                volume: device.volume,
                isMuted: device.isMuted,
                balance: device.balance,
                sampleRate: device.sampleRate,
                availableSampleRateRanges: device.availableSampleRateRanges,
                canSetVolume: device.canSetVolume,
                canSetMute: device.canSetMute,
                canSetBalance: device.canSetBalance
            )
        }
    }

    func getDeviceVolume(deviceID: String) throws -> Double? {
        devices.first { $0.uid == deviceID }?.volume
    }

    func setVolume(uid: String, kind: AudioDeviceKind, volume: Double) throws {}
    func setDeviceVolume(deviceID: String, volume: Double) throws {}

    func getDeviceMute(deviceID: String) throws -> Bool? {
        devices.first { $0.uid == deviceID }?.isMuted
    }

    func setMuted(uid: String, kind: AudioDeviceKind, isMuted: Bool) throws {}
    func setDeviceMute(deviceID: String, muted: Bool) throws {}

    func getDeviceBalance(deviceID: String) throws -> Double? {
        devices.first { $0.uid == deviceID }?.balance
    }

    func setBalance(uid: String, kind: AudioDeviceKind, balance: Double) throws {}
    func setDeviceBalance(deviceID: String, balance: Double) throws {}

    func observeDeviceChanges(_ onChange: @escaping @Sendable () -> Void) -> DevicePropertyObservation? {
        nil
    }
}

do {
    if CommandLine.arguments.contains("--dump-outputs") {
        try dumpRealOutputDevices()
        exit(0)
    }
    if CommandLine.arguments.contains("--dump-airplay") {
        dumpAirPlayRouteCandidates()
        exit(0)
    }

    try MainActor.assumeIsolated {
        try runChecks()
    }
    print("AudioRouter checks passed")
} catch {
    fputs("AudioRouter checks failed: \(error)\n", stderr)
    exit(1)
}
