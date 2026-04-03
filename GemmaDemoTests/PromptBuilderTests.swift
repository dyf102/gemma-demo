import XCTest
@testable import GemmaDemo

final class PromptBuilderTests: XCTestCase {

    func test_taxMode_wrapsInGemmaTemplate() {
        let prompt = PromptBuilder.build(mode: .tax(fixture: sampleFixture), userQuestion: "What is box14?")
        XCTAssertTrue(prompt.hasPrefix("<start_of_turn>user\n"), "Must start with Gemma user turn")
        XCTAssertTrue(prompt.hasSuffix("<start_of_turn>model\n"), "Must end with model turn opener")
    }

    func test_taxMode_containsFixtureJSON() {
        let prompt = PromptBuilder.build(mode: .tax(fixture: sampleFixture), userQuestion: "Any question")
        XCTAssertTrue(prompt.contains("85000"), "Must include fixture field value")
        XCTAssertTrue(prompt.contains("T4"), "Must include fixture document type")
    }

    func test_taxMode_containsSystemInstruction() {
        let prompt = PromptBuilder.build(mode: .tax(fixture: sampleFixture), userQuestion: "Any question")
        XCTAssertTrue(prompt.contains("Never invent"), "Must include hallucination guard instruction")
        XCTAssertTrue(prompt.contains("I don't have enough information"), "Must include refusal template phrase")
    }

    func test_taxMode_containsUserQuestion() {
        let question = "How much tax was withheld?"
        let prompt = PromptBuilder.build(mode: .tax(fixture: sampleFixture), userQuestion: question)
        XCTAssertTrue(prompt.contains(question))
    }

    func test_rawMode_noSystemPrompt_noFixture() {
        let question = "Hello"
        let prompt = PromptBuilder.build(mode: .raw, userQuestion: question)
        XCTAssertFalse(prompt.contains("Never invent"))
        XCTAssertFalse(prompt.contains("85000"))
        XCTAssertTrue(prompt.contains(question))
        XCTAssertTrue(prompt.hasPrefix("<start_of_turn>user\n"))
        XCTAssertTrue(prompt.hasSuffix("<start_of_turn>model\n"))
    }

    func test_template_structure_order() {
        let prompt = PromptBuilder.build(mode: .raw, userQuestion: "Q")
        let userTurnRange = prompt.range(of: "<start_of_turn>user")!
        let endTurnRange  = prompt.range(of: "<end_of_turn>")!
        let modelTurnRange = prompt.range(of: "<start_of_turn>model")!
        XCTAssertLessThan(userTurnRange.lowerBound, endTurnRange.lowerBound)
        XCTAssertLessThan(endTurnRange.lowerBound, modelTurnRange.lowerBound)
    }

    private let sampleFixture = """
    {"tax_year":2024,"documents":[{"type":"T4","box14":85000}],"onboarding":{"had_employment":true}}
    """
}
