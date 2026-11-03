// Records LCU WAMP events (gameflow phase + champ-select session) as JSON lines on stdout.
// Token/port come from the environment (never argv, which `ps` would expose):
//   source scripts/spike/lib.sh && load_lcu && swift scripts/spike/09-record-events.swift 60
// Spike only: trusts any certificate from 127.0.0.1. The app validates against riotgames.pem.
import Foundation

final class TrustLocalhost: NSObject, URLSessionDelegate, @unchecked Sendable {
    func urlSession(
        _: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.host == "127.0.0.1", let trust = challenge.protectionSpace.serverTrust else {
            return completionHandler(.performDefaultHandling, nil)
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

let env = ProcessInfo.processInfo.environment
guard let port = env["LCU_PORT"], let token = env["LCU_TOKEN"] else {
    FileHandle.standardError.write(Data("LCU_PORT/LCU_TOKEN missing\n".utf8))
    exit(2)
}

let seconds = Double(CommandLine.arguments.dropFirst().first ?? "60") ?? 60
guard let url = URL(string: "wss://127.0.0.1:\(port)/") else { exit(2) }
var request = URLRequest(url: url)
request.setValue("Basic " + Data("riot:\(token)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
request.setValue("wamp", forHTTPHeaderField: "Sec-WebSocket-Protocol")
let session = URLSession(configuration: .ephemeral, delegate: TrustLocalhost(), delegateQueue: nil)
let task = session.webSocketTask(with: request)
task.resume()

/// The LCU ignores subscriptions sent before its WAMP welcome ([0, session, 1, "WAMP-1.0-…"]).
let topics = (ProcessInfo.processInfo
    .environment["LCU_TOPICS"] ??
    "OnJsonApiEvent_lol-gameflow_v1_gameflow-phase,OnJsonApiEvent_lol-champ-select_v1_session").split(separator: ",")
    .map(String.init)
func subscribe() {
    for topic in topics {
        task.send(.string("[5,\"\(topic)\"]")) { error in
            if let error {
                FileHandle.standardError.write(Data("subscribe failed: \(error)\n".utf8))
            }
        }
    }
}

func receive() {
    task.receive { result in
        switch result {
        case let .success(.string(text)):
            print(text); fflush(stdout)
            if text.hasPrefix("[0,") {
                subscribe()
            }
        case .success: break
        case let .failure(error): FileHandle.standardError.write(Data("closed: \(error)\n".utf8)); exit(0)
        }
        receive()
    }
}

receive()
DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exit(0) }
dispatchMain()
