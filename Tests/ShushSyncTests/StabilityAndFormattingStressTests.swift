import AppKit
import ApplicationServices
import ShushDictionary
import Testing
@testable import Shush

@Suite("Pause, comma, fluff, and sorry correction stress tests")
struct FormattingStressTests {
    @Test(
        "RuleBasedFormatter cleans pause commas, fillers, and duplicates",
        arguments: [
            (
                "um, so, uh, when i, say silent, something silent, you put, , commas , .",
                "So, when i, say silent, something silent, you put, commas."
            ),
            (
                ", , , um, uh, erm, hello world , !",
                "Hello world!"
            ),
            (
                "uh-huh, hmm, mhm, this is, , the the test , ?",
                "This is, the test?"
            ),
            (
                "first sentence. , , um, second sentence , , .",
                "First sentence. Second sentence."
            ),
            (
                "uhm, , ,",
                ""
            ),
            (
                "we we should should probably go now",
                "We should probably go now."
            ),
            (
                "bye bye",
                "Bye bye."
            ),
            (
                "i had had enough",
                "I had had enough."
            ),
            (
                "جدا جدا",
                "جدا جدا."
            ),
            (
                "i know that that is true",
                "I know that that is true."
            ),
            (
                "well, um",
                "Well."
            ),
            (
                "i think so, um",
                "I think so."
            ),
            (
                "so, um, uh",
                "So."
            ),
            (
                "hi sarah,",
                "Hi sarah,"
            ),
        ]
    )
    func ruleBasedPauseCommasAndFillers(input: String, expected: String) async {
        let formatter = RuleBasedFormatter(removeFillerWords: true)
        let result = await formatter.format(input)
        #expect(result == expected)
    }

    @Test(
        "RuleBasedFormatter preserves real sorry phrases and apologies",
        arguments: [
            ("he said sorry again", "He said sorry again."),
            ("tell her sorry then", "Tell her sorry then."),
            ("oh sorry mate i missed that", "Oh sorry mate i missed that."),
            ("i'm sorry i missed your call", "I'm sorry i missed your call."),
            ("sorry for the delay", "Sorry for the delay."),
            ("we are sorry about that", "We are sorry about that."),
            ("sorry to bother you", "Sorry to bother you."),
        ]
    )
    func ruleBasedPreservesSorryPhrases(input: String, expected: String) async {
        let formatter = RuleBasedFormatter(removeFillerWords: true)
        let result = await formatter.format(input)
        #expect(result == expected)
    }

    @Test("RuleBasedFormatter respects removeFillerWords = false")
    func keepsFillersWhenDisabled() async {
        let formatter = RuleBasedFormatter(removeFillerWords: false)
        #expect(await formatter.format("um, hello, , world") == "Um, hello, world.")
        #expect(await formatter.format("the the test") == "The the test.")
    }

    @Test(
        "FoundationModelFormatter guard accepts valid rephrasing and sorry retractions",
        arguments: [
            (
                "send the report to the marketing team, sorry, the engineering team by friday",
                "Send the report to the engineering team by Friday.",
                true
            ),
            (
                "uh so i was thinking, like, maybe we should, uh, move the meeting to tuesday, sorry, wednesday, no wait, thursday",
                "I was thinking we should move the meeting to Thursday.",
                true
            ),
            (
                "me and sarah goes to the store yesterday and we buys milk eggs and bread",
                "Sarah and I went to the store yesterday and bought milk, eggs, and bread.",
                true
            ),
            (
                "im gonna wanna check this out later because its kinda broken",
                "I'm going to want to check this out later because it's kind of broken.",
                true
            ),
            (
                "after we implementing the sorry or rephrasing after, sorry, the app crashed many times",
                "After we implemented the rephrasing, the app crashed many times.",
                true
            ),
            ("can you send me the file", "Can you send me the file?", true),
            ("um so will it rain tomorrow", "Will it rain tomorrow?", true),
            ("is it ready? send it over", "Is it ready? Send it over.", true),
            (
                "when i pause mid sentence it puts stray commas everywhere",
                "When I pause mid-sentence, it puts stray commas everywhere.",
                true
            ),
            ("do the dishes before dinner", "Do the dishes before dinner.", true),
        ]
    )
    func foundationModelGuardAcceptsRephrasing(original: String, cleaned: String, polish: Bool) {
        #expect(FoundationModelFormatter.isPlausibleCleanup(original: original, cleaned: cleaned, polish: polish))
    }

    @Test(
        "FoundationModelFormatter guard rejects assistant replies, empty text, and hallucinations",
        arguments: [
            ("what is the capital of france", "The capital of France is Paris."),
            ("hello world", ""),
            ("hello world", "Here's the cleaned transcript: Hello world."),
            ("write a poem about cats", "Certainly, here is a poem about cats: whiskers and purrs."),
            ("tell me a joke", "As an AI, I cannot tell a joke right now."),
            ("is it going to rain tomorrow", "No, it will not rain tomorrow."),
            ("can you send me the file", "Yes, I can send you the file."),
            // Answers built only from the question's own words and the pronouns a grammar fix may add.
            ("can you send me the file", "I can send you the file."),
            ("will it rain tomorrow", "It will rain tomorrow."),
            ("can you help me", "I can help you."),
            ("are you there", "I am here."),
            ("is it ready? send it over", "It is ready. Send it over."),
        ]
    )
    func foundationModelGuardRejectsInvalidOutputs(original: String, cleaned: String) {
        #expect(!FoundationModelFormatter.isPlausibleCleanup(original: original, cleaned: cleaned, polish: true))
    }

    @Test("Live FoundationModelFormatter handles pause-commas, fluff, and sorry corrections without crashing")
    func liveFoundationModelFormatting() async {
        guard FoundationModelFormatter.isAvailable else { return }

        let formatter = FoundationModelFormatter(removeFillerWords: true, polish: true)
        let samples = [
            "send the report to ahmed, sorry, ali by tomorrow",
            "when I, say silent, something silent, you put, um, commas, which make the whole sentences not understandable",
            "I'm sorry I missed your call earlier",
            "um, like, we should meet at 3, sorry, 4 in the afternoon",
        ]

        for sample in samples {
            let output = await formatter.format(sample)
            #expect(!output.isEmpty)
        }
    }
}

@Suite("App stability and crash-resistance stress tests")
struct StabilityStressTests {
    @Test("CorrectionWatcher rapid observe/cancel cycles do not crash")
    @MainActor
    func correctionWatcherStress() {
        let watcher = CorrectionWatcher.shared
        for i in 0..<200 {
            watcher.observe(injected: "iteration \(i)", target: nil)
            watcher.cancel()
        }
    }

    @Test("HUDPanel rapid present and dismiss cycles do not crash")
    @MainActor
    func hudPanelRapidPresentDismiss() async {
        let controller = DictationController()
        let panel = HUDPanel(controller: controller)

        for _ in 0..<25 {
            panel.present()
            panel.dismiss()
        }
        // Allow queued completion handlers to drain.
        try? await Task.sleep(for: .milliseconds(250))
        panel.orderOut(nil)
    }

    @Test("CorrectionToastPanel rapid present and dismiss cycles do not crash")
    @MainActor
    func correctionToastRapidPresentDismiss() async {
        let systemWide = AXUIElementCreateSystemWide()
        for i in 0..<25 {
            guard let correction = CorrectionDiff.detect(
                original: "hello shush\(i) world",
                current: "hello Shush\(i) world"
            ) else {
                Issue.record("Expected correction diff")
                return
            }
            let toast = CorrectionToastPanel(
                correction: correction,
                onSave: {},
                onDismiss: {}
            )
            toast.present(near: systemWide)
            toast.dismiss()
        }
        try? await Task.sleep(for: .milliseconds(250))
    }

    @Test("TextInjector handles empty input and DictationController handles repeated cancel/stop safely")
    @MainActor
    func injectorAndControllerIdleStress() {
        TextInjector.insert("")
        let controller = DictationController()
        for _ in 0..<100 {
            controller.cancelCurrentRecording()
            controller.stopButtonRecording()
            controller.deactivate()
        }
        #expect(controller.state == .idle)
    }

    @Test("Concurrent RuleBasedFormatter stress test")
    func concurrentFormattingStress() async {
        let formatter = RuleBasedFormatter(removeFillerWords: true)
        await withTaskGroup(of: String.self) { group in
            for i in 0..<100 {
                group.addTask {
                    await formatter.format("um, uh, iteration \(i), sorry, step \(i) , , .")
                }
            }
            var count = 0
            for await result in group {
                #expect(!result.isEmpty)
                #expect(!result.contains(", ,"))
                count += 1
            }
            #expect(count == 100)
        }
    }
}
