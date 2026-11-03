import Foundation
@testable import LeagueKit
import Testing

struct ProcessArgumentsTests {
    /// Builds a KERN_PROCARGS2 buffer: argc, exec path, padding, args, environment.
    private func procargs(_ arguments: [String]) -> [UInt8] {
        var bytes = withUnsafeBytes(of: Int32(arguments.count).littleEndian) { Array($0) }
        bytes += Array("/Applications/League of Legends.app/x/LeagueClientUx".utf8) + [0, 0, 0, 0]
        for argument in arguments {
            bytes += Array(argument.utf8) + [0]
        }
        bytes += Array("HOME=/Users/anon".utf8) + [0]
        return bytes
    }

    @Test func parsesArgumentsWithSpaces() throws {
        let input = [
            "/path/LeagueClientUx",
            "--app-port=49215",
            "--install-directory=/Applications/League of Legends.app/Contents/LoL"
        ]
        let parsed = try ProcessArguments.parse(procargs2: procargs(input))
        #expect(parsed == input)
        #expect(ProcessArguments.value(of: "install-directory", in: parsed)
            == "/Applications/League of Legends.app/Contents/LoL")
    }

    @Test func rejectsTruncatedBuffer() {
        var bytes = procargs(["a", "b"])
        bytes.removeLast(30)
        #expect(throws: ProcessArgumentsError.malformed) { try ProcessArguments.parse(procargs2: bytes) }
        #expect(throws: ProcessArgumentsError.malformed) { try ProcessArguments.parse(procargs2: [1]) }
    }

    @Test func valueRequiresExactPrefix() {
        let arguments = ["--riotclient-app-port=65457", "--app-port=49215"]
        #expect(ProcessArguments.value(of: "app-port", in: arguments) == "49215")
        #expect(ProcessArguments.value(of: "missing", in: arguments) == nil)
    }

    @Test func readsOwnProcess() throws {
        let arguments = try ProcessArguments.read(pid: getpid())
        #expect(!arguments.isEmpty)
    }
}

struct LCUCredentialsTests {
    let arguments = [
        "--app-port=49215",
        "--remoting-auth-token=fake-pw",
        "--riotclient-auth-token=other",
        "--riotgamesapi-settings=e30="
    ]

    @Test func fromArguments() {
        let credentials = LCUCredentials(arguments: arguments)
        #expect(credentials == LCUCredentials(port: 49215, password: "fake-pw"))
        #expect(credentials?.basicAuthorization == "Basic " + Data("riot:fake-pw".utf8).base64EncodedString())
    }

    @Test func descriptionRedactsPassword() {
        let description = String(describing: LCUCredentials(port: 1, password: "fake-pw"))
        #expect(!description.contains("fake-pw"))
    }

    @Test func rejectsMissingOrInvalidValues() {
        #expect(LCUCredentials(arguments: ["--app-port=49215"]) == nil)
        #expect(LCUCredentials(arguments: ["--app-port=0", "--remoting-auth-token=x"]) == nil)
        #expect(LCUCredentials(arguments: ["--app-port=abc", "--remoting-auth-token=x"]) == nil)
    }
}

struct LockfileTests {
    @Test func parsesRecordedFormatWithoutNewline() throws {
        let lockfile = try #require(Lockfile(contents: "LeagueClient:37210:49215:pw-123:https"))
        #expect(lockfile.pid == 37210)
        #expect(lockfile.credentials == LCUCredentials(port: 49215, password: "pw-123"))
        #expect(lockfile.scheme == "https")
    }

    @Test func rejectsGarbage() {
        #expect(Lockfile(contents: "") == nil)
        #expect(Lockfile(contents: "LeagueClient:1:2:pw") == nil)
        #expect(Lockfile(contents: "LeagueClient:x:49215:pw:https") == nil)
        #expect(Lockfile(contents: "LeagueClient:1:49215::https") == nil)
    }
}

struct CredentialResolverTests {
    private let installArgs = ["--install-directory=/Apps/League of Legends.app/Contents/LoL"]
    private let lockfile = "LeagueClient:42:50000:from-lockfile:https"

    @Test func prefersProcessArguments() {
        let resolver = CredentialResolver(
            readArguments: { _ in ["--app-port=1234", "--remoting-auth-token=t"] },
            readFile: { _ in Issue.record("lockfile read"); return nil },
            isAlive: { _ in true }
        )
        #expect(resolver.resolve(clientUxPID: 1) == LCUCredentials(port: 1234, password: "t"))
    }

    @Test func fallsBackToLockfileInInstallDirectory() {
        let lockfile = lockfile
        let resolver = CredentialResolver(
            readArguments: { [installArgs] _ in installArgs },
            readFile: { url in
                url.path == "/Apps/League of Legends.app/Contents/LoL/lockfile"
                    ? lockfile : nil
            },
            isAlive: { $0 == 42 }
        )
        #expect(resolver.resolve(clientUxPID: 1) == LCUCredentials(port: 50000, password: "from-lockfile"))
    }

    @Test func ignoresStaleLockfile() {
        let lockfile = lockfile
        let resolver = CredentialResolver(
            readArguments: { [installArgs] _ in installArgs },
            readFile: { _ in lockfile },
            isAlive: { _ in false }
        )
        #expect(resolver.resolve(clientUxPID: 1) == nil)
    }

    @Test func usesBundleDirectoryWhenArgumentsAreUnreadable() {
        let lockfile = lockfile
        let resolver = CredentialResolver(
            readArguments: { _ in throw ProcessArgumentsError.malformed },
            readFile: { $0.path == "/fallback/lockfile" ? lockfile : nil },
            isAlive: { _ in true }
        )
        let credentials = resolver.resolve(clientUxPID: 1, installDirectory: URL(fileURLWithPath: "/fallback"))
        #expect(credentials?.port == 50000)
    }
}
