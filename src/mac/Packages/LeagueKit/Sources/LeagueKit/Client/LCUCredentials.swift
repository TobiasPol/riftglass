import Darwin
import Foundation

/// Port + remoting password of a running LCU. `description` never reveals the password.
public struct LCUCredentials: Sendable, Equatable, CustomStringConvertible {
    public let port: Int
    public let password: String

    public init(port: Int, password: String) {
        self.port = port
        self.password = password
    }

    /// From `LeagueClientUx` arguments (`--app-port`, `--remoting-auth-token`).
    /// `--riotgamesapi-settings` carries other tokens and is deliberately never read.
    public init?(arguments: [String]) {
        guard let portString = ProcessArguments.value(of: "app-port", in: arguments),
              let port = Int(portString), (1 ... 65535).contains(port),
              let token = ProcessArguments.value(of: "remoting-auth-token", in: arguments),
              !token.isEmpty
        else { return nil }
        self.init(port: port, password: token)
    }

    public var basicAuthorization: String {
        "Basic " + Data("riot:\(password)".utf8).base64EncodedString()
    }

    public var description: String {
        "LCUCredentials(port: \(port), password: <redacted>)"
    }
}

/// Contents of `<install-directory>/lockfile`: `name:pid:port:password:protocol` (no trailing newline).
public struct Lockfile: Sendable, Equatable {
    public let processName: String
    public let pid: pid_t
    public let credentials: LCUCredentials
    public let scheme: String

    public init?(contents: String) {
        let parts = contents.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 5, let pid = pid_t(parts[1]), let port = Int(parts[2]),
              (1 ... 65535).contains(port), !parts[3].isEmpty
        else { return nil }
        processName = String(parts[0])
        self.pid = pid
        credentials = LCUCredentials(port: port, password: String(parts[3]))
        scheme = String(parts[4])
    }
}

/// Resolves LCU credentials: process arguments first, lockfile as fallback.
public struct CredentialResolver: Sendable {
    public typealias ArgumentReader = @Sendable (pid_t) throws -> [String]
    public typealias FileReader = @Sendable (URL) -> String?
    public typealias LivenessCheck = @Sendable (pid_t) -> Bool

    private let readArguments: ArgumentReader
    private let readFile: FileReader
    private let isAlive: LivenessCheck

    public init(
        readArguments: @escaping ArgumentReader = ProcessArguments.read,
        readFile: @escaping FileReader = { try? String(contentsOf: $0, encoding: .utf8) },
        isAlive: @escaping LivenessCheck = { kill($0, 0) == 0 }
    ) {
        self.readArguments = readArguments
        self.readFile = readFile
        self.isAlive = isAlive
    }

    /// - Parameter installDirectory: fallback when the arguments cannot be read, e.g. the parent
    ///   folder of the `LeagueClientUx` bundle (`NSRunningApplication.bundleURL`).
    public func resolve(clientUxPID: pid_t, installDirectory: URL? = nil) -> LCUCredentials? {
        let arguments = (try? readArguments(clientUxPID)) ?? []
        if let credentials = LCUCredentials(arguments: arguments) {
            return credentials
        }
        let directory = ProcessArguments.value(of: "install-directory", in: arguments)
            .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? installDirectory
        return directory.flatMap(lockfileCredentials(in:))
    }

    /// The lockfile survives a client shutdown, so its PID must still be alive.
    private func lockfileCredentials(in directory: URL) -> LCUCredentials? {
        guard let contents = readFile(directory.appendingPathComponent("lockfile")),
              let lockfile = Lockfile(contents: contents),
              isAlive(lockfile.pid)
        else { return nil }
        return lockfile.credentials
    }
}
