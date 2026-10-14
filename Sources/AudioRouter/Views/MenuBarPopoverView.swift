import AppKit
import SwiftUI

public struct MenuBarPopoverView: View {
    @ObservedObject private var store: AudioRouterStore
    private let showMainWindow: () -> Void
    @State private var section: MenuBarSection = .apps
    @State private var selectedSourceID = ""
    @State private var setupName = ""
    @State private var savedSetupName: String?
    @State private var isPresented = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    public init(store: AudioRouterStore, showMainWindow: @escaping () -> Void) {
        self.store = store
        self.showMainWindow = showMainWindow
    }

    public var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 18).padding(.vertical, 16)
            navigation
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    notices
                    switch section {
                    case .apps: appControls
                    case .outputs: outputControls
                    case .setups: setupControls
                    case .eq: equalizerControls
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            systemControls.padding(.horizontal, 18).padding(.vertical, 12)
            footer.padding(.horizontal, 18).padding(.bottom, 12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(accent)
        .preferredColorScheme(store.settings.effectiveColorScheme)
        .controlSize(.small)
        .opacity(isPresented ? 1 : 0)
        .onAppear {
            synchronizeSource()
            selectVolumeTarget()
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) { isPresented = true }
        }
        .onDisappear { isPresented = false }
        .onChange(of: store.audioSources.map(\.id)) { _, _ in synchronizeSource() }
        .onChange(of: store.selectedSourceID) { _, id in
            if let id, store.audioSources.contains(where: { $0.id == id }) { selectedSourceID = id }
        }
        .onChange(of: selectedSourceID) { _, _ in
            if section == .apps { selectVolumeTarget() }
        }
        .onChange(of: section) { _, _ in selectVolumeTarget() }
        .onChange(of: store.activeUserProfile.id) { _, _ in savedSetupName = nil }
    }

    private var navigation: some View {
        HStack(spacing: 4) {
            ForEach(MenuBarSection.allCases) { item in
                Button { section = item } label: {
                    VStack(spacing: 7) {
                        HStack(spacing: 6) {
                            Image(systemName: item.systemImage).font(.system(size: 12, weight: .medium))
                            Text(item.rawValue).font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(section == item ? accent : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(section == item ? accent : .clear)
                            .frame(height: 2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.rawValue)
                .accessibilityAddTraits(section == item ? .isSelected : [])
            }
        }
        .padding(.horizontal, 18)
    }

    private var header: some View {
        HStack(spacing: 10) {
            AudioRouterLogo(size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("AudioRouter").font(.system(size: 16, weight: .semibold))
                HStack(spacing: 5) {
                    Circle().fill(store.activeLiveRouteCount > 0 ? accent : Color.secondary.opacity(0.5))
                        .frame(width: 5, height: 5)
                    Text(store.settings.demoMode ? "Demo Mode" : "\(store.activeLiveRouteCount) live route\(store.activeLiveRouteCount == 1 ? "" : "s")")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            Menu {
                ForEach(store.userProfileManager.profiles) { profile in
                    Button { store.selectUserProfile(profile) } label: {
                        if profile.id == store.activeUserProfile.id {
                            Label(profile.displayName, systemImage: "checkmark")
                        } else { Text(profile.displayName) }
                    }
                }
                Divider()
                Button("Manage Profiles...") { open(.setups) }
            } label: {
                Text(store.activeUserProfile.displayName)
                    .font(.caption.weight(.semibold)).lineLimit(1)
                    .frame(maxWidth: 150, alignment: .trailing)
            }
            .menuStyle(.borderlessButton)
            .foregroundStyle(.primary)
            .tint(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .help("Switch profile")
            .accessibilityLabel("Profile: \(store.activeUserProfile.displayName)")
            Menu {
                Button("Refresh Apps and Devices", systemImage: "arrow.clockwise") { store.refresh() }
                Button("Add App...", systemImage: "app.badge.plus") { open(.dashboard) }
                Divider()
                Button("Shortcuts...", systemImage: "keyboard") { open(.shortcuts) }
                Button("Settings...", systemImage: "gearshape") { open(.settings) }
                Button("Reliability and Diagnostics...", systemImage: "wrench.and.screwdriver") { open(.advanced) }
                Divider()
                Button("Check for Updates...", systemImage: "arrow.down.circle") { store.checkForUpdates() }
                    .disabled(store.updateManager.isChecking)
                Button("Quit AudioRouter", systemImage: "power") { NSApp.terminate(nil) }
            } label: { Image(systemName: "ellipsis").frame(width: 28, height: 28) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .foregroundStyle(.secondary)
            .help("More AudioRouter controls").accessibilityLabel("More AudioRouter controls")
        }
    }

    private var systemControls: some View {
        VStack(spacing: 8) {
            HStack {
                Label("System", systemImage: "speaker.wave.2").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Menu {
                    ForEach(store.outputDevices) { device in
                        Button { store.setDefaultDevice(device) } label: {
                            if device.isDefault { Label(device.name, systemImage: "checkmark") }
                            else { Text(device.name) }
                        }
                    }
                } label: {
                    Text(store.currentOutput?.name ?? "No output connected")
                        .font(.caption.weight(.medium)).lineLimit(1)
                }
                .menuStyle(.borderlessButton).fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.primary)
                .tint(.primary)
                .disabled(store.outputDevices.isEmpty)
                .help("Change the system output for apps following macOS")
            }
            HStack(spacing: 8) {
                iconButton(store.currentOutput?.isMuted == true ? "speaker.slash.fill" : "speaker.wave.2.fill",
                           label: store.currentOutput?.isMuted == true ? "Unmute system output" : "Mute system output",
                           enabled: store.currentOutput?.canSetMute == true) { store.toggleSystemMute() }
                volumeControl(store.currentOutput?.volume, enabled: store.currentOutput?.canSetVolume == true,
                              label: "System output volume", action: store.setSystemOutputVolume)
            }
        }
    }

    @ViewBuilder private var notices: some View {
        if !store.settings.hasCompletedOnboarding {
            Button {
                open(.dashboard)
                store.showOnboarding()
            } label: { Label("Finish setup", systemImage: "checklist") }
                .buttonStyle(MenuBarControlStyle())
        }
        if let error = store.lastError {
            SupportNote(note: error) { store.dismissUnsupportedNote() }
        }
        if let update = store.updateManager.availableUpdate {
            HStack {
                Label("Version \(update.version) available", systemImage: "arrow.down.circle")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button("View") { open(.settings) }.buttonStyle(MenuBarControlStyle())
            }
        }
    }

    private var appControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let source = selectedSource {
                selectedAppControls(source)
                sectionHeading("Apps", detail: "\(store.audioSources.count) configured", destination: .dashboard)
                LazyVStack(spacing: 1) {
                    ForEach(store.audioSources) { source in appRow(source) }
                }
            } else {
                emptyState("No apps configured", symbol: "app.dashed")
                Button("Add App...") { open(.dashboard) }.buttonStyle(MenuBarControlStyle(prominent: true))
            }
        }
    }

    private func appRow(_ source: AudioSource) -> some View {
        Button {
            selectedSourceID = source.id
            store.selectedSourceID = source.id
        } label: {
            HStack(spacing: 10) {
                AppSourceIcon(source: source).frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(source.appName).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(store.routeOutputName(for: source)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                MenuBarLevelMeter(meterState: store.meterState, target: .source(source.id))
                    .frame(width: 70, height: 20)
                Text(source.volume.roundedPercentDescription).font(.caption.monospacedDigit())
                    .frame(width: 38, alignment: .trailing)
                Image(systemName: selectedSourceID == source.id ? "checkmark" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(selectedSourceID == source.id ? accent : Color.secondary.opacity(0.5))
                    .frame(width: 14)
            }
            .padding(10)
            .background(selectedSourceID == source.id ? accent.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Select \(source.appName), output \(store.routeOutputName(for: source))")
        .accessibilityAddTraits(selectedSourceID == source.id ? .isSelected : [])
    }

    private func selectedAppControls(_ source: AudioSource) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AppSourceIcon(source: source).frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(source.appName).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    if let quality = store.sourceAudioQuality(for: source) {
                        Text(quality.compactDisplayLabel).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                if store.isPreparingRoute(for: source) {
                    ProgressView("Routing").controlSize(.small).font(.caption)
                } else if source.followsSystemOutput {
                    Text("System").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 4).background(inset, in: RoundedRectangle(cornerRadius: 5))
                } else {
                    StatusLabel(text: store.routeStatus(for: source), status: store.statusStyle(for: source))
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "arrow.turn.down.right").foregroundStyle(.secondary)
                Picker("Output for \(source.appName)", selection: Binding(
                    get: { store.route(for: source).outputDeviceID ?? "" },
                    set: { store.prepareAndAssignSourceOutput(source: source, uid: $0.isEmpty ? nil : $0) }
                )) {
                    Text("Follow System Output").tag("")
                    ForEach(store.outputDevices) { Text($0.name).tag($0.uid) }
                    ForEach(store.outputGroups) { Text($0.name).tag($0.routeTargetID) }
                    ForEach(store.airPlayRouteCandidates) { Text("\($0.name) (AirPlay)").tag($0.routeTargetID) }
                    if let missingID = store.route(for: source).outputDeviceID,
                       !availableTargetIDs.contains(missingID) {
                        Text("\(store.routeOutputName(for: source)) (unavailable)").tag(missingID)
                    }
                }
                .labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity)
                .disabled(store.isPreparingRoute(for: source))
                SystemAirPlayPickerButton(compact: true, adaptsToAppearance: true)
            }
            HStack(spacing: 8) {
                iconButton(source.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                           label: source.isMuted ? "Unmute \(source.appName)" : "Mute \(source.appName)",
                           enabled: store.supportsPerAppMute) {
                    store.setSourceMuted(source: source, isMuted: !source.isMuted)
                }
                volumeControl(source.volume, enabled: store.supportsPerAppVolume, label: "\(source.appName) gain",
                              range: 0...1.5, accent: .orange) {
                    store.selectedSourceID = source.id
                    store.setSourceVolume(source: source, volume: $0)
                }
                Menu {
                    Button("Test Route", systemImage: "waveform") { store.testRoute(for: source) }
                    Button("Retry Route", systemImage: "arrow.clockwise") { store.retrySourceRoute(source) }
                        .disabled(store.route(for: source).routeMode != .customOutput)
                    Button("Follow System Output", systemImage: "arrow.uturn.backward") { store.resetSourceToSystemOutput(source) }
                    Divider()
                    Button("Route Details...", systemImage: "info.circle") { open(.advanced) }
                } label: { Image(systemName: "ellipsis.circle").frame(width: 28, height: 28) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Actions for \(source.appName)")
            }
            if let diagnostic = store.routeDiagnostic(for: source), store.routeStatusIsWarning(for: source) {
                Text(diagnostic).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var outputControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeading("Output devices", detail: "\(store.outputDevices.count) connected", destination: .devices)
            if store.outputDevices.isEmpty { emptyState("No outputs connected", symbol: "speaker.slash") }
            ForEach(store.outputDevices) { outputRow($0) }
            if !store.airPlayRouteCandidates.isEmpty {
                HStack {
                    Text("AirPlay").font(.subheadline.weight(.semibold))
                    Spacer()
                    SystemAirPlayPickerButton(compact: true, adaptsToAppearance: true)
                }
                ForEach(store.airPlayRouteCandidates) { candidate in
                    HStack {
                        Label(candidate.name, systemImage: "airplayaudio").lineLimit(1)
                        Spacer()
                        Text("Use AirPlay picker").font(.caption).foregroundStyle(.secondary)
                    }.font(.subheadline)
                }
            }
            Divider()
            HStack {
                Text("Group Play").font(.subheadline.weight(.semibold))
                Spacer()
                Button { store.createOutputGroup() } label: { Label("New Group", systemImage: "plus") }
                    .buttonStyle(MenuBarControlStyle()).disabled(store.outputDevices.isEmpty)
            }
            ForEach(store.outputGroups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(group.name, systemImage: "speaker.3.fill").font(.subheadline.weight(.semibold)).lineLimit(1)
                        Spacer()
                        Text("\(store.outputDevices(for: group).count) speakers").font(.caption).foregroundStyle(.secondary)
                        iconButton("slider.horizontal.3", label: "Edit \(group.name)") { open(.devices) }
                    }
                    ForEach(store.outputDevices(for: group)) { device in
                        HStack {
                            Text(device.name).font(.caption).lineLimit(1).frame(width: 135, alignment: .leading)
                            Slider(value: Binding(
                                get: { group.perDeviceVolumes[device.uid] ?? device.volume ?? 1 },
                                set: {
                                    store.selectOutputDevice(device)
                                    store.setOutputGroupVolume(group, deviceUID: device.uid, volume: $0)
                                }
                            ), in: 0...1, step: 0.01)
                            .disabled(!device.canSetVolume)
                            .accessibilityLabel("\(group.name), \(device.name) volume")
                        }
                    }
                }
            }
            Divider()
            Picker("Input device", selection: Binding(
                get: { store.currentInput?.uid ?? "" },
                set: { uid in
                    if let device = store.inputDevices.first(where: { $0.uid == uid }) { store.setDefaultDevice(device) }
                }
            )) {
                if store.currentInput == nil { Text("No input connected").tag("") }
                ForEach(store.inputDevices) { Text($0.name).tag($0.uid) }
            }
            .pickerStyle(.menu).disabled(store.inputDevices.isEmpty)
            if let input = store.currentInput, input.canSetVolume {
                Slider(value: Binding(get: { input.volume ?? 0 }, set: { store.setInputVolume($0) }), in: 0...1, step: 0.01)
                    .accessibilityLabel("\(input.name) input volume")
            }
        }
    }

    private func outputRow(_ device: AudioDevice) -> some View {
        let isSelected = store.selectedOutputDeviceID == device.uid
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { store.selectOutputDevice(device) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "speaker.wave.2")
                            .foregroundStyle(isSelected ? Color.teal : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(device.isDefault ? "System output" : device.transport.rawValue)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }.contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel("Select \(device.name) volume")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                MenuBarLevelMeter(meterState: store.meterState, target: .device(device.id))
                    .frame(width: 70, height: 20)
                Menu {
                    Button("Set as System Output", systemImage: "speaker.wave.2") { store.setDefaultDevice(device) }
                        .disabled(device.isDefault)
                    Button("Test Speaker", systemImage: "waveform") { store.testOutput(device) }
                } label: { Image(systemName: "ellipsis.circle").frame(width: 28, height: 28) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Actions for \(device.name)")
            }
            HStack(spacing: 8) {
                iconButton(device.isMuted == true ? "speaker.slash.fill" : "speaker.wave.2.fill",
                           label: device.isMuted == true ? "Unmute \(device.name)" : "Mute \(device.name)",
                           enabled: device.canSetMute) {
                    store.selectOutputDevice(device)
                    store.setDeviceMuted(device, isMuted: !(device.isMuted ?? false))
                }
                volumeControl(device.volume, enabled: device.canSetVolume, label: "\(device.name) output volume") {
                    store.selectOutputDevice(device)
                    store.setDeviceVolume(device, volume: $0)
                }
            }
        }
        .padding(10)
        .background(isSelected ? accent.opacity(0.10) : inset, in: RoundedRectangle(cornerRadius: 6))
    }

    private var setupControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeading("Saved setups", detail: store.activeUserProfile.displayName, destination: .setups)
            HStack(spacing: 8) {
                TextField("Setup name", text: $setupName).textFieldStyle(.roundedBorder).onSubmit { saveSetup() }
                Button { saveSetup() } label: { Label("Save Current", systemImage: "square.and.arrow.down") }
                    .buttonStyle(MenuBarControlStyle(prominent: true)).disabled(setupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let savedSetupName {
                Label("Saved \(savedSetupName)", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.teal)
            }
            if store.presetManager.presets.isEmpty { emptyState("No saved setups for this profile", symbol: "square.stack.3d.up") }
            ForEach(store.presetManager.presets) { preset in
                HStack(spacing: 10) {
                    Image(systemName: "square.stack.3d.up").foregroundStyle(.teal)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(preset.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text("\(preset.appOutputAssignments.count) app routes \u{00B7} \(preset.eqPreset.rawValue) EQ")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Button("Apply") { store.applyPreset(preset) }.buttonStyle(MenuBarControlStyle())
                }.padding(.vertical, 5)
            }
        }
    }

    private var equalizerControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeading("Equalizer", detail: store.eqManager.state.selectedPreset.rawValue, destination: .eq)
            Picker("EQ preset", selection: Binding(
                get: { store.eqManager.state.selectedPreset }, set: { store.eqManager.applyPreset($0) }
            )) {
                ForEach(EQPreset.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.menu)
            VStack(spacing: 12) {
                EQCurveView(bands: store.eqManager.state.bands).frame(height: 64)
                HStack(spacing: 0) {
                    ForEach(EQPreset.bandLabels.indices, id: \.self) { index in
                        EQBandStrip(label: EQPreset.bandLabels[index], value: store.eqManager.state.bands[index],
                                    isEnabled: true, height: 88,
                                    onChange: { store.eqManager.setBand(index: index, gain: $0) })
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(8)
            .background(ConsolePalette.inset, in: RoundedRectangle(cornerRadius: 8))
            .environment(\.colorScheme, .dark)
            HStack {
                Button { store.eqManager.reset() } label: { Label("Reset Flat", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(MenuBarControlStyle())
                Spacer()
                Button { store.eqManager.saveCustomPreset() } label: { Label("Save Custom", systemImage: "square.and.arrow.down") }
                    .buttonStyle(MenuBarControlStyle(prominent: true))
            }
        }
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("AUDIOROUTER").font(.system(size: 10, weight: .heavy, design: .rounded))
                Text("by Alan").font(.system(size: 9, weight: .semibold))
            }.foregroundStyle(.primary.opacity(0.5)).accessibilityHidden(true)
            Spacer()
            iconButton("stethoscope", label: "Reliability and diagnostics") { open(.advanced) }
            iconButton("gearshape", label: "Settings") { open(.settings) }
            Button { open(section.destination) } label: {
                Label("Open App", systemImage: "arrow.up.right.square")
            }.buttonStyle(MenuBarControlStyle())
                .help("Open \(section.destination.rawValue)")
        }
    }

    private var inset: Color { Color.primary.opacity(0.045) }
    private var accent: Color { colorScheme == .dark ? Color(red: 0.36, green: 0.80, blue: 0.75) : Color(red: 0.08, green: 0.47, blue: 0.44) }
    private var selectedSource: AudioSource? {
        store.audioSources.first { $0.id == selectedSourceID } ?? store.audioSources.first
    }
    private var availableTargetIDs: Set<String> {
        Set(store.outputDevices.map(\.uid) + store.outputGroups.map(\.routeTargetID) + store.airPlayRouteCandidates.map(\.routeTargetID))
    }

    private func synchronizeSource() {
        if !store.audioSources.contains(where: { $0.id == selectedSourceID }) {
            selectedSourceID = store.audioSources.first { $0.id == store.selectedSourceID }?.id ?? store.audioSources.first?.id ?? ""
        }
    }

    private func selectVolumeTarget() {
        if section == .apps, let source = selectedSource { store.selectedSourceID = source.id }
        else if section == .outputs,
                !store.outputDevices.contains(where: { $0.uid == store.selectedOutputDeviceID }),
                let output = store.currentOutput ?? store.outputDevices.first { store.selectOutputDevice(output) }
    }

    private func saveSetup() {
        let name = setupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        store.saveCurrentSetup(named: name)
        savedSetupName = name
        setupName = ""
    }

    private func open(_ destination: SettingsSection) {
        store.selectedSettingsSection = destination
        showMainWindow()
    }

    private func sectionHeading(_ title: String, detail: String, destination: SettingsSection) -> some View {
        HStack {
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func volumeControl(_ value: Double?, enabled: Bool, label: String,
                               range: ClosedRange<Double> = 0...1, accent: Color = .teal,
                               action: @escaping (Double) -> Void) -> some View {
        let current = min(range.upperBound, max(range.lowerBound, value ?? range.lowerBound))
        let canAdjust = enabled && value != nil
        return HStack(spacing: 8) {
            iconButton("minus", label: "Decrease \(label) by 1%", enabled: canAdjust && current > range.lowerBound) {
                action(max(range.lowerBound, current - 0.01))
            }
            Slider(value: Binding(get: { current }, set: { action(($0 * 100).rounded() / 100) }), in: range)
                .tint(accent)
                .disabled(!canAdjust)
                .accessibilityLabel(label)
                .accessibilityValue(value?.roundedPercentDescription ?? "Unavailable")
                .accessibilityAdjustableAction { direction in
                    guard canAdjust else { return }
                    switch direction {
                    case .increment: action(min(range.upperBound, current + 0.01))
                    case .decrement: action(max(range.lowerBound, current - 0.01))
                    @unknown default: break
                    }
                }
            iconButton("plus", label: "Increase \(label) by 1%", enabled: canAdjust && current < range.upperBound) {
                action(min(range.upperBound, current + 0.01))
            }
            Text(value?.roundedPercentDescription ?? "N/A")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(canAdjust ? .primary : .secondary)
                .frame(width: 42, alignment: .trailing)
        }
    }

    private func iconButton(_ symbol: String, label: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 28, height: 28) }
            .buttonStyle(MenuBarControlStyle(iconOnly: true))
            .disabled(!enabled).help(label).accessibilityLabel(label)
    }

    private func emptyState(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.subheadline).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
    }
}

private enum MenuBarSection: String, CaseIterable, Identifiable {
    case apps = "Apps", outputs = "Outputs", setups = "Setups", eq = "EQ"
    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .apps: return "app.connected.to.app.below.fill"
        case .outputs: return "speaker.wave.2"
        case .setups: return "square.stack.3d.up"
        case .eq: return "waveform"
        }
    }
    var destination: SettingsSection {
        switch self {
        case .apps: return .dashboard
        case .outputs: return .devices
        case .setups: return .setups
        case .eq: return .eq
        }
    }
}

private struct MenuBarControlStyle: ButtonStyle {
    var prominent = false
    var iconOnly = false

    func makeBody(configuration: Configuration) -> some View {
        MenuBarControlBody(configuration: configuration, prominent: prominent, iconOnly: iconOnly)
    }
}

private struct MenuBarLevelMeter: View {
    enum Target {
        case source(String)
        case device(String)
    }

    @ObservedObject var meterState: AudioMeterState
    let target: Target
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var level: Double {
        let value: Double
        switch target {
        case .source(let id): value = meterState.snapshot.sourceMeters[id] ?? 0
        case .device(let id): value = meterState.snapshot.deviceMeters[id] ?? 0
        }
        return min(1, max(0, value))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.primary.opacity(0.12))
                Rectangle().fill(Color.teal)
                    .frame(width: proxy.size.width * level)
            }
            .frame(height: 3)
            .frame(maxHeight: .infinity)
        }
        .animation(reduceMotion ? nil : .linear(duration: 0.10), value: level)
        .accessibilityLabel("Audio level")
        .accessibilityValue(level.roundedPercentDescription)
    }
}

private struct MenuBarControlBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    let iconOnly: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    private var accent: Color {
        colorScheme == .dark ? Color(red: 0.36, green: 0.80, blue: 0.75) : Color(red: 0.08, green: 0.47, blue: 0.44)
    }

    var body: some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, iconOnly ? 0 : 10)
            .frame(minHeight: 28)
            .foregroundStyle(prominent ? (colorScheme == .dark ? Color.black : .white) : .primary)
            .background(prominent ? accent.opacity(configuration.isPressed ? 0.7 : 1) : Color.primary.opacity(configuration.isPressed ? 0.12 : (hovering ? 0.08 : 0.045)), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: hovering)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: configuration.isPressed)
    }
}
