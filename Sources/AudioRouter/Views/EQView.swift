import Foundation
import SwiftUI

struct EQView: View {
    @ObservedObject var eqManager: EQManager
    var compact: Bool = false
    @State private var showBefore = false

    private var displayedBands: [Double] {
        showBefore ? EQPreset.flat.bands : eqManager.state.bands
    }

    var body: some View {
        ConsoleFrame {
            VStack(alignment: .leading, spacing: 12) {
                header
                ConsolePanel(
                    title: "Equalizer",
                    systemImage: "slider.vertical.3",
                    trailing: eqManager.state.selectedPreset.rawValue,
                    tint: ConsolePalette.teal
                ) {
                    VStack(alignment: .leading, spacing: compact ? 12 : 16) {
                        presetGrid
                        curvePreview
                        bandControls
                        actionBar
                        backendNote
                    }
                }
            }
        }
    }

    private var header: some View {
        ConsolePageHeader(
            title: "EQ",
            subtitle: "Shape tone with a 10-band visual equalizer.",
            systemImage: "waveform.path.ecg",
            tint: ConsolePalette.teal
        ) {
            HStack(spacing: 10) {
                StatusLabel(text: showBefore ? "Flat Compare" : eqManager.state.selectedPreset.rawValue, status: showBefore ? .simulated : .working)

                Toggle("Before", isOn: $showBefore)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityHint("Compares the current EQ curve with a flat response")
            }
        }
    }

    private var presetGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            ConsoleSectionMarker(title: "Presets", detail: "\(EQPreset.allCases.count) curves", tint: ConsolePalette.amber)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(EQPreset.allCases) { preset in
                    EQPresetButton(
                        preset: preset,
                        isSelected: eqManager.state.selectedPreset == preset && !showBefore
                    ) {
                        showBefore = false
                        eqManager.applyPreset(preset)
                    }
                }
            }
        }
    }

    private var curvePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ConsoleSectionMarker(title: "Curve Preview", detail: "Live shape", tint: ConsolePalette.teal)
                Spacer()
                Text(gainRangeSummary)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            EQCurveView(bands: displayedBands)
                .frame(height: compact ? 86 : 132)
        }
    }

    private var bandControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ConsoleSectionMarker(title: "10-Band Control", detail: "Drag to adjust", tint: ConsolePalette.blue)
                Spacer()
                Text("-12 dB to +12 dB")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .bottom, spacing: compact ? 8 : 12) {
                ForEach(EQPreset.bandLabels.indices, id: \.self) { index in
                    EQBandStrip(
                        label: EQPreset.bandLabels[index],
                        value: eqManager.state.bands[index],
                        isEnabled: !showBefore,
                        height: compact ? 148 : 226,
                        onChange: { eqManager.setBand(index: index, gain: $0) }
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, compact ? 8 : 12)
            .padding(.vertical, compact ? 10 : 14)
            .background(ConsolePalette.inset.opacity(0.80), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button {
                showBefore = false
                eqManager.reset()
            } label: {
                Label("Reset Flat", systemImage: "arrow.counterclockwise")
            }

            Button {
                showBefore = false
                eqManager.saveCustomPreset()
            } label: {
                Label("Save Custom", systemImage: "square.and.arrow.down")
            }

            Spacer()

            Button {
                showBefore.toggle()
            } label: {
                Label(showBefore ? "Show EQ" : "Compare Flat", systemImage: showBefore ? "slider.vertical.3" : "rectangle.split.2x1")
            }
        }
        .controlSize(.small)
    }

    private var backendNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.teal)
                .frame(width: 18, height: 18)
            Text("EQ applies live to AudioRouter process-tap routes and is saved with your presets. System audio that is not routed through AudioRouter is unchanged.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var gainRangeSummary: String {
        let bands = displayedBands
        guard let minimum = bands.min(), let maximum = bands.max() else { return "Flat" }
        return "\(gainText(minimum)) to \(gainText(maximum))"
    }
}

private struct EQPresetButton: View {
    let preset: EQPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 16, height: 16)
                Text(preset.rawValue)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(isSelected ? .black : .primary)
            .background(isSelected ? ConsolePalette.teal : ConsolePalette.inset.opacity(0.85), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.clear : Color.white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(preset.rawValue) EQ preset")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private var iconName: String {
        switch preset {
        case .flat: return "minus"
        case .bassBoost: return "speaker.wave.3.fill"
        case .vocal: return "person.wave.2.fill"
        case .podcast: return "mic.fill"
        case .movie: return "film.fill"
        case .music: return "music.note"
        case .custom: return "slider.vertical.3"
        }
    }
}

struct EQBandStrip: View {
    let label: String
    let value: Double
    let isEnabled: Bool
    let height: CGFloat
    let onChange: (Double) -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(gainText(value))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(isEnabled ? bandTint : .secondary)
                .frame(height: 16)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            EQVerticalSlider(
                value: value,
                isEnabled: isEnabled,
                tint: bandTint,
                height: height,
                onChange: onChange
            )

            Text(label)
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(height: 16)
        }
        .frame(minWidth: 42)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) hertz band")
        .accessibilityValue("\(gainText(value)) dB")
    }

    private var bandTint: Color {
        if value > 0.4 { return .teal }
        if value < -0.4 { return .orange }
        return .secondary
    }
}

private struct EQVerticalSlider: View {
    let value: Double
    let isEnabled: Bool
    let tint: Color
    let height: CGFloat
    let onChange: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let trackWidth: CGFloat = 10
            let zeroY = size.height / 2
            let knobY = yPosition(for: value, height: size.height)
            let fillTop = min(zeroY, knobY)
            let fillHeight = max(4, abs(zeroY - knobY))

            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.secondary.opacity(0.14))
                    .frame(width: trackWidth)

                Rectangle()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: 34, height: 1)
                    .position(x: size.width / 2, y: zeroY)

                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isEnabled ? tint.opacity(0.90) : Color.secondary.opacity(0.35))
                    .frame(width: trackWidth, height: fillHeight)
                    .position(x: size.width / 2, y: fillTop + fillHeight / 2)

                Circle()
                    .fill(isEnabled ? Color.primary : Color.secondary)
                    .frame(width: 18, height: 18)
                    .overlay {
                        Circle()
                            .stroke(tint.opacity(isEnabled ? 0.75 : 0.25), lineWidth: 2)
                    }
                    .shadow(color: tint.opacity(isEnabled ? 0.25 : 0), radius: 4)
                    .position(x: size.width / 2, y: knobY)
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard isEnabled else { return }
                        updateValue(from: gesture.location.y, height: size.height)
                    }
            )
        }
        .frame(width: 42, height: height)
        .background(ConsolePalette.inset.opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        }
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            switch direction {
            case .increment:
                onChange(min(12, value + 1))
            case .decrement:
                onChange(max(-12, value - 1))
            @unknown default:
                break
            }
        }
    }

    private func yPosition(for value: Double, height: CGFloat) -> CGFloat {
        let normalized = CGFloat((value + 12) / 24)
        return height * (1 - min(1, max(0, normalized)))
    }

    private func updateValue(from y: CGFloat, height: CGFloat) {
        let clampedY = min(height, max(0, y))
        let normalized = 1 - Double(clampedY / max(1, height))
        let nextValue = -12 + normalized * 24
        onChange(nextValue)
    }
}

struct EQCurveView: View {
    let bands: [Double]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(ConsolePalette.inset.opacity(0.85))

                EQGrid()
                    .stroke(.white.opacity(0.07), lineWidth: 1)

                zeroLine(in: geometry.size)
                    .stroke(.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                curvePath(in: geometry.size)
                    .stroke(
                        LinearGradient(
                            colors: [.orange, .teal, .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )

                curvePoints(in: geometry.size)

                VStack {
                    HStack {
                        Text("+12")
                        Spacer()
                        Text("dB")
                    }
                    Spacer()
                    HStack {
                        Text("0")
                        Spacer()
                    }
                    Spacer()
                    HStack {
                        Text("-12")
                        Spacer()
                        Text("Hz")
                    }
                }
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Equalizer curve preview")
    }

    private func curvePath(in size: CGSize) -> Path {
        Path { path in
            guard !bands.isEmpty else { return }
            for index in bands.indices {
                let point = point(for: index, in: size)
                if index == bands.startIndex {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
        }
    }

    private func zeroLine(in size: CGSize) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
        }
    }

    private func point(for index: Int, in size: CGSize) -> CGPoint {
        let x = size.width * CGFloat(index) / CGFloat(max(1, bands.count - 1))
        let normalized = CGFloat((bands[index] + 12) / 24)
        let y = size.height * (1 - normalized)
        return CGPoint(x: x, y: y)
    }

    @ViewBuilder
    private func curvePoints(in size: CGSize) -> some View {
        ForEach(bands.indices, id: \.self) { index in
            Circle()
                .fill(.teal)
                .frame(width: 6, height: 6)
                .position(point(for: index, in: size))
        }
    }
}

private struct EQGrid: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            for index in 1..<4 {
                let y = rect.height * CGFloat(index) / 4
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
            for index in 1..<10 {
                let x = rect.width * CGFloat(index) / 10
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
        }
    }
}

private func gainText(_ value: Double) -> String {
    let snapped = abs(value) < 0.05 ? 0 : value
    return String(format: "%+.1f", snapped)
}
