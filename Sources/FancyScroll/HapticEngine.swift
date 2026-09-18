import AppKit
import IOKit

/// Something that can make the trackpad click.
protocol HapticEngine: AnyObject {
    var name: String { get }
    func pulse(_ intensity: HapticIntensity)
}

// MARK: - Public API engine

/// Uses NSHapticFeedbackManager. Always available on Force Touch trackpads, but the
/// three patterns are fairly subtle and are only felt while a finger is on the pad.
final class SystemHapticEngine: HapticEngine {
    let name = "System (NSHapticFeedbackManager)"

    func pulse(_ intensity: HapticIntensity) {
        let pattern: NSHapticFeedbackManager.FeedbackPattern
        switch intensity {
        case .light: pattern = .alignment
        case .medium: pattern = .generic
        case .strong: pattern = .levelChange
        }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}

// MARK: - Direct actuator engine (private MultitouchSupport.framework)

/// Drives the trackpad's actuator directly. This is the same mechanism used by apps such as
/// HapticKey. It gives a wider range of click strengths and fires even when the app is in the
/// background or the finger is lifted. Loaded with dlopen so the app still builds and runs
/// (falling back to the system engine) if the private framework changes.
final class ActuatorHapticEngine: HapticEngine {
    let name = "Direct actuator (MultitouchSupport)"

    private typealias CreateFn = @convention(c) (UInt64) -> UnsafeMutableRawPointer?
    private typealias OpenFn = @convention(c) (UnsafeMutableRawPointer) -> Int32
    private typealias ActuateFn = @convention(c) (UnsafeMutableRawPointer, Int32, UInt32, Float, Float) -> Int32

    private let actuate: ActuateFn
    private let actuators: [UnsafeMutableRawPointer]

    /// Returns nil if the framework or a working actuator can't be found.
    init?() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW),
              let createSym = dlsym(handle, "MTActuatorCreateFromDeviceID"),
              let openSym = dlsym(handle, "MTActuatorOpen"),
              let actuateSym = dlsym(handle, "MTActuatorActuate")
        else { return nil }

        let create = unsafeBitCast(createSym, to: CreateFn.self)
        let open = unsafeBitCast(openSym, to: OpenFn.self)
        actuate = unsafeBitCast(actuateSym, to: ActuateFn.self)

        var opened: [UnsafeMutableRawPointer] = []
        for deviceID in ActuatorHapticEngine.candidateDeviceIDs() {
            guard let ref = create(deviceID) else { continue }
            if open(ref) == KERN_SUCCESS {
                opened.append(ref)
            }
        }
        guard !opened.isEmpty else { return nil }
        actuators = opened
    }

    func pulse(_ intensity: HapticIntensity) {
        // Actuation IDs observed on Force Touch trackpads: 1–6 increase in strength; 15/16 are
        // the "click"/"release" pair used for Force click.
        let actuationID: Int32
        switch intensity {
        case .light: actuationID = 3
        case .medium: actuationID = 4
        case .strong: actuationID = 6
        }
        for ref in actuators {
            _ = actuate(ref, actuationID, 0, 0, 0)
        }
    }

    /// Multitouch IDs of every attached multitouch device, followed by IDs known from
    /// specific MacBook generations as a last resort.
    private static func candidateDeviceIDs() -> [UInt64] {
        var ids: [UInt64] = []

        var iterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleMultitouchDevice"), &iterator) == KERN_SUCCESS {
            var service = IOIteratorNext(iterator)
            while service != 0 {
                if let value = IORegistryEntryCreateCFProperty(service, "Multitouch ID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
                   let number = value as? NSNumber {
                    ids.append(number.uint64Value)
                }
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
        }

        let known: [UInt64] = [
            0x200000001000000, // MacBook Pro 2016/2017
            0x300000080500000, // MacBook Pro 2018+
            0x200000031000000, // Various
        ]
        for id in known where !ids.contains(id) { ids.append(id) }
        return ids
    }
}

// MARK: - Coordinator

/// Picks an engine according to the user's preference and plays multi-pulse patterns.
final class Haptics {
    static let shared = Haptics()

    private let system = SystemHapticEngine()
    private let actuator = ActuatorHapticEngine()
    private var lastPulse = DispatchTime.now()

    /// Minimum spacing between pulses so a fast scroll doesn't turn into a buzz.
    private let minInterval: UInt64 = 14_000_000 // 14 ms

    var actuatorAvailable: Bool { actuator != nil }

    private var engine: HapticEngine {
        switch Settings.shared.engine {
        case .auto: return actuator ?? system
        case .system: return system
        }
    }

    var activeEngineName: String { engine.name }

    /// Single pulse, rate-limited.
    func tick(_ intensity: HapticIntensity) {
        let now = DispatchTime.now()
        guard now.uptimeNanoseconds - lastPulse.uptimeNanoseconds >= minInterval else { return }
        lastPulse = now
        engine.pulse(intensity)
    }

    /// End-of-page pattern; bypasses the rate limiter so it always lands.
    func play(_ pattern: EndPattern, intensity: HapticIntensity) {
        lastPulse = DispatchTime.now()
        let engine = self.engine
        engine.pulse(intensity)
        guard pattern.pulses > 1 else { return }
        // Follow-up bumps are slightly lighter so the first hit reads as the "wall".
        let follow: HapticIntensity = intensity == .strong ? .medium : .light
        for i in 1..<pattern.pulses {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(70 * i)) {
                engine.pulse(follow)
            }
        }
    }
}
