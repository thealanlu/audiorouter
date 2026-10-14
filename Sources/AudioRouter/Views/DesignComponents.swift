import AppKit
import SwiftUI
#if canImport(AVKit)
import AVKit
#endif

struct DockCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.08))
        }
    }
}

enum ConsolePalette {
    static let window = Color(red: 0.035, green: 0.039, blue: 0.047)
    static let windowChrome = Color(red: 0.092, green: 0.098, blue: 0.112)
    static let sidebar = Color(red: 0.069, green: 0.074, blue: 0.086)
    static let console = Color(red: 0.047, green: 0.051, blue: 0.060)
    static let header = Color(red: 0.074, green: 0.080, blue: 0.092)
    static let panel = Color(red: 0.060, green: 0.065, blue: 0.076)
    static let strip = Color(red: 0.094, green: 0.101, blue: 0.116)
    static let inset = Color(red: 0.030, green: 0.033, blue: 0.040)
    static let stroke = Color.white.opacity(0.085)
    static let strongStroke = Color.white.opacity(0.14)
    static let green = Color(red: 0.45, green: 0.88, blue: 0.58)
    static let amber = Color(red: 0.94, green: 0.66, blue: 0.36)
    static let teal = Color(red: 0.36, green: 0.80, blue: 0.75)
    static let blue = Color(red: 0.50, green: 0.63, blue: 0.92)
    static let red = Color(red: 0.94, green: 0.38, blue: 0.36)
    static let warmInk = Color(red: 0.11, green: 0.085, blue: 0.050)
}

enum AudioRouterButtonKind {
    case primary
    case secondary
    case quiet
    case destructive
}

struct AudioRouterButtonStyle: ButtonStyle {
    let kind: AudioRouterButtonKind
    let tint: Color

    init(kind: AudioRouterButtonKind = .secondary, tint: Color = ConsolePalette.teal) {
        self.kind = kind
        self.tint = tint
    }

    func makeBody(configuration: Configuration) -> some View {
        AudioRouterButtonBody(configuration: configuration, kind: kind, tint: tint)
    }
}

extension ButtonStyle where Self == AudioRouterButtonStyle {
    static var audioRouter: AudioRouterButtonStyle {
        AudioRouterButtonStyle()
    }

    static var audioRouterPrimary: AudioRouterButtonStyle {
        AudioRouterButtonStyle(kind: .primary)
    }

    static var audioRouterQuiet: AudioRouterButtonStyle {
        AudioRouterButtonStyle(kind: .quiet)
    }

    static var audioRouterDestructive: AudioRouterButtonStyle {
        AudioRouterButtonStyle(kind: .destructive, tint: ConsolePalette.red)
    }
}

private struct AudioRouterButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: AudioRouterButtonKind
    let tint: Color

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(buttonFont)
            .lineLimit(1)
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: minimumHeight)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            }
            .shadow(color: shadowColor, radius: configuration.isPressed ? 2 : 7, y: configuration.isPressed ? 1 : 3)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(isEnabled ? 1 : 0.46)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
    }

    private var minimumHeight: CGFloat {
        switch controlSize {
        case .mini: return 22
        case .small: return 28
        case .large: return 36
        default: return 31
        }
    }

    private var horizontalPadding: CGFloat {
        switch controlSize {
        case .mini: return kind == .quiet ? 5 : 8
        case .small: return kind == .quiet ? 6 : 10
        case .large: return kind == .quiet ? 10 : 15
        default: return kind == .quiet ? 8 : 12
        }
    }

    private var buttonFont: Font {
        switch controlSize {
        case .mini: return .system(size: 10, weight: .semibold)
        case .small: return .system(size: 11, weight: .semibold)
        case .large: return .system(size: 14, weight: .semibold)
        default: return .system(size: 12, weight: .semibold)
        }
    }

    private var foregroundColor: Color {
        switch kind {
        case .primary:
            return ConsolePalette.warmInk
        case .destructive:
            return isHovering ? .white : tint
        case .secondary, .quiet:
            return isHovering ? .white : .primary
        }
    }

    private var backgroundColor: Color {
        let pressed = configuration.isPressed
        switch kind {
        case .primary:
            return tint.opacity(pressed ? 0.76 : (isHovering ? 1 : 0.90))
        case .secondary:
            return isHovering
                ? tint.opacity(pressed ? 0.14 : 0.18)
                : ConsolePalette.strip.opacity(pressed ? 0.72 : 0.92)
        case .quiet:
            return isHovering ? Color.white.opacity(pressed ? 0.055 : 0.09) : .clear
        case .destructive:
            return isHovering ? tint.opacity(pressed ? 0.62 : 0.78) : tint.opacity(0.10)
        }
    }

    private var borderColor: Color {
        switch kind {
        case .primary:
            return Color.white.opacity(isHovering ? 0.30 : 0.18)
        case .secondary:
            return isHovering ? tint.opacity(0.52) : ConsolePalette.strongStroke
        case .quiet:
            return isHovering ? ConsolePalette.strongStroke : .clear
        case .destructive:
            return tint.opacity(isHovering ? 0.86 : 0.36)
        }
    }

    private var shadowColor: Color {
        guard isEnabled, !configuration.isPressed else { return .clear }
        switch kind {
        case .primary: return tint.opacity(isHovering ? 0.24 : 0.12)
        case .destructive: return tint.opacity(isHovering ? 0.18 : 0.05)
        case .secondary, .quiet: return .black.opacity(isHovering ? 0.18 : 0.08)
        }
    }
}

struct AudioRouterSidebar: View {
    @Binding var selection: SettingsSection
    var showsWatermark = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                ForEach(SettingsSection.allCases) { section in
                    AudioRouterSidebarRow(
                        section: section,
                        isSelected: selection == section
                    ) {
                        selection = section
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if showsWatermark {
                AudioRouterWatermarkBanner(titleSize: 10, subtitleSize: 9, titleTracking: 0)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 18)
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ConsolePalette.sidebar)
        .navigationSplitViewColumnWidth(min: 168, ideal: 176, max: 196)
    }
}

private struct AudioRouterSidebarRow: View {
    let section: SettingsSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(isSelected ? ConsolePalette.teal : .clear)
                    .frame(width: 3, height: 17)

                Image(systemName: section.systemImage)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? ConsolePalette.teal : .secondary)
                    .frame(width: 18, height: 18, alignment: .center)

                Text(section.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isSelected ? ConsolePalette.teal.opacity(0.20) : .clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityLabel(section.rawValue)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Shows the \(section.rawValue) screen")
    }

    private var rowBackground: Color {
        if isSelected {
            return ConsolePalette.teal.opacity(0.11)
        }
        return .clear
    }
}

struct AudioRouterToolbarStyler: NSViewRepresentable {
    func makeNSView(context: Context) -> ToolbarStylerView {
        let view = ToolbarStylerView(frame: .zero)
        view.styleNativeSidebarToggle()
        return view
    }

    func updateNSView(_ nsView: ToolbarStylerView, context: Context) {
        nsView.styleNativeSidebarToggle()
    }

    static func scheduleStyling() {
        for delay in [0.0, 0.15, 0.45] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                NSApp.windows.forEach(ToolbarStylerView.styleNativeSidebarToggle(in:))
            }
        }
    }
}

final class ToolbarStylerView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        styleNativeSidebarToggle()

        DispatchQueue.main.async {
            self.styleNativeSidebarToggle()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { [weak self] in
            self?.styleNativeSidebarToggle()
        }
    }

    func styleNativeSidebarToggle() {
        Self.styleNativeSidebarToggle(in: window)
    }

    static func styleNativeSidebarToggle(in window: NSWindow?) {
        guard let window, let toolbar = window.toolbar else { return }

        for item in toolbar.items where isNativeSidebarToggle(item) {
            item.isBordered = false
            installBorderlessButton(on: item)
        }

        if let titlebarView = window.contentView?.superview {
            styleSidebarButtons(in: titlebarView)
        }
    }

    private static func isNativeSidebarToggle(_ item: NSToolbarItem) -> Bool {
        let identifier = item.itemIdentifier.rawValue.lowercased()
        return item.itemIdentifier == .toggleSidebar
            || item.action == #selector(NSSplitViewController.toggleSidebar(_:))
            || identifier.contains("togglesidebar")
            || identifier.contains("sidebar-toggle")
    }

    private static func installBorderlessButton(on item: NSToolbarItem) {
        let button: BorderlessSidebarToolbarButton
        if let existingButton = item.view as? BorderlessSidebarToolbarButton {
            button = existingButton
        } else {
            let originalTarget = item.target
            let originalAction = item.action ?? #selector(NSSplitViewController.toggleSidebar(_:))
            button = BorderlessSidebarToolbarButton(frame: NSRect(x: 0, y: 0, width: 32, height: 28))
            button.target = originalTarget
            button.action = originalAction
            button.image = NSImage(
                systemSymbolName: "sidebar.leading",
                accessibilityDescription: "Toggle Sidebar"
            )?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            )
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.contentTintColor = .secondaryLabelColor
            button.focusRingType = .none
            button.toolTip = "Toggle Sidebar"
            button.setAccessibilityLabel("Toggle Sidebar")
            item.view = button
        }

        style(button)
    }

    private static func styleSidebarButtons(in view: NSView) {
        if let button = view as? NSButton,
           button.action == #selector(NSSplitViewController.toggleSidebar(_:)) {
            style(button)
        }
        view.subviews.forEach(styleSidebarButtons(in:))
    }

    private static func style(_ button: NSButton) {
        button.isBordered = false
        button.showsBorderOnlyWhileMouseInside = false
        button.wantsLayer = true
        button.layer?.borderWidth = 0
        button.layer?.cornerRadius = 0
        button.layer?.backgroundColor = NSColor.clear.cgColor
        if let cell = button.cell as? NSButtonCell {
            cell.isBordered = false
            cell.showsBorderOnlyWhileMouseInside = false
        }
    }
}

private final class BorderlessSidebarToolbarButton: NSButton {
    override var intrinsicContentSize: NSSize {
        NSSize(width: 32, height: 28)
    }
}

struct SystemAirPlayPickerButton: View {
    var title: String = "AirPlay"
    var compact = false
    var adaptsToAppearance = false

    var body: some View {
        HStack(spacing: 7) {
#if canImport(AVKit)
            AirPlayRoutePickerRepresentable(adaptsToAppearance: adaptsToAppearance)
                .frame(width: 18, height: 18)
                .accessibilityLabel("Open macOS AirPlay route picker")
#else
            Image(systemName: "airplayaudio")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 18, height: 18)
#endif

            if !compact {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, compact ? 5 : 10)
        .frame(height: 28)
        .background(adaptsToAppearance ? Color.primary.opacity(0.045) : ConsolePalette.strip.opacity(0.82), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(ConsolePalette.teal.opacity(0.36), lineWidth: 1)
        }
        .foregroundStyle(adaptsToAppearance ? Color.primary : .white.opacity(0.86))
        .help("Open the macOS AirPlay picker for TV, HomePod, and other routes that may not appear as Core Audio devices until selected.")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Open AirPlay output picker")
        .accessibilityHint("Use this for TV, HomePod, and other AirPlay routes that are not yet listed as output devices.")
    }
}

#if canImport(AVKit)
private struct AirPlayRoutePickerRepresentable: NSViewRepresentable {
    let adaptsToAppearance: Bool

    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(frame: .zero)
        view.isRoutePickerButtonBordered = false
        view.setRoutePickerButtonColor(adaptsToAppearance ? .labelColor : .white.withAlphaComponent(0.86), for: .normal)
        view.setRoutePickerButtonColor(adaptsToAppearance ? .labelColor : .white, for: .normalHighlighted)
        view.setRoutePickerButtonColor(NSColor.systemTeal, for: .active)
        view.setRoutePickerButtonColor(NSColor.systemTeal, for: .activeHighlighted)
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        return view
    }

    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
}
#endif

struct ConsoleFrame<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(ConsolePalette.console, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct ConsolePageHeader<Accessory: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let accessory: Accessory

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color = ConsolePalette.teal,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)
            accessory
        }
        .padding(14)
        .background(ConsolePalette.header, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ConsolePalette.stroke, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(subtitle)")
    }
}

struct ConsolePanel<Content: View>: View {
    let title: String
    let systemImage: String
    let trailing: String?
    let tint: Color
    let content: Content

    init(
        title: String,
        systemImage: String,
        trailing: String? = nil,
        tint: Color = ConsolePalette.amber,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.trailing = trailing
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(tint)
                    .frame(width: 18, height: 18, alignment: .center)
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .tracking(0)
                    .lineLimit(1)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(ConsolePalette.header)

            Rectangle()
                .fill(ConsolePalette.stroke)
                .frame(height: 1)

            content
                .padding(12)
        }
        .background(ConsolePalette.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ConsolePalette.strongStroke, lineWidth: 1)
        }
    }
}

struct ConsoleMetricTile: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            ConsoleLED(color: tint)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint.opacity(0.85))
                .frame(width: 16, height: 16, alignment: .center)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(ConsolePalette.inset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(ConsolePalette.stroke, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
    }
}

struct ConsoleSectionMarker: View {
    let title: String
    let detail: String
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Capsule()
                .fill(tint)
                .frame(width: 4, height: 16)
                .shadow(color: tint.opacity(0.45), radius: 3)
            Text(title.uppercased())
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.9))
                .lineLimit(1)
            Rectangle()
                .fill(ConsolePalette.stroke)
                .frame(height: 1)
            Text(detail)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(height: 16, alignment: .center)
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(detail)")
    }
}

struct ConsoleLED: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .shadow(color: color.opacity(0.65), radius: 4)
            .accessibilityHidden(true)
    }
}

struct SectionHeader: View {
    let title: String
    let systemImage: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .frame(width: 20, height: 20, alignment: .center)
            Text(title)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 20, alignment: .center)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(trailing.map { "\(title), \($0)" } ?? title)
    }
}

struct AudioRouterWatermarkBanner: View {
    var titleSize: CGFloat = 10
    var subtitleSize: CGFloat = 9
    var titleTracking: CGFloat = 0
    var lineSpacing: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: lineSpacing) {
            Text("AUDIOROUTER")
                .font(.system(size: titleSize, weight: .black, design: .rounded))
                .tracking(titleTracking)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text("by Alan")
                .font(.system(size: subtitleSize, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(Color.white.opacity(0.50))
        .shadow(color: .black.opacity(0.35), radius: 5, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("AUDIOROUTER by Alan")
    }
}

struct StatusBadge: View {
    let text: String
    var isActive: Bool = false

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(isActive ? .black : .secondary)
            .background(isActive ? .green : .secondary.opacity(0.12), in: Capsule())
            .accessibilityLabel("\(text) status")
    }
}

struct SourceQualityPill: View {
    let label: String
    let isLive: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isLive ? "waveform.circle.fill" : "waveform.circle")
                .font(.system(size: 8, weight: .bold))
                .accessibilityHidden(true)
            Text(label)
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .lineLimit(1)
        }
        .foregroundStyle(isLive ? .cyan : .secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background((isLive ? Color.cyan : Color.secondary).opacity(0.10), in: Capsule())
        .overlay {
            Capsule()
                .stroke((isLive ? Color.cyan : Color.secondary).opacity(isLive ? 0.28 : 0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isLive ? "Live source sample rate \(label)" : "Source sample rate \(label)")
    }
}

struct DeviceIcon: View {
    let device: AudioDevice

    var body: some View {
        Image(systemName: imageName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(device.isDefault ? .teal : .secondary)
            .frame(width: 28, height: 28)
            .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }

    private var imageName: String {
        switch (device.kind, device.transport) {
        case (.input, _): return "mic.fill"
        case (.output, .bluetooth), (.output, .bluetoothLE): return "headphones"
        case (.output, .airPlay): return "airplayaudio"
        case (.output, .usb): return "cable.connector"
        default: return "speaker.wave.2.fill"
        }
    }
}

struct AppSourceIcon: View {
    let source: AudioSource

    var body: some View {
        Group {
            if let image = AppIconResolver.icon(for: source) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 30, height: 30)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct SupportNote: View {
    let note: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.blue)
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Dismiss note")
            .accessibilityHint("Hides this message")
        }
        .padding(10)
        .background(.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("AudioRouter note")
    }
}

struct VolumeSlider: View {
    let title: String
    let value: Double?
    let isEnabled: Bool
    let systemImage: String
    let range: ClosedRange<Double>
    let step: Double
    let accent: Color
    let showsStepButtons: Bool
    let nudgeStep: Double
    let onChange: (Double) -> Void

    @State private var draftValue: Double?
    @State private var isEditing = false

    init(
        title: String,
        value: Double?,
        isEnabled: Bool,
        systemImage: String,
        range: ClosedRange<Double> = 0...1,
        step: Double = 0.01,
        accent: Color = .teal,
        showsStepButtons: Bool = false,
        nudgeStep: Double = 0.05,
        onChange: @escaping (Double) -> Void
    ) {
        self.title = title
        self.value = value
        self.isEnabled = isEnabled
        self.systemImage = systemImage
        self.range = range
        self.step = step
        self.accent = accent
        self.showsStepButtons = showsStepButtons
        self.nudgeStep = nudgeStep
        self.onChange = onChange
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(isEnabled ? accent : .secondary)
                .frame(width: 18)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            if showsStepButtons {
                nudgeButton(systemImage: "minus", delta: -stepSize)
            }
            SmoothVolumeFader(
                value: displayedValue,
                isEnabled: isEnabled,
                range: range,
                step: step,
                accent: accent,
                accessibilityLabel: "\(title) volume",
                accessibilityValue: accessibilityValue,
                accessibilityHint: isEnabled ? "Adjusts \(title.lowercased()) volume" : "\(title) volume is not exposed by this device",
                onEditingChanged: updateEditingState,
                onChange: updateValue
            )
            if showsStepButtons {
                nudgeButton(systemImage: "plus", delta: stepSize)
            }
            percentPill
        }
        .help(isEnabled ? "\(title) volume" : "\(title) volume is not exposed by this device.")
    }

    private var displayedValue: Double {
        steppedValue(draftValue ?? value ?? range.lowerBound)
    }

    private var accessibilityValue: String {
        value == nil ? "Not available" : displayedValue.roundedPercentDescription
    }

    private var percentPill: some View {
        Text(value == nil ? "N/A" : displayedValue.roundedPercentDescription)
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(isEnabled ? accent : .secondary)
            .frame(minWidth: 46, alignment: .trailing)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(isEnabled ? accent.opacity(isEditing ? 0.22 : 0.12) : Color.secondary.opacity(0.08))
            )
    }

    private func updateValue(_ newValue: Double) {
        let adjusted = steppedValue(newValue)
        draftValue = adjusted
        onChange(adjusted)
    }

    private func updateEditingState(_ editing: Bool) {
        isEditing = editing
        if !editing {
            onChange(displayedValue)
            draftValue = nil
        }
    }

    private func nudgeButton(systemImage: String, delta: Double) -> some View {
        Button {
            updateValue(displayedValue + delta)
            draftValue = nil
        } label: {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(isEnabled ? .secondary : .tertiary)
        .disabled(!isEnabled || value == nil)
        .accessibilityLabel(delta < 0 ? "Decrease \(title) volume" : "Increase \(title) volume")
    }

    private var stepSize: Double {
        nudgeStep
    }

    private func steppedValue(_ value: Double) -> Double {
        range.snapped(value, to: step)
    }
}

struct InlineVolumeSlider: View {
    let value: Double?
    let isEnabled: Bool
    let systemImage: String
    let range: ClosedRange<Double>
    let step: Double
    let accent: Color
    let showsStepButtons: Bool
    let nudgeStep: Double
    let accessibilityLabel: String
    let accessibilityHint: String
    let onChange: (Double) -> Void

    @State private var draftValue: Double?
    @State private var isEditing = false

    init(
        value: Double?,
        isEnabled: Bool,
        systemImage: String = "speaker.wave.2.fill",
        range: ClosedRange<Double> = 0...1,
        step: Double = 0.01,
        accent: Color = .teal,
        showsStepButtons: Bool = false,
        nudgeStep: Double = 0.05,
        accessibilityLabel: String,
        accessibilityHint: String,
        onChange: @escaping (Double) -> Void
    ) {
        self.value = value
        self.isEnabled = isEnabled
        self.systemImage = systemImage
        self.range = range
        self.step = step
        self.accent = accent
        self.showsStepButtons = showsStepButtons
        self.nudgeStep = nudgeStep
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.onChange = onChange
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isEnabled ? accent : .secondary)
                .frame(width: 16)

            if showsStepButtons {
                nudgeButton(systemImage: "minus", delta: -nudgeStep)
            }

            SmoothVolumeFader(
                value: displayedValue,
                isEnabled: isEnabled,
                range: range,
                step: step,
                accent: accent,
                accessibilityLabel: accessibilityLabel,
                accessibilityValue: value == nil ? "Not available" : displayedValue.roundedPercentDescription,
                accessibilityHint: accessibilityHint,
                onEditingChanged: updateEditingState,
                onChange: updateValue
            )
            .frame(minWidth: showsStepButtons ? 96 : 80)

            if showsStepButtons {
                nudgeButton(systemImage: "plus", delta: nudgeStep)
            }

            percentPill
        }
        .help(accessibilityHint)
        .transaction { transaction in
            transaction.animation = isEditing ? nil : .easeOut(duration: 0.08)
        }
    }

    private var displayedValue: Double {
        range.snapped(draftValue ?? value ?? range.lowerBound, to: step)
    }

    private func updateValue(_ newValue: Double) {
        let adjusted = range.snapped(newValue, to: step)
        draftValue = adjusted
        onChange(adjusted)
    }

    private func updateEditingState(_ editing: Bool) {
        isEditing = editing
        if !editing {
            onChange(displayedValue)
            draftValue = nil
        }
    }

    private var percentPill: some View {
        Text(value == nil ? "N/A" : displayedValue.roundedPercentDescription)
            .font(.caption2.monospacedDigit().weight(.bold))
            .foregroundStyle(isEnabled ? accent : .secondary)
            .frame(width: 48, alignment: .trailing)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(isEnabled ? accent.opacity(isEditing ? 0.24 : 0.13) : Color.secondary.opacity(0.08))
            )
    }

    private func nudgeButton(systemImage: String, delta: Double) -> some View {
        Button {
            updateValue(displayedValue + delta)
            draftValue = nil
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(isEnabled ? .secondary : .tertiary)
        .disabled(!isEnabled || value == nil)
        .accessibilityLabel(delta < 0 ? "Decrease volume" : "Increase volume")
    }
}

private struct SmoothVolumeFader: View {
    let value: Double
    let isEnabled: Bool
    let range: ClosedRange<Double>
    let step: Double
    let accent: Color
    let accessibilityLabel: String
    let accessibilityValue: String
    let accessibilityHint: String
    let onEditingChanged: (Bool) -> Void
    let onChange: (Double) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDragging = false

    private let knobSize: CGFloat = 17
    private let trackHeight: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, knobSize)
            let trackWidth = max(1, width - knobSize)
            let normalized = normalizedValue(value)
            let fillWidth = trackWidth * normalized

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(isEnabled ? 0.09 : 0.055))
                    .frame(width: trackWidth, height: trackHeight)
                    .offset(x: knobSize / 2)

                Capsule(style: .continuous)
                    .fill(accent.opacity(isEnabled ? 0.92 : 0.35))
                    .frame(width: fillWidth, height: trackHeight)
                    .offset(x: knobSize / 2)

                Circle()
                    .fill(isEnabled ? Color.white.opacity(0.90) : Color.secondary.opacity(0.55))
                    .overlay {
                        Circle()
                            .stroke(accent.opacity(isEnabled ? (isDragging ? 0.92 : 0.62) : 0.28), lineWidth: isDragging ? 2 : 1)
                    }
                    .shadow(color: accent.opacity(isEnabled && isDragging ? 0.42 : 0.22), radius: isDragging ? 7 : 3, x: 0, y: 1)
                    .frame(width: knobSize, height: knobSize)
                    .offset(x: fillWidth)
            }
            .frame(height: 24, alignment: .center)
            .contentShape(Rectangle())
            .gesture(dragGesture(trackWidth: trackWidth))
            .allowsHitTesting(isEnabled)
            .animation(faderAnimation, value: value)
            .animation(faderAnimation, value: isDragging)
        }
        .frame(height: 24)
        .opacity(isEnabled ? 1 : 0.58)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(accessibilityHint)
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            switch direction {
            case .increment:
                onChange(range.snapped(value + step, to: step))
            case .decrement:
                onChange(range.snapped(value - step, to: step))
            @unknown default:
                break
            }
        }
    }

    private var faderAnimation: Animation? {
        guard !reduceMotion, !isDragging else { return nil }
        return .interpolatingSpring(stiffness: 320, damping: 30)
    }

    private func dragGesture(trackWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isEnabled else { return }
                if !isDragging {
                    isDragging = true
                    onEditingChanged(true)
                }
                onChange(valueForDragLocation(value.location.x, trackWidth: trackWidth))
            }
            .onEnded { value in
                guard isEnabled else { return }
                onChange(valueForDragLocation(value.location.x, trackWidth: trackWidth))
                isDragging = false
                onEditingChanged(false)
            }
    }

    private func valueForDragLocation(_ x: CGFloat, trackWidth: CGFloat) -> Double {
        guard trackWidth > 0 else { return range.lowerBound }
        let adjustedX = min(max(x - knobSize / 2, 0), trackWidth)
        let normalized = Double(adjustedX / trackWidth)
        let rawValue = range.lowerBound + (range.upperBound - range.lowerBound) * normalized
        return range.snapped(rawValue, to: step)
    }

    private func normalizedValue(_ value: Double) -> CGFloat {
        let clampedValue = range.clamped(value)
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat((clampedValue - range.lowerBound) / span)
    }
}

private extension ClosedRange where Bound == Double {
    func clamped(_ value: Double) -> Double {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }

    func snapped(_ value: Double, to step: Double) -> Double {
        let clampedValue = clamped(value)
        guard step > 0 else { return clampedValue }
        let snappedValue = lowerBound + ((clampedValue - lowerBound) / step).rounded() * step
        return clamped((snappedValue * 1_000).rounded() / 1_000)
    }
}
