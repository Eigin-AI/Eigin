import Darwin
import Foundation

/// Abstracts device hardware queries so services stay testable.
protocol DeviceInfoService: Sendable {
    /// Capacity iOS can make available for user-requested downloads, in bytes:
    /// purgeable data included — the figure iPhone Storage shows. Nil when the
    /// query fails.
    func availableDiskSpaceBytes() -> Int64?
    /// Total physical RAM installed in the device, in bytes.
    func physicalMemoryBytes() -> UInt64
    /// Hardware model identifier, e.g. "iPhone16,1".
    func deviceIdentifier() -> String
    /// Operating system version string, e.g. "18.0".
    func systemVersion() -> String
    /// App build number from `CFBundleVersion`, e.g. "47".
    func appBuildVersion() -> String
    /// App display name from `CFBundleName`, e.g. "Eigin".
    func appName() -> String
    /// App marketing version from `CFBundleShortVersionString`, e.g. "1.0".
    func appVersion() -> String
}

/// Production implementation that queries hardware directly.
struct DefaultDeviceInfoService: DeviceInfoService {
    func availableDiskSpaceBytes() -> Int64? {
        // Queried on the home directory, which shares the data volume with
        // Documents where downloaded models land.
        try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ).volumeAvailableCapacityForImportantUsage
    }

    func physicalMemoryBytes() -> UInt64 {
        ProcessInfo.processInfo.physicalMemory
    }

    func deviceIdentifier() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [UInt8](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        let identifier = String(decoding: machine.dropLast(), as: UTF8.self)
#if targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? identifier
#else
        return identifier
#endif
    }

    func systemVersion() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        if v.patchVersion == 0 {
            return "\(v.majorVersion).\(v.minorVersion)"
        }
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    func appName() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? ""
    }

    func appVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    func appBuildVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }
}
