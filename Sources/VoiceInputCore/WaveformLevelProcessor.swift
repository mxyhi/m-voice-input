public struct WaveformLevelProcessor {
    public struct RandomSource: Sendable {
        private let nextValue: @Sendable () -> Double

        public static let live = Self {
            Double.random(in: -1 ... 1)
        }

        public init(_ nextValue: @escaping @Sendable () -> Double = { Double.random(in: -1 ... 1) }) {
            self.nextValue = nextValue
        }

        public static func constant(_ value: Double) -> Self {
            Self { value }
        }

        public func nextSignedUnit() -> Double {
            Self.clamp(nextValue(), lowerBound: -1, upperBound: 1)
        }

        private static func clamp(_ value: Double, lowerBound: Double, upperBound: Double) -> Double {
            Swift.max(lowerBound, Swift.min(upperBound, value))
        }
    }

    private static let barWeights = [0.5, 0.8, 1.0, 0.75, 0.55]
    public static let barCount = 5
    public static let defaultMinimumVisibleLevel = 0.18

    private let attackFactor: Double
    private let releaseFactor: Double
    private let minimumVisibleLevel: Double
    private let jitterAmplitude: Double
    private let randomSource: RandomSource
    private var smoothedLevels: [Double]

    public init(
        randomSource: RandomSource = .live,
        minimumVisibleLevel: Double = Self.defaultMinimumVisibleLevel,
        attackFactor: Double = 0.4,
        releaseFactor: Double = 0.15,
        jitterAmplitude: Double = 0.04
    ) {
        self.randomSource = randomSource
        self.minimumVisibleLevel = minimumVisibleLevel
        self.attackFactor = attackFactor
        self.releaseFactor = releaseFactor
        self.jitterAmplitude = jitterAmplitude
        smoothedLevels = Array(
            repeating: minimumVisibleLevel,
            count: Self.barWeights.count
        )
    }

    public mutating func process(rms: Double) -> [Double] {
        let normalizedRMS = Self.clamp(rms, lowerBound: 0, upperBound: 1)

        return Self.barWeights.enumerated().map { index, weight in
            let targetLevel = Swift.max(minimumVisibleLevel, normalizedRMS * weight)
            let currentLevel = smoothedLevels[index]
            let smoothingFactor = targetLevel > currentLevel ? attackFactor : releaseFactor
            let smoothedLevel = currentLevel + ((targetLevel - currentLevel) * smoothingFactor)

            // 把平滑后的基础值存下来，抖动只作用于当前帧，避免随机噪声被累计进状态。
            let clampedLevel = Self.clamp(
                smoothedLevel,
                lowerBound: minimumVisibleLevel,
                upperBound: 1
            )
            smoothedLevels[index] = clampedLevel

            let jitterFactor = 1 + (randomSource.nextSignedUnit() * jitterAmplitude)
            return Self.clamp(
                clampedLevel * jitterFactor,
                lowerBound: minimumVisibleLevel,
                upperBound: 1
            )
        }
    }

    private static func clamp(_ value: Double, lowerBound: Double, upperBound: Double) -> Double {
        Swift.max(lowerBound, Swift.min(upperBound, value))
    }
}

public extension Array where Element == Double {
    static var idle: Self {
        Array(
            repeating: WaveformLevelProcessor.defaultMinimumVisibleLevel,
            count: WaveformLevelProcessor.barCount
        )
    }
}
