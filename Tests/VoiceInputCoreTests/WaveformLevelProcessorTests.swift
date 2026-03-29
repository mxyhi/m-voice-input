import Testing
@testable import VoiceInputCore

struct WaveformLevelProcessorTests {
    @Test
    func lowInput_keepsBarsVisible() {
        var processor = WaveformLevelProcessor(randomSource: .constant(0))

        let levels = processor.process(rms: 0.0)

        #expect(levels.count == 5)
        #expect(levels.allSatisfy { $0 >= 0.18 })
    }

    @Test
    func highInput_emphasizesCenterBars() {
        var processor = WaveformLevelProcessor(randomSource: .constant(0))

        let levels = processor.process(rms: 0.9)

        #expect(levels[2] > levels[0])
        #expect(levels[2] > levels[4])
        #expect(levels[1] > levels[0])
    }

    @Test
    func releaseSmoothing_decaysGraduallyInsteadOfDroppingImmediately() {
        var processor = WaveformLevelProcessor(randomSource: .constant(0))
        _ = processor.process(rms: 1.0)

        let firstDecay = processor.process(rms: 0.0)
        let secondDecay = processor.process(rms: 0.0)

        #expect(firstDecay[2] > 0.3)
        #expect(secondDecay[2] < firstDecay[2])
        #expect(secondDecay[2] > 0.18)
    }
}
