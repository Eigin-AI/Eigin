import Darwin
import Foundation

/// Abstracts device hardware queries so services stay testable.
protocol DeviceInfoService: Sendable {
    /// Available free space on the device's primary file system, in bytes.
    func freeDiskSpaceBytes() -> Int64?
    /// Total physical RAM installed in the device, in bytes.
    func physicalMemoryBytes() -> UInt64
    /// Hardware model identifier, e.g. "iPhone16,1".
    func deviceIdentifier() -> String
    /// Operating system version string, e.g. "18.0".
    func systemVersion() -> String
}

/// Production implementation that queries hardware directly.
struct DefaultDeviceInfoService: DeviceInfoService {
    func freeDiskSpaceBytes() -> Int64? {
        (try? FileManager.default.attributesOfFileSystem(
            forPath: NSHomeDirectory()
        )[.systemFreeSize]) as? Int64
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
}
