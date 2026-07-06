@testable import Citration
import Testing

@Suite("Citration Design System Tokens")
struct DesignTokensTests {
    @Test("spacing scale is increasing")
    func spacingScaleIsIncreasing() {
        #expect(BCSpacing.small < BCSpacing.medium)
        #expect(BCSpacing.medium < BCSpacing.large)
    }

    @Test("radius scale is increasing")
    func radiusScaleIsIncreasing() {
        #expect(BCRadius.small < BCRadius.medium)
        #expect(BCRadius.medium < BCRadius.large)
    }
}
