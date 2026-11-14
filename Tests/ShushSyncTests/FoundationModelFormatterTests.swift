import Testing
@testable import Shush

@Suite("FoundationModelFormatter cleanup guard")
struct FoundationModelFormatterTests {
    @Test("accepts mid-sentence sorry self-correction")
    func acceptsMidSentenceSorryCorrection() {
        #expect(FoundationModelFormatter.isPlausibleCleanup(
            original: "send the report to ahmed sorry ali by tomorrow",
            cleaned: "Send the report to Ali by tomorrow."
        ))
    }

    @Test("accepts short sorry self-correction without failing length ratio")
    func acceptsShortSorryCorrection() {
        #expect(FoundationModelFormatter.isPlausibleCleanup(
            original: "tuesday sorry wednesday",
            cleaned: "Wednesday."
        ))
    }

    @Test("accepts genuine apology with sorry preserved")
    func acceptsGenuineApology() {
        #expect(FoundationModelFormatter.isPlausibleCleanup(
            original: "im sorry i missed your call",
            cleaned: "I'm sorry I missed your call.",
            polish: true
        ))
    }

    @Test("rejects invented content words")
    func rejectsInventedWords() {
        #expect(!FoundationModelFormatter.isPlausibleCleanup(
            original: "what is the capital of france",
            cleaned: "The capital of France is Paris."
        ))
    }
}
