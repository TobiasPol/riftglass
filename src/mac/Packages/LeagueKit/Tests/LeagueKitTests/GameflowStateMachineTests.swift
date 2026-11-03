@testable import LeagueKit
import Testing

struct GameflowStateMachineTests {
    private let client = LeagueProcesses(clientUxPID: 10, gamePID: nil)
    private let clientAndGame = LeagueProcesses(clientUxPID: 10, gamePID: 20)
    private let gameOnly = LeagueProcesses(clientUxPID: nil, gamePID: 20)

    @Test func dormantUntilClientRuns() {
        var machine = GameflowStateMachine()
        #expect(machine.mode == .dormant)
        #expect(machine.handle(.processesChanged(.none)) == nil)
        #expect(machine.handle(.processesChanged(client)) == .client)
    }

    @Test func fullMatchCycle() {
        var machine = GameflowStateMachine()
        machine.handle(.processesChanged(client))
        #expect(machine.handle(.phaseChanged(.lobby)) == nil)
        #expect(machine.handle(.phaseChanged(.champSelect)) == .champSelect)
        #expect(machine.handle(.phaseChanged(.gameStart)) == .inGame)
        #expect(machine.handle(.processesChanged(clientAndGame)) == nil)
        #expect(machine.handle(.phaseChanged(.inProgress)) == nil)
        // Game process exits before the LCU reports the end: phase still says in-game.
        #expect(machine.handle(.processesChanged(client)) == nil)
        #expect(machine.handle(.phaseChanged(.endOfGame)) == .postGame)
        #expect(machine.handle(.phaseChanged(.lobby)) == .client)
    }

    @Test func dodgeReturnsToClient() {
        var machine = GameflowStateMachine()
        machine.handle(.processesChanged(client))
        machine.handle(.phaseChanged(.champSelect))
        #expect(machine.handle(.phaseChanged(.matchmaking)) == .client)
    }

    @Test func clientClosingDuringGameKeepsInGame() {
        var machine = GameflowStateMachine()
        machine.handle(.processesChanged(clientAndGame))
        machine.handle(.phaseChanged(.inProgress))
        #expect(machine.handle(.lcuDisconnected) == nil)
        #expect(machine.handle(.processesChanged(gameOnly)) == nil)
        #expect(machine.mode == .inGame)
        #expect(machine.handle(.processesChanged(.none)) == .dormant)
    }

    @Test func terminatedInErrorResets() {
        var machine = GameflowStateMachine()
        machine.handle(.processesChanged(client))
        machine.handle(.phaseChanged(.champSelect))
        #expect(machine.handle(.phaseChanged(.terminatedInError)) == .client)
        #expect(machine.phase == .idle)
    }

    @Test func unknownPhasesAreTolerated() {
        var machine = GameflowStateMachine()
        machine.handle(.processesChanged(client))
        machine.handle(.phaseChanged(.champSelect))
        #expect(machine.handle(.phaseChanged(.unknown("NewPhase2027"))) == .client)
    }

    @Test func clientQuitClearsPhase() {
        var machine = GameflowStateMachine()
        machine.handle(.processesChanged(client))
        machine.handle(.phaseChanged(.champSelect))
        #expect(machine.handle(.processesChanged(.none)) == .dormant)
        #expect(machine.phase == nil)
    }
}
