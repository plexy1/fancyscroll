import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject private var settings: Settings
    @EnvironmentObject private var monitor: ScrollMonitor

    @State private var accessibilityTrusted = ScrollEdgeDetector.isTrusted
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?

    private let poll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            stepsSection
            Divider()
            endSection
            Divider()
            engineSection
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 340)
        .onReceive(poll) { _ in
            accessibilityTrusted = ScrollEdgeDetector.isTrusted
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            Image(systemName: "hand.tap.fill")
                .font(.title2)
                .foregroundStyle(settings.enabled ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("FancyScroll").font(.headline)
                Text(settings.enabled ? "Haptics on" : "Paused")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $settings.enabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Scroll steps", systemImage: "dial.medium", isOn: $settings.stepsEnabled)

            Group {
                HStack {
                    Text("Every")
                    Slider(value: $settings.stepSize, in: 10...200, step: 5)
                    Text("\(Int(settings.stepSize)) pt")
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }
                Text(stepDescription)
                    .font(.caption).foregroundStyle(.secondary)

                Picker("Feel", selection: $settings.stepIntensity) {
                    ForEach(HapticIntensity.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                Toggle("Tick on horizontal scrolling", isOn: $settings.horizontalSteps)
                Toggle("Keep ticking while content coasts (finger lifted)", isOn: $settings.feedbackDuringMomentum)

                HStack {
                    Button("Test tick") { Haptics.shared.tick(settings.stepIntensity) }
                    Spacer()
                    Text("\(monitor.tickCount) ticks so far")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
            .disabled(!settings.stepsEnabled || !settings.enabled)
        }
    }

    private var stepDescription: String {
        switch settings.stepSize {
        case ..<25: return "Very fine — feels like a ratchet."
        case ..<60: return "Fine — a click every few lines of text."
        case ..<120: return "Medium — roughly one click per paragraph."
        default: return "Coarse — a click every screenful or so."
        }
    }

    private var endSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("End of page", systemImage: "arrow.down.to.line", isOn: $settings.endEnabled)

            Group {
                Picker("Pattern", selection: $settings.endPattern) {
                    ForEach(EndPattern.allCases) { Text($0.label).tag($0) }
                }
                Picker("Strength", selection: $settings.endIntensity) {
                    ForEach(HapticIntensity.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack {
                    Button("Test bump") { Haptics.shared.play(settings.endPattern, intensity: settings.endIntensity) }
                    Spacer()
                    if let edge = monitor.lastEdge {
                        Text("\(monitor.edgeHitCount) hits · last: \(label(for: edge))")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            .disabled(!settings.endEnabled || !settings.enabled)

            accessibilityRow
        }
    }

    @ViewBuilder
    private var accessibilityRow: some View {
        if accessibilityTrusted {
            Label("Accessibility access granted", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Label("Needs Accessibility access to know where a page ends.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                HStack {
                    Button("Grant access…") { ScrollEdgeDetector.requestTrust() }
                    Button("Open System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                .controlSize(.small)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.08)))
        }
    }

    private var engineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Haptic engine", systemImage: "waveform.path").font(.subheadline.weight(.semibold))
            Picker("", selection: $settings.engine) {
                ForEach(EnginePreference.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            Text(engineStatus)
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var engineStatus: String {
        let haptics = Haptics.shared
        if haptics.actuatorAvailable {
            return "Using: \(haptics.activeEngineName)"
        }
        return "Direct actuator not found on this Mac — using system haptics."
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLogin },
                set: { setLaunchAtLogin($0) }
            ))
            if let launchError {
                Text(launchError).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
                    .font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button("Quit FancyScroll") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
    }

    // MARK: Helpers

    private func sectionTitle(_ title: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Label(title, systemImage: systemImage).font(.subheadline.weight(.semibold))
            Spacer()
            Toggle("", isOn: isOn).toggleStyle(.switch).labelsHidden().controlSize(.small)
        }
    }

    private func label(for edge: ScrollEdge) -> String {
        switch edge {
        case .top: return "top"
        case .bottom: return "bottom"
        case .left: return "left"
        case .right: return "right"
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = on
            launchError = nil
        } catch {
            launchError = "Couldn't update login item: \(error.localizedDescription)"
        }
    }
}
