import XCTest
@testable import GemmaDemo

final class TestSuiteEvalTests: XCTestCase {

    func test_mustContain_match_passes() {
        XCTAssertTrue(EvalRule.mustContain("85000").evaluate("Your T4 box14 shows 85000 in employment income."))
    }

    func test_mustContain_noMatch_fails() {
        XCTAssertFalse(EvalRule.mustContain("85000").evaluate("I cannot find that value."))
    }

    func test_mustContain_caseInsensitive() {
        XCTAssertTrue(EvalRule.mustContain("employer co").evaluate("Your employer Employer Co issued the T4."))
    }

    func test_mustNotContain_match_fails() {
        XCTAssertFalse(EvalRule.mustNotContain("85000").evaluate("The value is 85000."))
    }

    func test_mustNotContain_noMatch_passes() {
        XCTAssertTrue(EvalRule.mustNotContain("85000").evaluate("I don't have that data."))
    }

    func test_mustRefuse_knownPhrase_passes() {
        XCTAssertTrue(EvalRule.mustRefuse.evaluate("I don't have enough information in the provided documents to answer that."))
        XCTAssertTrue(EvalRule.mustRefuse.evaluate("I cannot answer this question."))
        XCTAssertTrue(EvalRule.mustRefuse.evaluate("That is outside the scope of what I can help with."))
        XCTAssertTrue(EvalRule.mustRefuse.evaluate("I don't know the answer."))
    }

    func test_mustRefuse_noPhrase_fails() {
        XCTAssertFalse(EvalRule.mustRefuse.evaluate("Your marginal rate is approximately 35%."))
    }

    func test_questionCount_is20() {
        XCTAssertEqual(TestSuite.questions.count, 20)
    }

    func test_refusalCategory_has7Questions() {
        XCTAssertEqual(TestSuite.questions.filter { $0.category == .outOfScopeRefusal }.count, 7)
    }

    func test_allQuestionsHaveNonEmptyText() {
        for q in TestSuite.questions {
            XCTAssertFalse(q.question.isEmpty, "Question \(q.id) has empty text")
        }
    }
}
