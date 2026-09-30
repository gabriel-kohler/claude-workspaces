import Darwin
import Foundation

struct Usage: Equatable {
    /// Physical footprint, the number Activity Monitor calls "Memory".
    var memory: UInt64
    /// Percent of one core over the last interval.
    var cpu: Double

    static let zero = Usage(memory: 0, cpu: 0)
}

/// Reads memory and CPU straight from the kernel (`proc_pid_rusage`), without spawning anything.
/// A session's usage is Claude plus everything under it (its MCP servers and tool commands).
final class UsageMonitor {
    private var lastCPU: [pid_t: (nanos: UInt64, at: UInt64)] = [:]
    private let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    func usage(ofTree root: pid_t) -> Usage {
        var pids = [root]
        var index = 0
        while index < pids.count, pids.count < 256 {
            pids += ProcessTree.children(of: pids[index])
            index += 1
        }
        var memory: UInt64 = 0
        var cpuTicks: UInt64 = 0
        for pid in pids {
            guard let info = Self.rusage(pid) else { continue }
            memory += info.ri_phys_footprint
            cpuTicks += info.ri_user_time + info.ri_system_time
        }
        // rusage times are in Mach absolute units on Apple silicon.
        let nanos = cpuTicks * UInt64(timebase.numer) / UInt64(timebase.denom)
        let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        var cpu = 0.0
        if let last = lastCPU[root], now > last.at, nanos >= last.nanos {
            cpu = Double(nanos - last.nanos) / Double(now - last.at) * 100
        }
        lastCPU[root] = (nanos, now)
        return Usage(memory: memory, cpu: cpu)
    }

    func usageOfThisApp() -> Usage { usage(ofSelf: getpid()) }

    private func usage(ofSelf pid: pid_t) -> Usage {
        guard let info = Self.rusage(pid) else { return .zero }
        let nanos = (info.ri_user_time + info.ri_system_time) * UInt64(timebase.numer) / UInt64(timebase.denom)
        let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        var cpu = 0.0
        let key = -pid
        if let last = lastCPU[key], now > last.at, nanos >= last.nanos {
            cpu = Double(nanos - last.nanos) / Double(now - last.at) * 100
        }
        lastCPU[key] = (nanos, now)
        return Usage(memory: info.ri_phys_footprint, cpu: cpu)
    }

    func forget(_ root: pid_t) { lastCPU[root] = nil }

    private static func rusage(_ pid: pid_t) -> rusage_info_v4? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        return result == 0 ? info : nil
    }
}

enum ByteFormat {
    /// "182 MB", "1,4 GB".
    static func short(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024).replacingOccurrences(of: ".", with: ",")
        }
        return "\(Int(mb.rounded())) MB"
    }

    static func cpu(_ percent: Double) -> String {
        if percent < 0.1 { return "0%" }
        if percent < 10 { return String(format: "%.1f%%", percent).replacingOccurrences(of: ".", with: ",") }
        return "\(Int(percent.rounded()))%"
    }
}
