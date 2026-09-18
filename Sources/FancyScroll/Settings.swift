import Foundation
import Combine

enum HapticIntensity: String, CaseIterable, Identifiable, Codable {
    case light, medium, strong
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum EndPattern: String, CaseIterable, Identifiable, Codable {
    case thud, doubleBump, tripleBump
    var id: String { rawValue }
    var label: String {
        switch self {
        case .thud: return "Firm thud"
        case .doubleBump: return "Double bump"
        case .tripleBump: return "Triple bump"
        }
    }
    /// Number of pulses and the gap between them.
    var pulses: Int {
        switch self {
        case .thud: return 1
        case .doubleBump: return 2
        case .tripleBump: return 3
        }
    }
}

enum EnginePreference: String, CaseIterable, Identifiable, Codable {
    /// Use the trackpad actuator directly when available (stronger, works while finger is lifted),
    /// otherwise fall back to the public NSHapticFeedbackManager.
    case auto
    /// Always use NSHapticFeedbackManager.
    case system
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return "Auto (direct actuator when available)"
        case .system: return "System haptics only"
        }
    }
}

/// User-facing preferences, persisted in UserDefaults.
final class Settings: ObservableObject {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "enabled") } }

    // Step ticks
    @Published var stepsEnabled: Bool { didSet { defaults.set(stepsEnabled, forKey: "stepsEnabled") } }
    /// Points of scroll travel per tick.
    @Published var stepSize: Double { didSet { defaults.set(stepSize, forKey: "stepSize") } }
    @Published var stepIntensity: HapticIntensity { didSet { defaults.set(stepIntensity.rawValue, forKey: "stepIntensity") } }
    @Published var horizontalSteps: Bool { didSet { defaults.set(horizontalSteps, forKey: "horizontalSteps") } }
    /// Keep ticking while the finger is lifted and content is coasting.
    @Published var feedbackDuringMomentum: Bool { didSet { defaults.set(feedbackDuringMomentum, forKey: "feedbackDuringMomentum") } }

    // End of page
    @Published var endEnabled: Bool { didSet { defaults.set(endEnabled, forKey: "endEnabled") } }
    @Published var endIntensity: HapticIntensity { didSet { defaults.set(endIntensity.rawValue, forKey: "endIntensity") } }
    @Published var endPattern: EndPattern { didSet { defaults.set(endPattern.rawValue, forKey: "endPattern") } }

    // Engine
    @Published var engine: EnginePreference { didSet { defaults.set(engine.rawValue, forKey: "engine") } }

    private init() {
        defaults.register(defaults: [
            "enabled": true,
            "stepsEnabled": true,
            "stepSize": 40.0,
            "stepIntensity": HapticIntensity.light.rawValue,
            "horizontalSteps": true,
            "feedbackDuringMomentum": false,
            "endEnabled": true,
            "endIntensity": HapticIntensity.strong.rawValue,
            "endPattern": EndPattern.doubleBump.rawValue,
            "engine": EnginePreference.auto.rawValue,
        ])

        enabled = defaults.bool(forKey: "enabled")
        stepsEnabled = defaults.bool(forKey: "stepsEnabled")
        stepSize = defaults.double(forKey: "stepSize")
        stepIntensity = HapticIntensity(rawValue: defaults.string(forKey: "stepIntensity") ?? "") ?? .light
        horizontalSteps = defaults.bool(forKey: "horizontalSteps")
        feedbackDuringMomentum = defaults.bool(forKey: "feedbackDuringMomentum")
        endEnabled = defaults.bool(forKey: "endEnabled")
        endIntensity = HapticIntensity(rawValue: defaults.string(forKey: "endIntensity") ?? "") ?? .strong
        endPattern = EndPattern(rawValue: defaults.string(forKey: "endPattern") ?? "") ?? .doubleBump
        engine = EnginePreference(rawValue: defaults.string(forKey: "engine") ?? "") ?? .auto
    }
}
