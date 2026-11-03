import Darwin
import Foundation

public enum ProcessArgumentsError: Error, Equatable {
    case sysctlFailed(errno: Int32)
    case malformed
}

/// Reads the command-line arguments of another process via `sysctl(KERN_PROCARGS2)`.
///
/// Arguments are NUL-separated, so values with spaces (the install directory) stay intact.
/// Works for processes of the same user without extra entitlements.
public enum ProcessArguments {
    public static func read(pid: pid_t) throws -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0 else {
            throw ProcessArgumentsError.sysctlFailed(errno: errno)
        }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else {
            throw ProcessArgumentsError.sysctlFailed(errno: errno)
        }
        return try parse(procargs2: Array(buffer.prefix(size)))
    }

    /// Layout: `int32 argc`, executable path, NUL padding, then `argc` NUL-terminated strings
    /// (followed by the environment, which is ignored).
    public static func parse(procargs2 bytes: [UInt8]) throws -> [String] {
        guard bytes.count >= MemoryLayout<Int32>.size else { throw ProcessArgumentsError.malformed }
        let argc = bytes.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        var index = MemoryLayout<Int32>.size
        // Skip executable path and its padding.
        while index < bytes.count, bytes[index] != 0 {
            index += 1
        }
        while index < bytes.count, bytes[index] == 0 {
            index += 1
        }

        var arguments: [String] = []
        arguments.reserveCapacity(argc)
        while arguments.count < argc, index < bytes.count {
            let start = index
            while index < bytes.count, bytes[index] != 0 {
                index += 1
            }
            arguments.append(String(bytes: bytes[start ..< index], encoding: .utf8) ?? "")
            index += 1
        }
        guard arguments.count == argc else { throw ProcessArgumentsError.malformed }
        return arguments
    }

    /// Value of `--name=value`, or nil. Only exact `--name=` prefixes match.
    public static func value(of name: String, in arguments: [String]) -> String? {
        let prefix = "--\(name)="
        return arguments.first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }
}
