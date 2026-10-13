import Combine
import Foundation

@MainActor
public final class AudioRouterStore: ObservableObject {
    @Published public private(set) var devices: [AudioDevice] = []
    @Published public private(set) var audioSources: [AudioSource] = []
    @Published public private(set) var availableAppCandidates: [AudioSource] = []
    @Published public private(set) var airPlayRouteCandidates: [AirPlayRouteCandidate] = []
    @Published public private(set) var lastError: String?
    @Published public private(set) var unsupportedNote: String?
    @Published public var selectedSettingsSection: SettingsSection = .dashboard
    @Published public var soloSourceID: String?
    @Published public var selectedSourceID: String? {
        didSet {
            if selectedSourceID != oldValue, selectedSourceID != nil {
                selectedOutputDeviceID = nil
            }
        }
    }
    @Published public var selectedOutputDeviceID: String? {
        didSet {
            if selectedOutputDeviceID != oldValue, selectedOutputDeviceID != nil {
                selectedSourceID = nil
            }
        }
    }
    @Published public private(set) var preparingRouteSourceIDs: Set<String> = []
    @Published public private(set) var meteringNote: String = "Live meters appear when a process-tap route is active."
    @Published public private(set) var processTapProbeMessage: String?
    @Published public private(set) var publishedAppInputDevices: [PublishedAppInputDevice] = []
    @Published public var isOnboardingPresented = false
    @Published public var outputGroups: [OutputDeviceGroup] = [] {
        didSet { saveOutputGroups() }
    }

    public let settings: AppSettingsStore
    public let eqManager: EQManager
    public let presetManager: PresetManager
    public let userProfileManager: UserProfileManager
    public let shortcutManager: ShortcutManager
    public let updateManager: UpdateManager
    public let meterState = AudioMeterState()

    private let deviceManager: AudioDeviceManaging
    private let volumeManager: SystemVolumeManager
    private let audioRoutingManager: AudioRoutingManager
    private let processAudioMonitor: ProcessAudioMonitor
    private let appInputPublisher: AppInputPublishing
    private let playbackKeepAliveService: PlaybackKeepAliveService
    private let outputTestToneService: OutputTestToneService
    private let airPlayRouteDiscoveryService: AirPlayRouteDiscoveryService
    private var refreshTimer: Timer?
    private var meterTimer: Timer?
    private var deviceObservation: DevicePropertyObservation?
    private var pendingVolumeTasks: [String: Task<Void, Never>] = [:]
    private var pendingBalanceTasks: [String: Task<Void, Never>] = [:]
    private var pendingSourceVolumeTasks: [String: Task<Void, Never>] = [:]
    private var pendingSourceVolumes: [String: Double] = [:]
    private var lastDeviceVolumeCommitDates: [String: Date] = [:]
    private var pendingRefreshTask: Task<Void, Never>?
    private var pendingDeviceRefreshTask: Task<Void, Never>?
    private var pendingPlaybackKeepAliveTask: Task<Void, Never>?
    private var mediaKeepAliveWatchdogTask: Task<Void, Never>?
    private var pendingRoutePreparationTasks: [String: Task<Void, Never>] = [:]
    private var meterPhase: Double = 0
    private var lastRefreshUsedDemoMode: Bool?
    private var autoRetriedRouteSignatures: Set<String> = []
    private var deviceTopologySettlingUntil: Date?
    private var cancellables: Set<AnyCancellable> = []
    private let outputGroupsURL: URL
    private let appSourcesURL: URL
    private let hiddenDefaultSourcesURL: URL
    private let sourceOrderURL: URL
    private var userSourceSpecs: [FocusedSourceSpec]
    private var hiddenDefaultSourceIDs: Set<String>
    private var sourceOrderIDs: [String]
    private var pendingDeviceDisconnectTasks: [String: Task<Void, Never>] = [:]
    private let refreshInterval: TimeInterval = 18
    private let meterInterval: TimeInterval = 0.10
    private let meterPublishThreshold = 0.005
    private let deviceVolumeCommitInterval: TimeInterval = 0.10
    private let deviceDisconnectGraceInterval: TimeInterval = 12
    private let protectedDeviceDisconnectGraceInterval: TimeInterval = 30
    private let deviceChangeRouteRetrySuppressionInterval: TimeInterval = 20
    private let protectedDeviceRefreshDelay: TimeInterval = 2.5
    private let protectedDeviceRefreshFollowUpDelay: TimeInterval = 6.5
    private let mediaKeepAliveWatchdogInterval: TimeInterval = 1.2
    private let playbackKeepAliveAttemptDelays: [TimeInterval] = [0, 0.18, 0.42, 0.78, 1.2, 1.8, 2.7, 4, 6, 9, 13, 18, 24, 30]

    public init(
        deviceManager: AudioDeviceManaging = AudioDeviceService(),
        settings: AppSettingsStore = AppSettingsStore(),
        eqManager: EQManager = EQManager(),
        presetManager: PresetManager = PresetManager(),
        userProfileManager: UserProfileManager = UserProfileManager(),
        shortcutManager: ShortcutManager = ShortcutManager(),
        updateManager: UpdateManager? = nil,
        audioRoutingManager: AudioRoutingManager = AudioRoutingManager(),
        processAudioMonitor: ProcessAudioMonitor = ProcessAudioMonitor(),
        appInputPublisher: AppInputPublishing = AppInputDevicePublisher(),
        playbackKeepAliveService: PlaybackKeepAliveService = PlaybackKeepAliveService(),
        outputTestToneService: OutputTestToneService = OutputTestToneService(),
        airPlayRouteDiscoveryService: AirPlayRouteDiscoveryService = AirPlayRouteDiscoveryService(),
        outputGroupsURL: URL = try! AppSupport.fileURL(named: "output-groups.json"),
        appSourcesURL: URL = try! AppSupport.fileURL(named: "audio-sources.json"),
        hiddenDefaultSourcesURL: URL = try! AppSupport.fileURL(named: "hidden-default-sources.json"),
        sourceOrderURL: URL = try! AppSupport.fileURL(named: "source-order.json")
    ) {
        self.deviceManager = deviceManager
        self.volumeManager = SystemVolumeManager(deviceManager: deviceManager)
        self.settings = settings
        self.eqManager = eqManager
        self.presetManager = presetManager
        self.userProfileManager = userProfileManager
        self.shortcutManager = shortcutManager
        self.updateManager = updateManager ?? UpdateManager()
        self.audioRoutingManager = audioRoutingManager
        self.processAudioMonitor = processAudioMonitor
        self.appInputPublisher = appInputPublisher
        self.playbackKeepAliveService = playbackKeepAliveService
        self.outputTestToneService = outputTestToneService
        self.airPlayRouteDiscoveryService = airPlayRouteDiscoveryService
        self.outputGroupsURL = outputGroupsURL
        self.appSourcesURL = appSourcesURL
        self.hiddenDefaultSourcesURL = hiddenDefaultSourcesURL
        self.sourceOrderURL = sourceOrderURL
        self.userSourceSpecs = Self.loadUserSourceSpecs(from: appSourcesURL)
        self.hiddenDefaultSourceIDs = Self.loadHiddenDefaultSourceIDs(from: hiddenDefaultSourcesURL)
        self.sourceOrderIDs = Self.loadSourceOrderIDs(from: sourceOrderURL)
        self.outputGroups = (try? Data(contentsOf: outputGroupsURL))
            .flatMap { try? JSONDecoder().decode([OutputDeviceGroup].self, from: $0) } ?? []

        settings.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        audioRoutingManager.setEQState(eqManager.state)
        eqManager.$state
            .sink { [weak self] state in
                self?.audioRoutingManager.setEQState(state)
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        presetManager.setActiveProfileID(userProfileManager.activeProfileID)
        userProfileManager.$activeProfileID
            .sink { [weak self] profileID in
                self?.presetManager.setActiveProfileID(profileID)
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        userProfileManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        presetManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        shortcutManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        self.updateManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        airPlayRouteDiscoveryService.$candidates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] candidates in
                self?.airPlayRouteCandidates = candidates
            }
            .store(in: &cancellables)
    }

    public var outputDevices: [AudioDevice] {
        Self.routeOutputDevices(from: devices)
    }

    public var inputDevices: [AudioDevice] {
        devices.filter { $0.kind == .input }
    }

    public var currentOutput: AudioDevice? {
        outputDevices.first { $0.isDefault } ?? outputDevices.first
    }

    nonisolated public static func routeOutputDevices(from devices: [AudioDevice]) -> [AudioDevice] {
        let outputs = devices.filter { $0.kind == .output && $0.isAlive }

        if let defaultOutput = outputs.first(where: { $0.isDefault }) {
            return ([defaultOutput] + outputs).uniquedByUID()
        }

        return outputs.uniquedByUID()
    }

    public var currentInput: AudioDevice? {
        inputDevices.first { $0.isDefault } ?? inputDevices.first
    }

    public var routingBackendName: String {
        audioRoutingManager.backendName
    }

    public var supportsTruePerAppRouting: Bool {
        audioRoutingManager.supportsTruePerAppRouting
    }

    public var supportsPerAppVolume: Bool {
        audioRoutingManager.supportsPerAppVolume || settings.demoMode
    }

    public var supportsPerAppMute: Bool {
        audioRoutingManager.supportsPerAppMute || settings.demoMode
    }

    public var liveMeteringAvailable: Bool {
        !settings.demoMode
            && audioRoutingManager.supportsLiveProcessMeters
            && audioSources.contains { source in
                let route = audioRoutingManager.route(for: source.id)
                return route.routeMode == .customOutput && route.status == .active
            }
    }

    public var activeLiveRouteCount: Int {
        guard !settings.demoMode else { return 0 }
        return audioSources.filter { source in
            let route = audioRoutingManager.route(for: source.id)
            return route.routeMode == .customOutput && route.status == .active
        }.count
    }

    public var savedCustomRouteCount: Int {
        audioSources.filter { source in
            let route = audioRoutingManager.route(for: source.id)
            return route.routeMode == .customOutput && route.status != .active
        }.count
    }

    public var routeableSourceCount: Int {
        audioSources.filter { $0.audioObjectID != nil }.count
    }

    public var backendReadinessState: BackendReadinessState {
        if settings.demoMode {
            return .demo
        }
        if activeLiveRouteCount > 0 {
            return .live
        }
        if !audioRoutingManager.supportsTruePerAppRouting {
            return .unsupported
        }
        if routeableSourceCount > 0 && !outputDevices.isEmpty {
            return .ready
        }
        if savedCustomRouteCount > 0 {
            return .savedOnly
        }
        return .working
    }

    public var backendReadinessTitle: String {
        switch backendReadinessState {
        case .live:
            return activeLiveRouteCount == 1 ? "1 Live Route" : "\(activeLiveRouteCount) Live Routes"
        case .ready:
            return "Ready"
        case .working:
            return "Available"
        default:
            return backendReadinessState.badgeTitle
        }
    }

    public var backendReadinessDetail: String {
        if settings.demoMode {
            return "Demo data is active; switch to Live Mode for real devices and route attempts."
        }
        if activeLiveRouteCount > 0 {
            return "Process-tap routing is rendering selected app audio to chosen outputs."
        }
        if !audioRoutingManager.supportsTruePerAppRouting {
            return "System device control works; live app routing needs macOS 14.2 or newer."
        }
        if outputDevices.isEmpty {
            return "Connect a Bluetooth output or use the built-in speaker, then refresh."
        }
        if routeableSourceCount == 0 {
            return "Play audio in a configured app, then refresh to make the source routeable."
        }
        if savedCustomRouteCount > 0 {
            return "Saved routes are ready to retry when their app audio becomes available."
        }
        return "Device control is live. App routes can be attempted when a configured source is producing audio."
    }

    public var backendReadinessItems: [BackendReadinessItem] {
        let outputState: BackendReadinessState = outputDevices.isEmpty ? .deviceMissing : .working
        let sourceState: BackendReadinessState
        if settings.demoMode {
            sourceState = .demo
        } else if routeableSourceCount > 0 {
            sourceState = .working
        } else {
            sourceState = .savedOnly
        }

        let tapState: BackendReadinessState
        if settings.demoMode {
            tapState = .demo
        } else if activeLiveRouteCount > 0 {
            tapState = .live
        } else if audioRoutingManager.supportsTruePerAppRouting {
            tapState = .ready
        } else {
            tapState = .unsupported
        }

        let routeState: BackendReadinessState
        if settings.demoMode {
            routeState = .demo
        } else if activeLiveRouteCount > 0 {
            routeState = .live
        } else if savedCustomRouteCount > 0 {
            routeState = .savedOnly
        } else if audioRoutingManager.supportsTruePerAppRouting {
            routeState = .ready
        } else {
            routeState = .requiresBackend
        }

        return [
            BackendReadinessItem(
                id: "devices",
                title: "Devices",
                detail: outputDevices.isEmpty
                    ? "No route outputs loaded"
                    : "\(outputDevices.count) route output\(outputDevices.count == 1 ? "" : "s") available",
                state: outputState
            ),
            BackendReadinessItem(
                id: "sources",
                title: "Route Apps",
                detail: routeableSourceCount > 0
                    ? "\(routeableSourceCount) app\(routeableSourceCount == 1 ? "" : "s") exposing Core Audio output"
                    : "\(configuredSourceSpecs.count) configured app\(configuredSourceSpecs.count == 1 ? "" : "s") waiting for playback",
                state: sourceState
            ),
            BackendReadinessItem(
                id: "process-taps",
                title: "Process Taps",
                detail: meteringNote,
                state: tapState
            ),
            BackendReadinessItem(
                id: "routes",
                title: "Custom Routes",
                detail: routeSummaryText,
                state: routeState
            )
        ]
    }

    public func start() {
        refresh()
        if !settings.demoMode {
            airPlayRouteDiscoveryService.start()
        }
        startDeviceObservationIfNeeded()
        updateManager.startAutomaticChecks(enabled: settings.automaticallyCheckForUpdates)
        startImmediatePlaybackObserversIfNeeded()
        startMediaKeepAliveWatchdogIfNeeded()
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh(silent: true)
            }
        }
        refreshTimer?.tolerance = 2
        configureMeterTimer()
    }

    public func stop() {
        airPlayRouteDiscoveryService.stop()
        refreshTimer?.invalidate()
        refreshTimer = nil
        meterTimer?.invalidate()
        meterTimer = nil
        pendingVolumeTasks.values.forEach { $0.cancel() }
        pendingVolumeTasks.removeAll()
        lastDeviceVolumeCommitDates.removeAll()
        pendingBalanceTasks.values.forEach { $0.cancel() }
        pendingBalanceTasks.removeAll()
        for (sourceID, volume) in pendingSourceVolumes {
            audioRoutingManager.setSourceVolume(sourceID: sourceID, volume: volume, persist: true)
        }
        pendingSourceVolumes.removeAll()
        pendingSourceVolumeTasks.values.forEach { $0.cancel() }
        pendingSourceVolumeTasks.removeAll()
        pendingRefreshTask?.cancel()
        pendingRefreshTask = nil
        pendingDeviceRefreshTask?.cancel()
        pendingDeviceRefreshTask = nil
        pendingPlaybackKeepAliveTask?.cancel()
        pendingPlaybackKeepAliveTask = nil
        mediaKeepAliveWatchdogTask?.cancel()
        mediaKeepAliveWatchdogTask = nil
        playbackKeepAliveService.stopImmediatePlaybackObservers()
        pendingRoutePreparationTasks.values.forEach { $0.cancel() }
        pendingRoutePreparationTasks.removeAll()
        pendingDeviceDisconnectTasks.values.forEach { $0.cancel() }
        pendingDeviceDisconnectTasks.removeAll()
        outputTestToneService.stopAll()
        appInputPublisher.stopAll()
        publishedAppInputDevices = []
        deviceObservation?.cancel()
        deviceObservation = nil
        updateManager.stopAutomaticChecks()
    }

    public func refresh(silent: Bool = false) {
        do {
            let usingDemoMode = settings.demoMode
            let previousOutputUIDs = Self.aliveOutputUIDs(from: devices)
            let hadDeviceSnapshot = lastRefreshUsedDemoMode != nil || !devices.isEmpty
            var refreshedDevices: [AudioDevice]
            if usingDemoMode {
                airPlayRouteDiscoveryService.stop()
                deviceObservation?.cancel()
                deviceObservation = nil
                if lastRefreshUsedDemoMode != true || devices.isEmpty {
                    refreshedDevices = demoDevices
                } else {
                    refreshedDevices = devices
                }
            } else {
                airPlayRouteDiscoveryService.start()
                refreshedDevices = try deviceManager.refreshDevices()
            }
            let currentOutputUIDs = Self.aliveOutputUIDs(from: refreshedDevices)
            if hadDeviceSnapshot, currentOutputUIDs != previousOutputUIDs {
                noteDeviceTopologyIsSettling()
                schedulePlaybackKeepAliveAfterDeviceChange()
            }
            if refreshedDevices != devices {
                devices = refreshedDevices
            }
            lastRefreshUsedDemoMode = usingDemoMode
            let nextMeteringNote: String
            if usingDemoMode {
                nextMeteringNote = "Demo Mode uses animated meters for UI testing."
            } else {
                startDeviceObservationIfNeeded()
                nextMeteringNote = processAudioMonitor.meterAvailabilityMessage
            }
            if meteringNote != nextMeteringNote {
                meteringNote = nextMeteringNote
            }
            for disconnectedUID in previousOutputUIDs.subtracting(currentOutputUIDs) {
                scheduleDeviceMissingCheck(for: disconnectedUID)
            }
            for reconnectedUID in currentOutputUIDs.subtracting(previousOutputUIDs) {
                pendingDeviceDisconnectTasks[reconnectedUID]?.cancel()
                pendingDeviceDisconnectTasks.removeValue(forKey: reconnectedUID)
                if audioRoutingManager.hasDeviceMissingRoute(forDeviceID: reconnectedUID) {
                    audioRoutingManager.handleDeviceReconnected(deviceID: reconnectedUID)
                }
            }
            var refreshedSources = usingDemoMode ? demoSources : focusedSources(from: audioRoutingManager.getActiveAudioSources())
            if !usingDemoMode {
                reconcileAirPlayRoutes(using: &refreshedSources)
            }
            if refreshedSources != audioSources {
                audioSources = refreshedSources
            }
            syncAppInputDevices(using: refreshedSources)
            if !settings.protectPlaybackDuringDeviceChanges || !isDeviceTopologySettling {
                ensureSelectedOutputDeviceStillExists()
                ensureSelectedSourceStillExists()
            }
            retryReadySavedRoutes(using: refreshedSources)
            if !silent || availableAppCandidates.isEmpty {
                updateAvailableAppCandidates()
            }
            configureMeterTimer()
            if let warning = audioRoutingManager.lastWarning, unsupportedNote != warning {
                unsupportedNote = warning
            }
            if !silent {
                lastError = nil
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func applyActivationPolicy() {
        settings.applyActivationPolicy()
    }

    public func checkForUpdates() {
        updateManager.checkForUpdates()
    }

    public func setAutomaticallyCheckForUpdates(_ enabled: Bool) {
        settings.automaticallyCheckForUpdates = enabled
        if enabled {
            updateManager.startAutomaticChecks(enabled: true)
            updateManager.checkAutomaticallyIfNeeded(enabled: true, force: true)
        } else {
            updateManager.stopAutomaticChecks()
        }
    }

    public func openUpdateDownload() {
        updateManager.openLatestDownload()
    }

    public func downloadAvailableUpdate() {
        updateManager.fetchAvailableUpdate()
    }

    public func installDownloadedUpdate() {
        updateManager.installDownloadedUpdate()
    }

    public func dismissUpdatePrompt() {
        updateManager.dismissInstallPrompt()
    }

    public func openLatestRelease() {
        updateManager.openLatestRelease()
    }

    public func openSystemAudioPermissionSettings() {
        PermissionsManager.openSystemAudioRecordingSettings()
    }

    public func completeOnboarding() {
        settings.hasCompletedOnboarding = true
        isOnboardingPresented = false
    }

    public func showOnboarding() {
        settings.hasCompletedOnboarding = false
        selectedSettingsSection = .dashboard
        isOnboardingPresented = true
    }

    public func dismissOnboardingForNow() {
        isOnboardingPresented = false
    }

    public func setDefaultDevice(_ device: AudioDevice) {
        if settings.demoMode {
            devices = devices.map { $0.kind == device.kind ? copyDevice($0, isDefault: $0.uid == device.uid) : $0 }
            return
        }
        do {
            try deviceManager.setDefaultDevice(uid: device.uid, kind: device.kind)
            devices = devices.map { $0.kind == device.kind ? copyDevice($0, isDefault: $0.uid == device.uid) : $0 }
            refreshAfterDelay()
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func setSystemOutputVolume(_ volume: Double) {
        guard let output = currentOutput else { return }
        setDeviceVolume(output, volume: volume)
    }

    public func setInputVolume(_ volume: Double) {
        guard let input = currentInput else { return }
        setDeviceVolume(input, volume: volume)
    }

    public func setDeviceVolume(_ device: AudioDevice, volume: Double) {
        let clamped = volume.clampedUnit.snappedToPercentStep
        devices = devices.map { $0.id == device.id ? copyDevice($0, volume: clamped) : $0 }
        if settings.demoMode {
            return
        }
        guard device.canSetVolume else {
            lastError = AudioRouterError.unsupportedControl("\(device.kind.title) volume").localizedDescription
            return
        }
        let taskKey = device.id
        pendingVolumeTasks[taskKey]?.cancel()
        let now = Date()
        let elapsed = now.timeIntervalSince(lastDeviceVolumeCommitDates[taskKey] ?? .distantPast)
        if elapsed >= deviceVolumeCommitInterval {
            lastDeviceVolumeCommitDates[taskKey] = now
            commitDeviceVolume(device, volume: clamped)
            return
        }

        let delay = max(0.01, deviceVolumeCommitInterval - elapsed)
        pendingVolumeTasks[taskKey] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                self?.lastDeviceVolumeCommitDates[taskKey] = Date()
                self?.commitDeviceVolume(device, volume: clamped)
                self?.pendingVolumeTasks.removeValue(forKey: taskKey)
            }
        }
    }

    public func setDeviceMuted(_ device: AudioDevice, isMuted: Bool) {
        devices = devices.map { $0.id == device.id ? copyDevice($0, isMuted: isMuted) : $0 }
        if settings.demoMode {
            return
        }
        do {
            try volumeManager.setMuted(device: device, isMuted: isMuted)
            refreshAfterDelay()
        } catch {
            lastError = error.localizedDescription
            refreshAfterDelay(interval: 0.1)
        }
    }

    public func setDeviceBalance(_ device: AudioDevice, balance: Double) {
        let clamped = balance.clampedBalance
        devices = devices.map { $0.id == device.id ? copyDevice($0, balance: clamped) : $0 }
        if settings.demoMode {
            return
        }
        guard device.canSetBalance else {
            lastError = AudioRouterError.unsupportedControl("\(device.kind.title) balance").localizedDescription
            return
        }
        let taskKey = device.id
        pendingBalanceTasks[taskKey]?.cancel()
        pendingBalanceTasks[taskKey] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                self?.commitDeviceBalance(device, balance: clamped)
                self?.pendingBalanceTasks.removeValue(forKey: taskKey)
            }
        }
    }

    private func commitDeviceVolume(_ device: AudioDevice, volume: Double) {
        do {
            if device.kind == .output {
                try volumeManager.setOutputVolume(device: device, volume: volume)
            } else {
                try volumeManager.setInputVolume(device: device, volume: volume)
            }
            refreshAfterDelay(interval: 0.45)
        } catch {
            lastError = error.localizedDescription
            refreshAfterDelay(interval: 0.1)
        }
    }

    private func commitDeviceBalance(_ device: AudioDevice, balance: Double) {
        do {
            try volumeManager.setBalance(device: device, balance: balance)
            refreshAfterDelay(interval: 0.45)
        } catch {
            lastError = error.localizedDescription
            refreshAfterDelay(interval: 0.1)
        }
    }

    public func toggleSystemMute() {
        guard let output = currentOutput else { return }
        setDeviceMuted(output, isMuted: !(output.isMuted ?? false))
    }

    public func changeSystemVolume(by delta: Double) {
        guard let output = currentOutput else { return }
        setDeviceVolume(output, volume: (output.volume ?? 0.5) + delta)
    }

    public func selectOutputDevice(_ device: AudioDevice) {
        guard device.kind == .output else { return }
        selectedOutputDeviceID = device.uid
    }

    public func changeSelectedVolume(by delta: Double) {
        ensureSelectedOutputDeviceStillExists()
        if let output = selectedOutputDevice {
            guard output.canSetVolume else {
                showUnsupportedNote("\(output.name) does not expose software volume control.")
                return
            }
            setDeviceVolume(output, volume: (output.volume ?? 0.5) + delta)
            return
        }
        changeSelectedSourceVolume(by: delta)
    }

    public func changeSelectedSourceVolume(by delta: Double) {
        ensureSelectedSourceStillExists()
        guard let source = selectedSource else {
            showUnsupportedNote("Select an app route before changing track volume.")
            return
        }
        guard supportsPerAppVolume else {
            showUnsupportedNote("Per-app gain requires a live audio route or supported routing backend.")
            return
        }
        setSourceVolume(source: source, volume: source.volume + delta)
    }

    public var selectedSourceVolumeCommandTitle: String {
        guard let selectedSource else { return "Selected Track" }
        return selectedSource.appName
    }

    public var selectedVolumeCommandTitle: String {
        if let output = selectedOutputDevice {
            return output.name
        }
        return selectedSourceVolumeCommandTitle
    }

    public func switchToNextOutputDevice() {
        switchOutputDevice(offset: 1)
    }

    public func switchToPreviousOutputDevice() {
        switchOutputDevice(offset: -1)
    }

    private func switchOutputDevice(offset: Int) {
        let outputs = outputDevices
        guard outputs.count > 1 else { return }
        let currentIndex = outputs.firstIndex { $0.uid == currentOutput?.uid } ?? 0
        let nextIndex = (currentIndex + offset + outputs.count) % outputs.count
        setDefaultDevice(outputs[nextIndex])
    }

    public func route(for source: AudioSource) -> AudioRoute {
        audioRoutingManager.route(for: source.id)
    }

    public func routeOutputName(for source: AudioSource) -> String {
        let route = route(for: source)
        if let outputDeviceID = route.outputDeviceID,
           let group = outputGroups.first(where: { $0.routeTargetID == outputDeviceID }) {
            return group.name
        }
        if let outputDeviceID = route.outputDeviceID,
           AirPlayRouteCandidate.isRouteTargetID(outputDeviceID) {
            return airPlayRouteCandidate(forRouteTargetID: outputDeviceID)?.name ?? "AirPlay Route"
        }
        return audioRoutingManager.deviceName(for: route, outputs: outputDevices)
    }

    public func airPlayRouteCandidate(forRouteTargetID routeTargetID: String) -> AirPlayRouteCandidate? {
        if let exact = airPlayRouteCandidates.first(where: { $0.routeTargetID == routeTargetID }) {
            return exact
        }
        guard let targetKey = AirPlayRouteCandidate.normalizedTargetKey(forRouteTargetID: routeTargetID) else {
            return nil
        }
        return airPlayRouteCandidates.first {
            AirPlayRouteCandidate.normalizedKey(for: $0.name) == targetKey
        }
    }

    public func isAirPlayRouteCandidateTarget(_ routeTargetID: String) -> Bool {
        AirPlayRouteCandidate.isRouteTargetID(routeTargetID)
    }

    public var routeAppDisplayNames: [String] {
        configuredSourceSpecs.map(\.displayName)
    }

    public var hasHiddenDefaultRouteApps: Bool {
        !hiddenDefaultSourceIDs.isEmpty
    }

    public func isUserAddedRouteApp(_ source: AudioSource) -> Bool {
        userSourceSpecs.contains { $0.bundleIdentifier == source.id }
    }

    public func isDefaultRouteApp(_ source: AudioSource) -> Bool {
        Self.defaultSourceSpecs.contains { $0.bundleIdentifier == source.id }
    }

    public func canMoveRouteApp(_ source: AudioSource, offset: Int) -> Bool {
        let ids = configuredSourceSpecs.map(\.bundleIdentifier)
        guard let index = ids.firstIndex(of: source.id) else { return false }
        return ids.indices.contains(index + offset)
    }

    public func moveRouteApp(_ source: AudioSource, offset: Int) {
        var ids = configuredSourceSpecs.map(\.bundleIdentifier)
        guard let currentIndex = ids.firstIndex(of: source.id) else { return }
        let nextIndex = currentIndex + offset
        guard ids.indices.contains(nextIndex), currentIndex != nextIndex else { return }
        let movedID = ids.remove(at: currentIndex)
        ids.insert(movedID, at: nextIndex)
        sourceOrderIDs = ids
        saveSourceOrderIDs()
        selectedSourceID = source.id
        refresh(silent: true)
    }

    @discardableResult
    public func reorderRouteApp(draggedSourceID: String, targetSourceID: String) -> Bool {
        var ids = configuredSourceSpecs.map(\.bundleIdentifier)
        guard draggedSourceID != targetSourceID,
              let currentIndex = ids.firstIndex(of: draggedSourceID),
              let originalTargetIndex = ids.firstIndex(of: targetSourceID) else {
            return false
        }

        let movedID = ids.remove(at: currentIndex)
        guard let targetIndex = ids.firstIndex(of: targetSourceID) else { return false }
        let insertionIndex = currentIndex < originalTargetIndex ? targetIndex + 1 : targetIndex
        ids.insert(movedID, at: min(insertionIndex, ids.count))
        sourceOrderIDs = ids
        saveSourceOrderIDs()
        selectedSourceID = draggedSourceID
        refresh(silent: true)
        return true
    }

    public func resetRouteAppOrder() {
        sourceOrderIDs = Self.defaultSourceSpecs.map(\.bundleIdentifier) + userSourceSpecs.map(\.bundleIdentifier)
        saveSourceOrderIDs()
        refresh(silent: true)
    }

    public func refreshAppCandidates() {
        updateAvailableAppCandidates()
    }

    public func addRouteApp(source: AudioSource) {
        guard let bundleIdentifier = source.bundleIdentifier, !bundleIdentifier.isEmpty else {
            showUnsupportedNote("That app does not expose a stable bundle identifier, so AudioRouter cannot save it as a route source.")
            return
        }
        addRouteAppSpec(
            FocusedSourceSpec(
                displayName: source.appName,
                bundleIdentifier: bundleIdentifier,
                matchName: source.appName,
                iconPath: resolvedAppIconPath(bundleIdentifier: bundleIdentifier, fallbackPath: source.icon)
            )
        )
    }

    public func addRouteApp(bundleURL: URL) {
        guard bundleURL.pathExtension == "app",
              let bundle = Bundle(url: bundleURL),
              let bundleIdentifier = bundle.bundleIdentifier,
              !bundleIdentifier.isEmpty else {
            showUnsupportedNote("Choose a valid macOS .app bundle with a bundle identifier.")
            return
        }

        let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? bundleURL.deletingPathExtension().lastPathComponent

        addRouteAppSpec(
            FocusedSourceSpec(
                displayName: displayName,
                bundleIdentifier: bundleIdentifier,
                matchName: displayName,
                iconPath: bundleURL.path
            )
        )
    }

    public func removeRouteApp(_ source: AudioSource) {
        if isDefaultRouteApp(source) {
            hiddenDefaultSourceIDs.insert(source.id)
            userSourceSpecs.removeAll { $0.bundleIdentifier == source.id }
            saveHiddenDefaultSourceIDs()
            saveUserSourceSpecs()
        } else if isUserAddedRouteApp(source) {
            userSourceSpecs.removeAll { $0.bundleIdentifier == source.id }
            sourceOrderIDs.removeAll { $0 == source.id }
            saveUserSourceSpecs()
            saveSourceOrderIDs()
        } else {
            return
        }
        audioRoutingManager.resetSourceToSystemOutput(sourceID: source.id)
        if selectedSourceID == source.id {
            selectedSourceID = audioSources.first { $0.id != source.id }?.id
        }
        audioSources.removeAll { $0.id == source.id }
        meterState.removeSource(source.id)
        refresh(silent: true)
    }

    public func restoreDefaultRouteApps() {
        guard !hiddenDefaultSourceIDs.isEmpty else { return }
        hiddenDefaultSourceIDs.removeAll()
        saveHiddenDefaultSourceIDs()
        ensureSourceOrderContains(Self.defaultSourceSpecs.map(\.bundleIdentifier))
        refresh(silent: true)
    }

    public func setSourceVolume(source: AudioSource, volume: Double) {
        selectedSourceID = source.id
        let clamped = max(0, min(1.5, volume)).snappedToPercentStep
        audioRoutingManager.setSourceVolume(sourceID: source.id, volume: clamped, persist: false)
        updateAudioSource(source.id) { current in
            current.volume = clamped
        }
        scheduleSourceVolumeCommit(sourceID: source.id, volume: clamped)
        if let warning = audioRoutingManager.lastWarning {
            showUnsupportedNote(warning)
        }
    }

    public func toggleSolo(source: AudioSource) {
        selectedSourceID = source.id
        soloSourceID = soloSourceID == source.id ? nil : source.id
    }

    public func setSourceMuted(source: AudioSource, isMuted: Bool) {
        selectedSourceID = source.id
        audioRoutingManager.muteSource(sourceID: source.id, muted: isMuted)
        updateAudioSource(source.id) { current in
            current.isMuted = isMuted
        }
        if let warning = audioRoutingManager.lastWarning {
            showUnsupportedNote(warning)
        }
    }

    public func assignSourceOutput(source: AudioSource, uid: String?) {
        selectedSourceID = source.id
        autoRetriedRouteSignatures.remove(routeSignature(sourceID: source.id, outputDeviceID: uid))
        if uid == nil {
            pendingRoutePreparationTasks[source.id]?.cancel()
            pendingRoutePreparationTasks.removeValue(forKey: source.id)
        }
        if let uid {
            if let group = outputGroups.first(where: { $0.routeTargetID == uid }) {
                audioRoutingManager.assignOutputGroup(
                    sourceID: source.id,
                    groupID: uid,
                    outputDevices: outputDevices(for: group)
                )
            } else {
                audioRoutingManager.assignOutputDevice(sourceID: source.id, deviceID: uid)
            }
        } else {
            audioRoutingManager.resetSourceToSystemOutput(sourceID: source.id)
        }
        let route = audioRoutingManager.route(for: source.id)
        updateAudioSource(source.id) { current in
            current.assignedOutputDeviceID = route.outputDeviceID
            current.routeMode = route.routeMode
            current.followsSystemOutput = route.routeMode == .followSystemOutput
        }
        configureMeterTimer()
        if let warning = audioRoutingManager.lastWarning {
            showUnsupportedNote(warning)
        }
    }

    public func prepareAndAssignSourceOutput(source: AudioSource, uid: String?) {
        selectedSourceID = source.id
        pendingRoutePreparationTasks[source.id]?.cancel()
        pendingRoutePreparationTasks.removeValue(forKey: source.id)
        guard let uid else {
            assignSourceOutput(source: source, uid: nil)
            return
        }

        if AirPlayRouteCandidate.isRouteTargetID(uid) {
            if let output = Self.airPlayOutputDevice(forRouteTargetID: uid, outputs: outputDevices) {
                prepareAndAssignSourceOutput(source: source, uid: output.uid)
                return
            }
            assignAirPlayCandidateRoute(source: source, routeTargetID: uid)
            return
        }

        preparingRouteSourceIDs.insert(source.id)
        let probeResult = processAudioMonitor.probeSystemAudioPermission()
        processTapProbeMessage = probeResult.message
        unsupportedNote = routePreparationMessage(
            for: source.appName,
            probeResult: probeResult
        )

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.preparingRouteSourceIDs.remove(source.id)
            }

            self.refresh(silent: true)
            let refreshedSource = self.audioSources.first { $0.id == source.id } ?? source
            self.assignSourceOutput(source: refreshedSource, uid: uid)

            let route = self.route(for: refreshedSource)
            if route.status == .active {
                self.unsupportedNote = nil
            } else if route.status == .savedOnly, refreshedSource.audioObjectID == nil {
                self.unsupportedNote = "Route saved. AudioRouter already asked macOS for System Audio Recording permission and will retry automatically when \(refreshedSource.appName) exposes audio."
                self.schedulePreparedRouteRetries(sourceID: refreshedSource.id, outputID: uid)
            } else if let warning = self.audioRoutingManager.lastWarning {
                self.unsupportedNote = "\(warning) AudioRouter already asked macOS for System Audio Recording permission."
                self.schedulePreparedRouteRetries(sourceID: refreshedSource.id, outputID: uid)
            }
        }
    }

    private func assignAirPlayCandidateRoute(source: AudioSource, routeTargetID: String) {
        assignSourceOutput(source: source, uid: routeTargetID)
        let candidateName = airPlayRouteCandidate(forRouteTargetID: routeTargetID)?.name ?? "that AirPlay device"
        showUnsupportedNote("AudioRouter found \(candidateName) through AirPlay discovery, but macOS has not exposed it as a Core Audio output device yet. Press AirPlay, choose \(candidateName) in macOS, then refresh AudioRouter. Live routing can start only after macOS exposes a real output device.")
    }

    nonisolated public static func airPlayOutputDevice(
        forRouteTargetID routeTargetID: String,
        outputs: [AudioDevice]
    ) -> AudioDevice? {
        guard let targetKey = AirPlayRouteCandidate.normalizedTargetKey(forRouteTargetID: routeTargetID) else {
            return nil
        }
        return outputs.first {
            $0.kind == .output
                && $0.isAlive
                && AirPlayRouteCandidate.normalizedKey(for: $0.name) == targetKey
        }
    }

    private func reconcileAirPlayRoutes(using sources: inout [AudioSource]) {
        for index in sources.indices {
            let source = sources[index]
            let route = audioRoutingManager.route(for: source.id)
            guard route.routeMode == .customOutput,
                  let routeTargetID = route.outputDeviceID,
                  AirPlayRouteCandidate.isRouteTargetID(routeTargetID),
                  let output = Self.airPlayOutputDevice(
                    forRouteTargetID: routeTargetID,
                    outputs: outputDevices
                  ) else {
                continue
            }

            audioRoutingManager.assignOutputDevice(sourceID: source.id, deviceID: output.uid)
            let updatedRoute = audioRoutingManager.route(for: source.id)
            sources[index].assignedOutputDeviceID = updatedRoute.outputDeviceID
            sources[index].routeMode = updatedRoute.routeMode
            sources[index].followsSystemOutput = updatedRoute.routeMode == .followSystemOutput

            if updatedRoute.status == .active {
                unsupportedNote = nil
            } else {
                unsupportedNote = "\(output.name) is now available to Core Audio. AudioRouter prepared the saved route and will start it automatically when \(source.appName) exposes audio."
            }
        }
    }

    public func resetSourceToSystemOutput(_ source: AudioSource) {
        assignSourceOutput(source: source, uid: nil)
    }

    public func isPreparingRoute(for source: AudioSource) -> Bool {
        preparingRouteSourceIDs.contains(source.id)
    }

    public func retrySourceRoute(_ source: AudioSource) {
        selectedSourceID = source.id
        if let outputID = route(for: source).outputDeviceID {
            autoRetriedRouteSignatures.remove(routeSignature(sourceID: source.id, outputDeviceID: outputID))
        }
        if let outputID = route(for: source).outputDeviceID,
           let group = outputGroups.first(where: { $0.routeTargetID == outputID }) {
            audioRoutingManager.retryOutputGroup(sourceID: source.id, outputDevices: outputDevices(for: group))
        } else {
            audioRoutingManager.retryRoute(sourceID: source.id)
        }
        let route = audioRoutingManager.route(for: source.id)
        updateAudioSource(source.id) { current in
            current.assignedOutputDeviceID = route.outputDeviceID
            current.routeMode = route.routeMode
            current.followsSystemOutput = route.routeMode == .followSystemOutput
        }
        configureMeterTimer()
        if let warning = audioRoutingManager.lastWarning {
            showUnsupportedNote(warning)
        }
    }

    public func toggleSelectedSourceMute() {
        guard let selectedSourceID,
              let source = audioSources.first(where: { $0.id == selectedSourceID }) else {
            showUnsupportedNote("Select an app source in Dashboard or Mixer before using Mute Selected App.")
            return
        }
        setSourceMuted(source: source, isMuted: !source.isMuted)
    }

    public func applyPreset(at index: Int) {
        guard presetManager.presets.indices.contains(index) else {
            showUnsupportedNote("No saved setup exists in slot \(index + 1).")
            return
        }
        applyPreset(presetManager.presets[index])
    }

    public func probeProcessTapPermission() {
        var result = processAudioMonitor.probeSystemAudioPermission()
        if case .unavailable = result.status {
            result = processAudioMonitor.probeFirstAvailableProcessTap(from: audioSources)
        }
        processTapProbeMessage = result.message
        switch result.status {
        case .tapCreated:
            showUnsupportedNote("System Audio Recording permission is available. Choose an output to start or save a route.")
        case let .permissionDenied(message), let .unavailable(message):
            showUnsupportedNote(message)
        }
    }

    public func createOutputGroup() {
        let deviceUIDs = outputDevices.map(\.uid)
        let volumes = Dictionary(uniqueKeysWithValues: deviceUIDs.map { uid in
            (uid, outputDevices.first(where: { $0.uid == uid })?.volume ?? 1)
        })
        outputGroups.insert(
            OutputDeviceGroup(
                name: "Group Play \(outputGroups.count + 1)",
                deviceUIDs: deviceUIDs,
                perDeviceVolumes: volumes
            ),
            at: 0
        )
    }

    public func renameOutputGroup(_ group: OutputDeviceGroup, to name: String) {
        updateOutputGroup(group.id) { current in
            current.name = name.isEmpty ? current.name : name
        }
    }

    public func deleteOutputGroup(_ group: OutputDeviceGroup) {
        outputGroups.removeAll { $0.id == group.id }
        for source in audioSources where route(for: source).outputDeviceID == group.routeTargetID {
            resetSourceToSystemOutput(source)
        }
    }

    public func outputDevices(for group: OutputDeviceGroup) -> [AudioDevice] {
        group.deviceUIDs.compactMap { uid in
            outputDevices.first { $0.uid == uid && $0.isAlive }
        }
    }

    public func setOutputGroup(_ group: OutputDeviceGroup, includes device: AudioDevice, included: Bool) {
        updateOutputGroup(group.id) { current in
            if included {
                if !current.deviceUIDs.contains(device.uid) {
                    current.deviceUIDs.append(device.uid)
                }
                current.perDeviceVolumes[device.uid] = device.volume ?? current.perDeviceVolumes[device.uid] ?? 1
            } else {
                current.deviceUIDs.removeAll { $0 == device.uid }
                current.perDeviceVolumes.removeValue(forKey: device.uid)
            }
        }
        retryRoutesUsingGroup(group)
    }

    public func setOutputGroupVolume(_ group: OutputDeviceGroup, deviceUID: String, volume: Double) {
        let adjustedVolume = volume.clampedUnit.snappedToPercentStep
        updateOutputGroup(group.id) { current in
            current.perDeviceVolumes[deviceUID] = adjustedVolume
        }
        if let device = outputDevices.first(where: { $0.uid == deviceUID }), device.canSetVolume {
            setDeviceVolume(device, volume: adjustedVolume)
        }
    }

    public func retryRoutesUsingGroup(_ group: OutputDeviceGroup) {
        let currentGroup = outputGroups.first { $0.id == group.id } ?? group
        let groupOutputs = outputDevices(for: currentGroup)
        for source in audioSources where route(for: source).outputDeviceID == currentGroup.routeTargetID {
            audioRoutingManager.retryOutputGroup(sourceID: source.id, outputDevices: groupOutputs)
        }
        configureMeterTimer()
    }

    public func testOutput(_ device: AudioDevice) {
        selectedOutputDeviceID = device.uid
        do {
            try outputTestToneService.playTestTone(deviceUID: device.uid)
            showUnsupportedNote("Playing a test tone on \(device.name).")
        } catch {
            showUnsupportedNote("Could not play a test tone on \(device.name): \(error.localizedDescription)")
        }
    }

    public func testOutputGroup(_ group: OutputDeviceGroup) {
        let outputs = outputDevices(for: group)
        guard !outputs.isEmpty else {
            showUnsupportedNote("\(group.name) has no connected speakers to test.")
            return
        }

        for (index, device) in outputs.enumerated() {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Double(index) * 0.18 * 1_000_000_000))
                self?.testOutput(device)
            }
        }
        showUnsupportedNote("Testing \(outputs.count) speaker\(outputs.count == 1 ? "" : "s") in \(group.name).")
    }

    public func testRoute(for source: AudioSource) {
        selectedSourceID = source.id
        let route = route(for: source)
        if route.routeMode == .followSystemOutput {
            if let output = currentOutput {
                testOutput(output)
            } else {
                showUnsupportedNote("No system output is available for \(source.appName).")
            }
            return
        }

        guard let outputID = route.outputDeviceID else {
            showUnsupportedNote("\(source.appName) does not have an assigned output to test.")
            return
        }

        if let group = outputGroups.first(where: { $0.routeTargetID == outputID }) {
            testOutputGroup(group)
        } else if let output = outputDevices.first(where: { $0.uid == outputID }) {
            testOutput(output)
        } else if AirPlayRouteCandidate.isRouteTargetID(outputID) {
            let candidateName = airPlayRouteCandidate(forRouteTargetID: outputID)?.name ?? "that AirPlay route"
            showUnsupportedNote("Use the AirPlay button to choose \(candidateName) in macOS first. AudioRouter can test it after macOS exposes it as a Core Audio output.")
        } else {
            showUnsupportedNote("\(source.appName)'s assigned output is missing.")
        }
    }

    public func routedSources(to device: AudioDevice) -> [AudioSource] {
        audioSources.filter { source in
            let route = route(for: source)
            if route.routeMode != .customOutput {
                return false
            }
            if route.outputDeviceID == device.uid {
                return true
            }
            return outputGroups
                .first(where: { $0.routeTargetID == route.outputDeviceID })?
                .deviceUIDs
                .contains(device.uid) == true
        }
    }

    public func routeStatus(for source: AudioSource) -> String {
        let route = route(for: source)
        if settings.demoMode {
            return route.routeMode == .followSystemOutput ? "Demo" : "Simulated"
        }
        if route.routeMode == .followSystemOutput {
            return "Working"
        }
        if let outputID = route.outputDeviceID,
           AirPlayRouteCandidate.isRouteTargetID(outputID) {
            return "AirPlay"
        }
        switch route.status {
        case .active:
            return supportsTruePerAppRouting ? "Live" : "Working"
        case .savedOnly:
            return "Saved Only"
        case .simulated:
            return "Simulated"
        case .requiresBackend:
            return "Requires Audio Backend"
        case .deviceMissing:
            return "Device Missing"
        }
    }

    public func sourceAudioQuality(for source: AudioSource) -> SourceAudioQuality? {
        if settings.demoMode {
            return demoAudioQuality(for: source)
        }
        return audioRoutingManager.sourceAudioQuality(for: source.id)
    }

    public func sourceAudioQualityHelp(
        for source: AudioSource,
        quality: SourceAudioQuality
    ) -> String {
        let mode = settings.demoMode ? "Demo sample rate" : "Live Core Audio sample rate"
        return "\(source.appName) \(mode.lowercased()): \(quality.accessibilityDescription)."
    }

    public var routeSummaryText: String {
        if settings.demoMode {
            return "Demo routes are simulated for UI testing"
        }
        if activeLiveRouteCount > 0 {
            return activeLiveRouteCount == 1
                ? "1 route is live"
                : "\(activeLiveRouteCount) routes are live"
        }
        if savedCustomRouteCount > 0 {
            return savedCustomRouteCount == 1
                ? "1 saved route is waiting to retry"
                : "\(savedCustomRouteCount) saved routes are waiting to retry"
        }
        return "No custom app routes are active"
    }

    public func routeDiagnostic(for source: AudioSource) -> String? {
        guard !settings.demoMode else {
            return "Demo route only."
        }

        if let preciseFailure = routeFailureReason(for: source) {
            return preciseFailure
        }

        let route = route(for: source)
        guard route.routeMode == .customOutput else {
            return source.audioObjectID == nil
                ? "Start playback to make this source routeable."
                : nil
        }

        switch route.status {
        case .active:
            return nil
        case .savedOnly:
            return "Saved route. AudioRouter asked for permission and will retry automatically when it sees this app's audio process."
        case .simulated:
            return "Simulated route. Switch to Live Mode to use Core Audio."
        case .requiresBackend:
            if !audioRoutingManager.supportsTruePerAppRouting {
                return "This macOS version cannot use Core Audio process taps."
            }
            if source.audioObjectID == nil {
                return "AudioRouter asked for permission and will retry when \(source.appName)'s Core Audio process appears."
            }
            return audioRoutingManager.lastWarning ?? "The public process-tap route could not start for this app/device."
        case .deviceMissing:
            return "The assigned output is disconnected."
        }
    }

    public func routeFailureReason(for source: AudioSource) -> String? {
        guard !settings.demoMode else { return nil }
        let route = route(for: source)
        if route.routeMode == .followSystemOutput {
            return source.audioObjectID == nil ? "App is configured, but AudioRouter has not seen playable audio from it yet." : nil
        }
        if let message = audioRoutingManager.routeMessage(for: source.id),
           route.status != .active {
            return message
        }
        if let outputID = route.outputDeviceID,
           let group = outputGroups.first(where: { $0.routeTargetID == outputID }),
           outputDevices(for: group).isEmpty {
            return "Output group has no connected devices selected."
        }
        if route.outputDeviceID == nil {
            return "No output is selected for this custom route."
        }
        if let outputID = route.outputDeviceID,
           outputDevices.first(where: { $0.uid == outputID }) == nil {
            return "Assigned output is missing or disconnected."
        }
        if !audioRoutingManager.supportsTruePerAppRouting {
            return "This macOS/backend cannot start a live process-tap route."
        }
        if source.audioObjectID == nil {
            return "AudioRouter cannot see \(source.appName)'s Core Audio process yet; it will retry automatically after the process appears."
        }
        if !source.isProducingAudio && route.status != .active {
            return "\(source.appName) is not producing audio right now."
        }
        return nil
    }

    public func routeHealthItems(for source: AudioSource) -> [RouteHealthItem] {
        let route = route(for: source)
        let outputName = routeOutputName(for: source)
        let outputExists = route.routeMode == .followSystemOutput
            || route.outputDeviceID.flatMap { outputID in
                outputDevices.first { $0.uid == outputID }?.uid
                    ?? outputGroups.first { $0.routeTargetID == outputID }?.routeTargetID
            } != nil

        return [
            RouteHealthItem(
                id: "configured",
                title: "App configured",
                detail: source.bundleIdentifier ?? source.id,
                state: .working
            ),
            RouteHealthItem(
                id: "running",
                title: "App running",
                detail: source.isRunning ? "Process \(source.processID)" : "Open the app to route it",
                state: source.isRunning ? .working : .savedOnly
            ),
            RouteHealthItem(
                id: "audio-object",
                title: "Audio detected",
                detail: source.audioObjectID == nil ? "Waiting for Core Audio process" : "Core Audio process object available",
                state: source.audioObjectID == nil ? .savedOnly : .working
            ),
            RouteHealthItem(
                id: "playback",
                title: "Playback activity",
                detail: source.isProducingAudio ? "Audio is active" : "No live audio level yet",
                state: source.isProducingAudio ? .live : .savedOnly
            ),
            RouteHealthItem(
                id: "output",
                title: "Assigned output",
                detail: outputName,
                state: outputExists ? .working : .deviceMissing
            ),
            RouteHealthItem(
                id: "backend",
                title: "Routing backend",
                detail: audioRoutingManager.supportsTruePerAppRouting ? "Process taps available" : "Requires routing backend",
                state: audioRoutingManager.supportsTruePerAppRouting ? .ready : .requiresBackend
            ),
            RouteHealthItem(
                id: "route",
                title: "Route status",
                detail: routeStatus(for: source),
                state: routeHealthState(for: source)
            )
        ]
    }

    private func routeHealthState(for source: AudioSource) -> BackendReadinessState {
        switch routeStatus(for: source) {
        case "Live": return .live
        case "Working": return .working
        case "AirPlay": return .savedOnly
        case "Saved Only": return .savedOnly
        case "Simulated": return .demo
        case "Requires Audio Backend": return .requiresBackend
        case "Device Missing": return .deviceMissing
        default: return .ready
        }
    }

    public func routeStatusIsWarning(for source: AudioSource) -> Bool {
        ["AirPlay", "Requires Audio Backend", "Unsupported", "Device Missing"].contains(routeStatus(for: source))
    }

    public var activeUserProfile: UserProfile {
        userProfileManager.activeProfile
    }

    @discardableResult
    public func addUserProfile(named name: String) -> UserProfile {
        userProfileManager.addProfile(named: name)
    }

    public func selectUserProfile(_ profile: UserProfile) {
        userProfileManager.selectProfile(profile)
    }

    public func renameUserProfile(_ profile: UserProfile, to name: String) {
        userProfileManager.rename(profile, to: name)
    }

    public func deleteUserProfile(_ profile: UserProfile) {
        userProfileManager.delete(profile)
    }

    public func saveCurrentSetup(named name: String? = nil) {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let presetName = trimmedName.isEmpty ? "Setup \(presetManager.presets.count + 1)" : trimmedName
        presetManager.savePreset(currentSetupPreset(name: presetName))
    }

    public func saveSuggestedSetup(_ kind: SuggestedSetupKind) {
        var preset = currentSetupPreset(name: kind.rawValue)
        switch kind {
        case .deskSpeakers:
            let builtInOutput = outputDevices.first { $0.transport == .builtIn } ?? currentOutput
            preset.outputDeviceUID = builtInOutput?.uid
            preset.systemVolume = builtInOutput?.volume ?? 0.72
            preset.eqPreset = .flat
        case .airPodsCall:
            let bluetoothOutput = outputDevices.first { $0.name.localizedCaseInsensitiveContains("airpods") }
                ?? outputDevices.first { $0.transport == .bluetoothLE || $0.transport == .bluetooth }
                ?? currentOutput
            preset.outputDeviceUID = bluetoothOutput?.uid
            preset.inputDeviceUID = currentInput?.uid
            preset.systemVolume = bluetoothOutput?.volume ?? 0.64
            preset.eqPreset = .podcast
        case .musicToBluetooth:
            let bluetoothOutput = outputDevices.first { $0.transport == .bluetooth || $0.transport == .bluetoothLE } ?? currentOutput
            preset.outputDeviceUID = bluetoothOutput?.uid
            preset.eqPreset = .music
            if let bluetoothUID = bluetoothOutput?.uid {
                for source in audioSources where source.appName.localizedCaseInsensitiveContains("music")
                    || source.appName.localizedCaseInsensitiveContains("spotify") {
                    preset.appOutputAssignments[source.id] = bluetoothUID
                }
            }
        case .focusMode:
            preset.systemMuted = currentOutput?.isMuted ?? false
            preset.eqPreset = .podcast
            preset.mutedApps = Dictionary(uniqueKeysWithValues: audioSources.map { ($0.id, true) })
        }
        presetManager.savePreset(preset)
    }

    private func currentSetupPreset(name: String) -> AudioPreset {
        AudioPreset(
            name: name,
            outputDeviceUID: currentOutput?.uid,
            inputDeviceUID: currentInput?.uid,
            systemVolume: currentOutput?.volume,
            inputVolume: currentInput?.volume,
            systemMuted: currentOutput?.isMuted ?? false,
            appVolumes: Dictionary(uniqueKeysWithValues: audioSources.map { ($0.id, $0.volume) }),
            mutedApps: Dictionary(uniqueKeysWithValues: audioSources.map { ($0.id, $0.isMuted) }),
            appOutputAssignments: Dictionary(uniqueKeysWithValues: audioSources.compactMap { source in
                source.assignedOutputDeviceID.map { (source.id, $0) }
            }),
            eqPreset: eqManager.state.selectedPreset
        )
    }

    public func applyPreset(_ preset: AudioPreset) {
        if let outputUID = preset.outputDeviceUID,
           let output = outputDevices.first(where: { $0.uid == outputUID }) {
            setDefaultDevice(output)
        }
        if let inputUID = preset.inputDeviceUID,
           let input = inputDevices.first(where: { $0.uid == inputUID }) {
            setDefaultDevice(input)
        }
        if let volume = preset.systemVolume {
            setSystemOutputVolume(volume)
        }
        if let inputVolume = preset.inputVolume {
            setInputVolume(inputVolume)
        }
        if let output = currentOutput {
            setDeviceMuted(output, isMuted: preset.systemMuted)
        }
        eqManager.applyPreset(preset.eqPreset)
        audioSources = audioSources.map { source in
            var updated = source
            if let volume = preset.appVolumes[source.id] {
                updated.volume = volume
                audioRoutingManager.setSourceVolume(sourceID: source.id, volume: volume)
            }
            if let muted = preset.mutedApps[source.id] {
                updated.isMuted = muted
                audioRoutingManager.muteSource(sourceID: source.id, muted: muted)
            }
            if let outputID = preset.appOutputAssignments[source.id] {
                updated.assignedOutputDeviceID = outputID
                updated.followsSystemOutput = false
                updated.routeMode = .customOutput
                audioRoutingManager.assignOutputDevice(sourceID: source.id, deviceID: outputID)
            } else {
                updated.assignedOutputDeviceID = nil
                updated.followsSystemOutput = true
                updated.routeMode = .followSystemOutput
                audioRoutingManager.resetSourceToSystemOutput(sourceID: source.id)
            }
            return updated
        }
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try settings.setLaunchAtLogin(enabled)
        } catch {
            lastError = "Launch at Login could not be changed: \(error.localizedDescription)"
        }
    }

    public func resetAllSettings() {
        settings.reset()
        eqManager.applyPreset(.flat)
        shortcutManager.reset()
        presetManager.reset()
        userSourceSpecs.removeAll()
        hiddenDefaultSourceIDs.removeAll()
        sourceOrderIDs = Self.defaultSourceSpecs.map(\.bundleIdentifier)
        saveUserSourceSpecs()
        saveHiddenDefaultSourceIDs()
        saveSourceOrderIDs()
        audioSources = audioSources.map {
            var source = $0
            source.volume = 1
            source.isMuted = false
            source.assignedOutputDeviceID = nil
            source.followsSystemOutput = true
            source.routeMode = .followSystemOutput
            audioRoutingManager.resetSourceToSystemOutput(sourceID: source.id)
            return source
        }
        outputGroups.removeAll()
        autoRetriedRouteSignatures.removeAll()
    }

    public func showUnsupportedNote(_ note: String) {
        guard settings.showUnsupportedNotes else { return }
        unsupportedNote = note
    }

    public func dismissUnsupportedNote() {
        unsupportedNote = nil
    }

    func statusStyle(for source: AudioSource) -> RouteVisualStatus {
        switch routeStatus(for: source) {
        case "Live": return .live
        case "Demo": return .demo
        case "Simulated": return .simulated
        case "AirPlay": return .savedOnly
        case "Saved Only": return .savedOnly
        case "Requires Audio Backend": return .requiresBackend
        case "Device Missing": return .deviceMissing
        case "Unsupported": return .unsupported
        default: return .working
        }
    }

    public var debugDeviceList: String {
        devices
            .map { "\($0.kind.title): \($0.name) [\($0.uid)] \($0.typeDescription) default=\($0.isDefault) volume=\($0.volume.map { String(format: "%.2f", $0) } ?? "n/a")" }
            .joined(separator: "\n")
    }

    private func updateAudioSource(_ id: String, transform: (inout AudioSource) -> Void) {
        if let index = audioSources.firstIndex(where: { $0.id == id }) {
            transform(&audioSources[index])
        }
    }

    private var selectedSource: AudioSource? {
        guard let selectedSourceID else { return nil }
        return audioSources.first { $0.id == selectedSourceID }
    }

    private var selectedOutputDevice: AudioDevice? {
        guard let selectedOutputDeviceID else { return nil }
        return outputDevices.first { $0.uid == selectedOutputDeviceID }
    }

    private func ensureSelectedSourceStillExists() {
        if let selectedOutputDeviceID,
           outputDevices.contains(where: { $0.uid == selectedOutputDeviceID }) {
            return
        }
        if let selectedSourceID,
           audioSources.contains(where: { $0.id == selectedSourceID }) {
            return
        }
        selectedSourceID = audioSources.first?.id
    }

    private func ensureSelectedOutputDeviceStillExists() {
        guard let selectedOutputDeviceID else { return }
        if outputDevices.contains(where: { $0.uid == selectedOutputDeviceID }) {
            return
        }
        self.selectedOutputDeviceID = nil
    }

    private func scheduleSourceVolumeCommit(sourceID: String, volume: Double) {
        pendingSourceVolumes[sourceID] = volume
        pendingSourceVolumeTasks[sourceID]?.cancel()
        pendingSourceVolumeTasks[sourceID] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                self?.audioRoutingManager.setSourceVolume(sourceID: sourceID, volume: volume, persist: true)
                self?.pendingSourceVolumes.removeValue(forKey: sourceID)
                self?.pendingSourceVolumeTasks.removeValue(forKey: sourceID)
            }
        }
    }

    private func routePreparationMessage(
        for appName: String,
        probeResult: ProcessTapProbeResult
    ) -> String {
        switch probeResult.status {
        case .tapCreated:
            return "System Audio Recording permission is ready. AudioRouter is refreshing devices, finding \(appName), and starting the route."
        case .permissionDenied(_):
            return "\(probeResult.message) AudioRouter saved the output choice and will retry after permission is granted."
        case .unavailable(_):
            return "Preparing \(appName). \(probeResult.message)"
        }
    }

    private func schedulePreparedRouteRetries(sourceID: String, outputID: String) {
        pendingRoutePreparationTasks[sourceID]?.cancel()
        pendingRoutePreparationTasks[sourceID] = Task { @MainActor [weak self] in
            guard let self else { return }
            let retryDelays: [UInt64] = [
                700_000_000,
                1_600_000_000,
                3_200_000_000,
                6_000_000_000,
                10_000_000_000
            ]

            for delay in retryDelays {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }

                let currentRoute = audioRoutingManager.route(for: sourceID)
                guard currentRoute.routeMode == .customOutput,
                      currentRoute.outputDeviceID == outputID else {
                    break
                }
                guard currentRoute.status != .active else {
                    break
                }

                refresh(silent: true)
                if let refreshedSource = audioSources.first(where: { $0.id == sourceID }) {
                    retrySourceRoute(refreshedSource)
                    if audioRoutingManager.route(for: sourceID).status == .active {
                        break
                    }
                }
            }

            pendingRoutePreparationTasks.removeValue(forKey: sourceID)
        }
    }

    private func updateOutputGroup(_ id: UUID, transform: (inout OutputDeviceGroup) -> Void) {
        guard let index = outputGroups.firstIndex(where: { $0.id == id }) else { return }
        transform(&outputGroups[index])
    }

    private func startDeviceObservationIfNeeded() {
        guard !settings.demoMode, deviceObservation == nil else { return }
        deviceObservation = deviceManager.observeDeviceChanges { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleObservedDeviceChange()
            }
        }
    }

    private func handleObservedDeviceChange() {
        noteDeviceTopologyIsSettling()
        schedulePlaybackKeepAliveAfterDeviceChange()
        guard settings.protectPlaybackDuringDeviceChanges else {
            refresh(silent: true)
            refreshAfterDelay(interval: 1.8)
            return
        }
        scheduleProtectedDeviceRefresh()
    }

    private func scheduleProtectedDeviceRefresh() {
        pendingDeviceRefreshTask?.cancel()
        pendingDeviceRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(protectedDeviceRefreshDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            refresh(silent: true)

            try? await Task.sleep(nanoseconds: UInt64(protectedDeviceRefreshFollowUpDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            refresh(silent: true)
            pendingDeviceRefreshTask = nil
        }
    }

    private func schedulePlaybackKeepAliveAfterDeviceChange() {
        guard !settings.demoMode,
              settings.keepMediaPlayingDuringDeviceChanges else {
            return
        }

        let sourceSnapshot = audioSources
        pendingPlaybackKeepAliveTask?.cancel()
        pendingPlaybackKeepAliveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for delay in playbackKeepAliveAttemptDelays {
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                guard !Task.isCancelled,
                      settings.keepMediaPlayingDuringDeviceChanges else {
                    return
                }
                playbackKeepAliveService.keepPlaying(
                    sources: Self.mergedSourceSnapshot(sourceSnapshot, with: audioSources)
                )
            }
            pendingPlaybackKeepAliveTask = nil
        }
    }

    private func startMediaKeepAliveWatchdogIfNeeded() {
        guard mediaKeepAliveWatchdogTask == nil else { return }

        mediaKeepAliveWatchdogTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.mediaKeepAliveWatchdogInterval else { return }
                self?.runMediaKeepAliveWatchdogTick()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    private func startImmediatePlaybackObserversIfNeeded() {
        playbackKeepAliveService.startImmediatePlaybackObservers(
            sourcesProvider: { [weak self] in
                self?.audioSources ?? []
            },
            isEnabled: { [weak self] in
                guard let self else { return false }
                return !self.settings.demoMode && self.settings.keepMediaPlayingDuringDeviceChanges
            }
        )
    }

    private func runMediaKeepAliveWatchdogTick() {
        guard !settings.demoMode,
              settings.keepMediaPlayingDuringDeviceChanges else {
            return
        }
        playbackKeepAliveService.keepPlaying(sources: audioSources)
    }

    private func scheduleDeviceMissingCheck(for uid: String) {
        pendingDeviceDisconnectTasks[uid]?.cancel()
        pendingDeviceDisconnectTasks[uid] = Task { @MainActor [weak self] in
            guard let self else { return }
            let graceInterval = settings.protectPlaybackDuringDeviceChanges
                ? protectedDeviceDisconnectGraceInterval
                : deviceDisconnectGraceInterval
            try? await Task.sleep(nanoseconds: UInt64(graceInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if !Self.aliveOutputUIDs(from: devices).contains(uid) {
                audioRoutingManager.handleDeviceDisconnected(deviceID: uid)
                if let warning = audioRoutingManager.lastWarning {
                    showUnsupportedNote(warning)
                }
            } else {
                audioRoutingManager.handleDeviceReconnected(deviceID: uid)
            }
            pendingDeviceDisconnectTasks.removeValue(forKey: uid)
        }
    }

    private func noteDeviceTopologyIsSettling() {
        guard !settings.demoMode else { return }
        let nextSettledAt = Date().addingTimeInterval(deviceChangeRouteRetrySuppressionInterval)
        if let current = deviceTopologySettlingUntil, current > nextSettledAt {
            return
        }
        deviceTopologySettlingUntil = nextSettledAt
    }

    private var isDeviceTopologySettling: Bool {
        guard let settledAt = deviceTopologySettlingUntil else { return false }
        if settledAt > Date() {
            return true
        }
        deviceTopologySettlingUntil = nil
        return false
    }

    private static func aliveOutputUIDs(from devices: [AudioDevice]) -> Set<String> {
        Set(devices.filter { $0.kind == .output && $0.isAlive }.map(\.uid))
    }

    private static func mergedSourceSnapshot(_ snapshot: [AudioSource], with currentSources: [AudioSource]) -> [AudioSource] {
        var merged = snapshot
        var seenIDs = Set(snapshot.map(\.id))
        for source in currentSources where seenIDs.insert(source.id).inserted {
            merged.append(source)
        }
        return merged
    }

    private func saveOutputGroups() {
        guard let data = try? JSONEncoder().encode(outputGroups) else { return }
        try? data.write(to: outputGroupsURL, options: .atomic)
    }

    private func addRouteAppSpec(_ spec: FocusedSourceSpec) {
        let normalized = spec.normalized
        guard !configuredSourceSpecs.contains(where: { $0.bundleIdentifier == normalized.bundleIdentifier }) else {
            selectedSourceID = normalized.bundleIdentifier
            showUnsupportedNote("\(normalized.displayName) is already in the routing dashboard.")
            return
        }

        if Self.defaultSourceSpecs.contains(where: { $0.bundleIdentifier == normalized.bundleIdentifier }) {
            hiddenDefaultSourceIDs.remove(normalized.bundleIdentifier)
            saveHiddenDefaultSourceIDs()
            ensureSourceOrderContains([normalized.bundleIdentifier])
            selectedSourceID = normalized.bundleIdentifier
            refresh(silent: true)
            return
        }

        userSourceSpecs.append(normalized)
        ensureSourceOrderContains([normalized.bundleIdentifier])
        saveUserSourceSpecs()
        selectedSourceID = normalized.bundleIdentifier
        refresh(silent: true)
    }

    private func updateAvailableAppCandidates() {
        let configuredIDs = Set(configuredSourceSpecs.map(\.bundleIdentifier))
        let candidates = processAudioMonitor.listRunningApps()
            .filter { source in
                guard let bundleIdentifier = source.bundleIdentifier else { return false }
                return !configuredIDs.contains(bundleIdentifier)
            }
            .uniquedBySourceBundle()
            .sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }

        if candidates != availableAppCandidates {
            availableAppCandidates = candidates
        }
    }

    private func saveUserSourceSpecs() {
        guard let data = try? JSONEncoder().encode(userSourceSpecs) else { return }
        try? data.write(to: appSourcesURL, options: .atomic)
    }

    private func saveHiddenDefaultSourceIDs() {
        let ids = Array(hiddenDefaultSourceIDs).sorted()
        guard let data = try? JSONEncoder().encode(ids) else { return }
        try? data.write(to: hiddenDefaultSourcesURL, options: .atomic)
    }

    private func saveSourceOrderIDs() {
        let validIDs = Set((Self.defaultSourceSpecs + userSourceSpecs).map(\.bundleIdentifier))
        let orderedIDs = sourceOrderIDs.filter { validIDs.contains($0) }
        guard let data = try? JSONEncoder().encode(orderedIDs) else { return }
        try? data.write(to: sourceOrderURL, options: .atomic)
    }

    private func ensureSourceOrderContains(_ ids: [String]) {
        var changed = false
        if sourceOrderIDs.isEmpty {
            sourceOrderIDs = Self.defaultSourceSpecs.map(\.bundleIdentifier) + userSourceSpecs.map(\.bundleIdentifier)
            changed = true
        }
        for id in ids where !sourceOrderIDs.contains(id) {
            sourceOrderIDs.append(id)
            changed = true
        }
        if changed {
            saveSourceOrderIDs()
        }
    }

    private static func loadUserSourceSpecs(from url: URL) -> [FocusedSourceSpec] {
        guard let data = try? Data(contentsOf: url),
              let specs = try? JSONDecoder().decode([FocusedSourceSpec].self, from: data) else {
            return []
        }
        let defaultIDs = Set(defaultSourceSpecs.map(\.bundleIdentifier))
        var seen = Set<String>()
        return specs.compactMap { spec in
            let normalized = spec.normalized
            guard !defaultIDs.contains(normalized.bundleIdentifier),
                  seen.insert(normalized.bundleIdentifier).inserted else {
                return nil
            }
            return normalized
        }
    }

    private static func loadHiddenDefaultSourceIDs(from url: URL) -> Set<String> {
        guard let data = try? Data(contentsOf: url),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        let defaultIDs = Set(defaultSourceSpecs.map(\.bundleIdentifier))
        return Set(ids.filter { defaultIDs.contains($0) })
    }

    private static func loadSourceOrderIDs(from url: URL) -> [String] {
        guard let data = try? Data(contentsOf: url),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    private func configureMeterTimer() {
        let shouldAnimate = settings.demoMode || liveMeteringAvailable
        if shouldAnimate {
            guard meterTimer == nil else { return }
            meterTimer = Timer.scheduledTimer(withTimeInterval: meterInterval, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.tickMeters()
                }
            }
            meterTimer?.tolerance = 0.025
        } else {
            meterTimer?.invalidate()
            meterTimer = nil
            clearMetersIfNeeded()
        }
    }

    private func clearMetersIfNeeded() {
        let current = meterState.snapshot
        guard current.systemOutputMeter != 0
            || current.inputMeter != 0
            || current.sourceMeters.values.contains(where: { $0 != 0 })
            || current.deviceMeters.values.contains(where: { $0 != 0 }) else {
            return
        }
        meterState.update(
            systemOutput: 0,
            input: 0,
            sources: Dictionary(uniqueKeysWithValues: audioSources.map { ($0.id, 0) }),
            devices: Dictionary(uniqueKeysWithValues: devices.map { ($0.id, 0) })
        )
    }

    private func tickMeters() {
        if !settings.demoMode {
            tickLiveMeters()
            return
        }
        meterPhase += 0.19
        let nextInputMeter = abs(sin(meterPhase * 0.51 + 1.1)) * 0.65
        let nextSourceMeters = Dictionary(uniqueKeysWithValues: audioSources.map { source in
            let seed = Double(abs(source.id.hashValue % 100)) / 31.0
            let activeBoost = source.isProducingAudio ? 0.35 : 0.10
            let level = source.isMuted ? 0 : min(1, abs(sin(meterPhase + seed)) * 0.55 + activeBoost)
            return (source.id, level)
        })
        let systemSourceIDs = systemRoutedSourceIDs()
        let nextSystemOutputMeter = maxMeterLevel(for: systemSourceIDs, using: nextSourceMeters)
        let nextDeviceMeters = Dictionary(uniqueKeysWithValues: devices.map { device in
            let routed = routedSources(to: device)
            let customRouteLevel = averageMeterLevel(for: routed.map(\.id), using: nextSourceMeters)
            let systemRouteLevel = device.isDefault ? nextSystemOutputMeter : 0
            let idleLevel = routed.isEmpty && !device.isDefault ? 0.14 : 0
            let base = min(1, max(systemRouteLevel, customRouteLevel == 0 ? idleLevel : customRouteLevel + 0.12))
            return (device.id, device.kind == .input ? nextInputMeter : base)
        })
        publishMeters(
            systemOutput: nextSystemOutputMeter,
            input: nextInputMeter,
            sources: nextSourceMeters,
            devices: nextDeviceMeters
        )
    }

    private func tickLiveMeters() {
        let nextSourceMeters = Dictionary(uniqueKeysWithValues: audioSources.map { source in
            let level = audioRoutingManager.currentLevel(for: source.id) ?? source.currentLevel ?? 0
            return (source.id, level)
        })
        let systemSourceIDs = systemRoutedSourceIDs()
        let nextSystemOutputMeter = maxMeterLevel(for: systemSourceIDs, using: nextSourceMeters)
        let nextDeviceMeters = Dictionary(uniqueKeysWithValues: devices.map { device in
            let routed = routedSources(to: device)
            let customRouteLevel = averageMeterLevel(for: routed.map(\.id), using: nextSourceMeters)
            let systemRouteLevel = device.isDefault ? nextSystemOutputMeter : 0
            let level = max(systemRouteLevel, customRouteLevel)
            return (device.id, device.kind == .input ? 0 : level)
        })
        publishMeters(
            systemOutput: nextSystemOutputMeter,
            input: 0,
            sources: nextSourceMeters,
            devices: nextDeviceMeters
        )
    }

    private func publishMeters(
        systemOutput: Double,
        input: Double,
        sources: [String: Double],
        devices: [String: Double]
    ) {
        let current = meterState.snapshot
        let smoothedSystemOutput = smoothedMeterValue(from: current.systemOutputMeter, to: systemOutput)
        let smoothedInput = smoothedMeterValue(from: current.inputMeter, to: input)
        let smoothedSources = smoothedMeterDictionary(from: current.sourceMeters, to: sources)
        let smoothedDevices = smoothedMeterDictionary(from: current.deviceMeters, to: devices)

        let nextSystemOutput = shouldPublishMeterValue(current.systemOutputMeter, smoothedSystemOutput)
            ? smoothedSystemOutput
            : current.systemOutputMeter
        let nextInput = shouldPublishMeterValue(current.inputMeter, smoothedInput)
            ? smoothedInput
            : current.inputMeter
        let nextSources = shouldPublishMeterDictionary(current.sourceMeters, smoothedSources)
            ? smoothedSources
            : current.sourceMeters
        let nextDevices = shouldPublishMeterDictionary(current.deviceMeters, smoothedDevices)
            ? smoothedDevices
            : current.deviceMeters

        meterState.update(
            systemOutput: nextSystemOutput,
            input: nextInput,
            sources: nextSources,
            devices: nextDevices
        )
    }

    private func smoothedMeterValue(from oldValue: Double, to newValue: Double) -> Double {
        if oldValue == 0 || newValue == 0 {
            return newValue
        }
        let blend = newValue > oldValue ? 0.72 : 0.42
        return oldValue + (newValue - oldValue) * blend
    }

    private func smoothedMeterDictionary(from oldValue: [String: Double], to newValue: [String: Double]) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: newValue.map { entry in
            (entry.key, smoothedMeterValue(from: oldValue[entry.key] ?? 0, to: entry.value))
        })
    }

    private func shouldPublishMeterValue(_ oldValue: Double, _ newValue: Double) -> Bool {
        abs(oldValue - newValue) >= meterPublishThreshold
            || (oldValue != 0 && newValue == 0)
            || (oldValue == 0 && newValue != 0)
    }

    private func shouldPublishMeterDictionary(_ oldValue: [String: Double], _ newValue: [String: Double]) -> Bool {
        guard Set(oldValue.keys) == Set(newValue.keys) else { return true }
        return newValue.contains { entry in
            shouldPublishMeterValue(oldValue[entry.key] ?? 0, entry.value)
        }
    }

    private func systemRoutedSourceIDs() -> [String] {
        audioSources
            .filter { route(for: $0).routeMode == .followSystemOutput }
            .map(\.id)
    }

    private func maxMeterLevel(for sourceIDs: [String], using sourceMeters: [String: Double]) -> Double {
        sourceIDs.map { sourceMeters[$0] ?? 0 }.max() ?? 0
    }

    private func averageMeterLevel(for sourceIDs: [String], using sourceMeters: [String: Double]) -> Double {
        guard !sourceIDs.isEmpty else { return 0 }
        return min(1, sourceIDs.map { sourceMeters[$0] ?? 0 }.reduce(0, +) / Double(sourceIDs.count))
    }

    private func focusedSources(from detectedSources: [AudioSource]) -> [AudioSource] {
        configuredSourceSpecs.map { spec in
            let detectedSource = bestDetectedSource(for: spec, in: detectedSources)

            let route = audioRoutingManager.route(for: spec.bundleIdentifier)
            return AudioSource(
                id: spec.bundleIdentifier,
                appName: spec.displayName,
                bundleIdentifier: spec.bundleIdentifier,
                processID: detectedSource?.processID ?? 0,
                audioObjectID: detectedSource?.audioObjectID,
                icon: focusedIconPath(for: spec, detectedSource: detectedSource),
                isRunning: detectedSource?.isRunning ?? false,
                isProducingAudio: detectedSource?.isProducingAudio ?? false,
                lastActiveTime: detectedSource?.lastActiveTime ?? .distantPast,
                currentLevel: detectedSource?.currentLevel,
                volume: route.volume,
                isMuted: route.isMuted,
                routeMode: route.routeMode,
                assignedOutputDeviceID: route.outputDeviceID,
                followsSystemOutput: route.routeMode == .followSystemOutput
            )
        }
    }

    private func bestDetectedSource(for spec: FocusedSourceSpec, in sources: [AudioSource]) -> AudioSource? {
        sources
            .map { source in (source, detectedSourceScore(source, for: spec)) }
            .filter { $0.1 > 0 }
            .max { lhs, rhs in lhs.1 < rhs.1 }?
            .0
    }

    private func detectedSourceScore(_ source: AudioSource, for spec: FocusedSourceSpec) -> Int {
        var score = 0
        let bundleIdentifier = source.bundleIdentifier ?? ""
        if bundleIdentifier == spec.bundleIdentifier || source.id == spec.bundleIdentifier {
            score += 1_000
        } else if bundleIdentifier.hasPrefix("\(spec.bundleIdentifier).") || source.id.hasPrefix("\(spec.bundleIdentifier).") {
            score += 850
        } else if source.appName.localizedCaseInsensitiveContains(spec.matchName)
                    || bundleIdentifier.localizedCaseInsensitiveContains(spec.matchName)
                    || source.id.localizedCaseInsensitiveContains(spec.matchName) {
            score += 500
        }
        guard score > 0 else {
            return 0
        }
        if source.audioObjectID != nil {
            score += 120
        }
        if source.isProducingAudio {
            score += 80
        }
        if source.isRunning {
            score += 10
        }
        return score
    }

    private func retryReadySavedRoutes(using sources: [AudioSource]) {
        guard !settings.demoMode,
              audioRoutingManager.supportsTruePerAppRouting,
              !isDeviceTopologySettling else {
            return
        }

        for source in sources {
            let route = audioRoutingManager.route(for: source.id)
            guard route.routeMode == .customOutput,
                  route.status != .active,
                  let outputID = route.outputDeviceID,
                  source.audioObjectID != nil,
                  source.isProducingAudio || (source.currentLevel ?? 0) > 0.015 else {
                continue
            }
            let group = outputGroups.first { $0.routeTargetID == outputID }
            let outputIsReady = group.map { !outputDevices(for: $0).isEmpty }
                ?? outputDevices.contains { $0.uid == outputID }
            guard outputIsReady else { continue }

            let signature = routeSignature(sourceID: source.id, outputDeviceID: outputID)
            guard autoRetriedRouteSignatures.insert(signature).inserted else { continue }

            if let group {
                audioRoutingManager.retryOutputGroup(sourceID: source.id, outputDevices: outputDevices(for: group))
            } else {
                audioRoutingManager.retryRoute(sourceID: source.id)
            }
            let updatedRoute = audioRoutingManager.route(for: source.id)
            updateAudioSource(source.id) { current in
                current.assignedOutputDeviceID = updatedRoute.outputDeviceID
                current.routeMode = updatedRoute.routeMode
                current.followsSystemOutput = updatedRoute.routeMode == .followSystemOutput
            }
        }
    }

    private func syncAppInputDevices(using sources: [AudioSource]) {
        let shouldPublish = !settings.demoMode && settings.publishAppInputsAsSystemDevices
        appInputPublisher.sync(sources: sources, enabled: shouldPublish)
        let nextDevices = appInputPublisher.publishedDevices
        if nextDevices != publishedAppInputDevices {
            publishedAppInputDevices = nextDevices
        }
        if let message = appInputPublisher.lastMessage,
           !message.isEmpty,
           !message.contains("published") {
            processTapProbeMessage = message
        }
    }

    private func routeSignature(sourceID: String, outputDeviceID: String?) -> String {
        "\(sourceID)|\(outputDeviceID ?? "system")"
    }

    private var demoDevices: [AudioDevice] {
        [
            AudioDevice(audioObjectID: 10, uid: "demo-macbook", name: "MacBook Speakers", kind: .output, channelCount: 2, transport: .builtIn, isDefault: true, isAlive: true, volume: 0.72, balance: 0, sampleRate: 48000, availableSampleRateRanges: [AudioSampleRateRange(minimum: 44100, maximum: 96000)], canSetVolume: true, canSetMute: true, canSetBalance: true),
            AudioDevice(audioObjectID: 11, uid: "demo-bluetooth", name: "Bluetooth Speaker", kind: .output, channelCount: 2, transport: .bluetooth, isDefault: false, isAlive: true, volume: 0.82, balance: -0.08, sampleRate: 44100, availableSampleRateRanges: [AudioSampleRateRange(minimum: 44100, maximum: 48000)], canSetVolume: true, canSetMute: true, canSetBalance: false),
            AudioDevice(audioObjectID: 12, uid: "demo-airpods", name: "AirPods", kind: .output, channelCount: 2, transport: .bluetoothLE, isDefault: false, isAlive: true, volume: 0.64, balance: 0.04, sampleRate: 48000, availableSampleRateRanges: [AudioSampleRateRange(minimum: 48000, maximum: 48000)], canSetVolume: true, canSetMute: true, canSetBalance: true),
            AudioDevice(audioObjectID: 16, uid: "demo-mic", name: "MacBook Microphone", kind: .input, channelCount: 1, transport: .builtIn, isDefault: true, isAlive: true, volume: 0.66, sampleRate: 48000, availableSampleRateRanges: [AudioSampleRateRange(minimum: 44100, maximum: 96000)], canSetVolume: true, canSetMute: false, canSetBalance: false)
        ]
    }

    private var demoSources: [AudioSource] {
        configuredSourceSpecs.map { spec in
            let route = audioRoutingManager.route(for: spec.bundleIdentifier)
            return AudioSource(
                id: spec.bundleIdentifier,
                appName: spec.displayName,
                bundleIdentifier: spec.bundleIdentifier,
                processID: Int32(abs(spec.bundleIdentifier.hashValue % 9000) + 100),
                icon: focusedIconPath(for: spec, detectedSource: nil),
                isProducingAudio: true,
                lastActiveTime: Date().addingTimeInterval(-3),
                currentLevel: 0.7,
                volume: route.volume,
                isMuted: route.isMuted,
                routeMode: route.routeMode,
                assignedOutputDeviceID: route.outputDeviceID,
                followsSystemOutput: route.routeMode == .followSystemOutput
            )
        }
    }

    private func demoAudioQuality(for source: AudioSource) -> SourceAudioQuality {
        let loweredID = source.id.lowercased()
        if loweredID.contains("spotify") {
            return SourceAudioQuality(sampleRate: 44_100, bitDepth: 32, channelCount: 2, isFloatPCM: true)
        }
        if loweredID.contains("music") {
            return SourceAudioQuality(sampleRate: 48_000, bitDepth: 32, channelCount: 2, isFloatPCM: true)
        }
        if loweredID.contains("chrome") {
            return SourceAudioQuality(sampleRate: 48_000, bitDepth: 32, channelCount: 2, isFloatPCM: true)
        }
        return SourceAudioQuality(sampleRate: 48_000, bitDepth: 32, channelCount: 2, isFloatPCM: true)
    }

    private var configuredSourceSpecs: [FocusedSourceSpec] {
        var seen = Set<String>()
        let visibleDefaults = Self.defaultSourceSpecs.filter { !hiddenDefaultSourceIDs.contains($0.bundleIdentifier) }
        let specs: [FocusedSourceSpec] = (visibleDefaults + userSourceSpecs).compactMap { spec in
            let normalized = spec.normalized
            guard seen.insert(normalized.bundleIdentifier).inserted else { return nil }
            return normalized
        }
        let order = Dictionary(uniqueKeysWithValues: sourceOrderIDs.enumerated().map { ($0.element, $0.offset) })
        return specs.enumerated().sorted { left, right in
            let leftOrder = order[left.element.bundleIdentifier] ?? Int.max
            let rightOrder = order[right.element.bundleIdentifier] ?? Int.max
            if leftOrder != rightOrder {
                return leftOrder < rightOrder
            }
            return left.offset < right.offset
        }.map { $0.element }
    }

    private struct FocusedSourceSpec: Codable, Hashable {
        let displayName: String
        let bundleIdentifier: String
        let matchName: String
        let iconPath: String?

        var normalized: FocusedSourceSpec {
            FocusedSourceSpec(
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? bundleIdentifier
                    : displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                bundleIdentifier: bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
                matchName: matchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? displayName
                    : matchName.trimmingCharacters(in: .whitespacesAndNewlines),
                iconPath: iconPath
            )
        }
    }

    private static let defaultSourceSpecs: [FocusedSourceSpec] = [
        FocusedSourceSpec(displayName: "Spotify", bundleIdentifier: "com.spotify.client", matchName: "spotify", iconPath: "/Applications/Spotify.app"),
        FocusedSourceSpec(displayName: "Apple Music", bundleIdentifier: "com.apple.Music", matchName: "music", iconPath: "/System/Applications/Music.app"),
        FocusedSourceSpec(displayName: "Chrome", bundleIdentifier: "com.google.Chrome", matchName: "chrome", iconPath: "/Applications/Google Chrome.app")
    ]

    private func focusedIconPath(for spec: FocusedSourceSpec, detectedSource: AudioSource?) -> String? {
        resolvedAppIconPath(bundleIdentifier: spec.bundleIdentifier, fallbackPath: detectedSource?.icon)
            ?? resolvedAppIconPath(bundleIdentifier: spec.bundleIdentifier, fallbackPath: spec.iconPath)
            ?? detectedSource?.icon
            ?? spec.iconPath
    }

    private func resolvedAppIconPath(bundleIdentifier: String?, fallbackPath: String?) -> String? {
        AppIconResolver.applicationPath(bundleIdentifier: bundleIdentifier, fallbackPath: fallbackPath)
            ?? fallbackPath
    }

    private func refreshAfterDelay(interval: TimeInterval = 0.35) {
        pendingRefreshTask?.cancel()
        pendingRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.refresh(silent: true)
            self?.pendingRefreshTask = nil
        }
    }

    private func copyDevice(
        _ device: AudioDevice,
        isDefault: Bool? = nil,
        volume: Double? = nil,
        isMuted: Bool? = nil,
        balance: Double? = nil
    ) -> AudioDevice {
        AudioDevice(
            audioObjectID: device.audioObjectID,
            uid: device.uid,
            name: device.name,
            kind: device.kind,
            channelCount: device.channelCount,
            transport: device.transport,
            isDefault: isDefault ?? device.isDefault,
            isAlive: device.isAlive,
            volume: volume ?? device.volume,
            isMuted: isMuted ?? device.isMuted,
            balance: balance ?? device.balance,
            sampleRate: device.sampleRate,
            availableSampleRateRanges: device.availableSampleRateRanges,
            canSetVolume: device.canSetVolume,
            canSetMute: device.canSetMute,
            canSetBalance: device.canSetBalance
        )
    }
}

public enum SettingsSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case devices = "Devices"
    case eq = "EQ"
    case setups = "Setups"
    case shortcuts = "Shortcuts"
    case settings = "Settings"
    case advanced = "Advanced"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .dashboard: return "point.3.connected.trianglepath.dotted"
        case .devices: return "speaker.wave.2"
        case .eq: return "waveform"
        case .setups: return "square.stack.3d.up"
        case .shortcuts: return "keyboard"
        case .settings: return "gearshape"
        case .advanced: return "wrench.and.screwdriver"
        }
    }
}

private extension Array where Element == AudioDevice {
    func uniquedByUID() -> [AudioDevice] {
        var seen: Set<String> = []
        return filter { device in
            seen.insert(device.uid).inserted
        }
    }
}

private extension Array where Element == AudioSource {
    func uniquedBySourceBundle() -> [AudioSource] {
        var seen: Set<String> = []
        return filter { source in
            guard let bundleIdentifier = source.bundleIdentifier else { return false }
            return seen.insert(bundleIdentifier).inserted
        }
    }
}
