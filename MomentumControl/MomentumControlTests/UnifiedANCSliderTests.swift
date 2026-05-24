import Testing
@testable import MomentumControl

@Suite("Unified ANC Slider Tests")
struct UnifiedANCSliderTests {

    @Test("Rejects vertical-dominant scroll gestures")
    func rejectsVerticalDominantScroll() {
        #expect(
            ANCSliderScrollPolicy.shouldBeginHorizontalScroll(
                horizontalDelta: 2,
                verticalDelta: 8
            ) == false
        )
    }

    @Test("Rejects tiny horizontal trackpad noise")
    func rejectsTinyHorizontalNoise() {
        #expect(
            ANCSliderScrollPolicy.shouldBeginHorizontalScroll(
                horizontalDelta: 0.5,
                verticalDelta: 0.1
            ) == false
        )
    }

    @Test("Accepts clearly horizontal scroll gestures")
    func acceptsHorizontalScroll() {
        #expect(
            ANCSliderScrollPolicy.shouldBeginHorizontalScroll(
                horizontalDelta: 6,
                verticalDelta: 2
            ) == true
        )
    }
}
