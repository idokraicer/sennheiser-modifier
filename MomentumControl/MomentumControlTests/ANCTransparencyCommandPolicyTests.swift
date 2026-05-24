import Testing
@testable import MomentumControl

@Suite("ANC Transparency Command Policy Tests")
struct ANCTransparencyCommandPolicyTests {

    @Test("Delays transparency level when entering transparency during drag")
    func delaysTransparencyLevelWhenCrossingZones() {
        let mode = ANCTransparencyCommandPolicy.levelSendMode(
            zone: .transparency,
            didChangeZone: true,
            isCommit: false,
            isAwaitingTransparencyActivation: true
        )

        #expect(mode == .delayedForModeActivation)
    }

    @Test("Delays commit while transparency activation is still pending")
    func delaysCommitDuringPendingTransparencyActivation() {
        let mode = ANCTransparencyCommandPolicy.levelSendMode(
            zone: .transparency,
            didChangeZone: false,
            isCommit: true,
            isAwaitingTransparencyActivation: true
        )

        #expect(mode == .delayedForModeActivation)
    }

    @Test("Uses debounced sends while dragging within the same zone")
    func debouncesDraggingWithinSameZone() {
        let mode = ANCTransparencyCommandPolicy.levelSendMode(
            zone: .transparency,
            didChangeZone: false,
            isCommit: false,
            isAwaitingTransparencyActivation: false
        )

        #expect(mode == .debounced)
    }

    @Test("Uses immediate send for stable commit")
    func sendsImmediateLevelForStableCommit() {
        let mode = ANCTransparencyCommandPolicy.levelSendMode(
            zone: .transparency,
            didChangeZone: false,
            isCommit: true,
            isAwaitingTransparencyActivation: false
        )

        #expect(mode == .immediate)
    }
}
