@testable import Citration
import Testing

@Suite("Title similarity")
struct TitleSimilarityTests {
    /// The real mismatch observed against Crossref: searching for the
    /// 1966 DLI Kabul Persian book returns Routledge's "Colloquial
    /// Persian" as the top hit. It must be rejected.
    @Test("rejects a plausible but wrong top hit")
    func rejectsWrongTopHit() {
        #expect(
            !TitleSimilarity.isAcceptableMatch(
                query: "PERSIAN AN INTRODUCTION TO COLLOQUIAL KABUL PERSIAN",
                candidate: "Colloquial Persian"
            )
        )
    }

    @Test("accepts the true record despite case and word-order noise")
    func acceptsTrueRecord() {
        #expect(
            TitleSimilarity.isAcceptableMatch(
                query: "PERSIAN AN INTRODUCTION TO COLLOQUIAL KABUL PERSIAN",
                candidate: "An introduction to colloquial Kabul Persian"
            )
        )
    }

    @Test("accepts punctuation and subtitle-free variants")
    func acceptsMinorVariants() {
        #expect(
            TitleSimilarity.isAcceptableMatch(
                query: "Language Learning Theories A Student's Guide",
                candidate: "Language Learning Theories: A Student’s Guide"
            )
        )
    }

    @Test("rejects unrelated titles and empty input")
    func rejectsUnrelated() {
        #expect(!TitleSimilarity.isAcceptableMatch(query: "slow", candidate: "A Fast Paper About Nothing"))
        #expect(!TitleSimilarity.isAcceptableMatch(query: "", candidate: "Anything"))
    }
}
