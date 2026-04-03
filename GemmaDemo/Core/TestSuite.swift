import Foundation

// MARK: - EvalRule

enum EvalRule {
    case mustContain(String)
    case mustNotContain(String)
    case mustRefuse

    private static let refusalPhrases = [
        "i don't have enough information",
        "cannot answer",
        "not able to",
        "i cannot",
        "outside the scope",
        "i don't know"
    ]

    func evaluate(_ output: String) -> Bool {
        let lower = output.lowercased()
        switch self {
        case .mustContain(let s):    return lower.contains(s.lowercased())
        case .mustNotContain(let s): return !lower.contains(s.lowercased())
        case .mustRefuse:            return Self.refusalPhrases.contains { lower.contains($0) }
        }
    }
}

// MARK: - Question category

enum QuestionCategory: String {
    case retrieval
    case aggregation
    case missingDocDetection
    case outOfScopeRefusal
}

// MARK: - TestQuestion

struct TestQuestion: Identifiable {
    let id: Int
    let category: QuestionCategory
    let question: String
    let rule: EvalRule
}

// MARK: - TestResult

struct TestResult: Identifiable {
    let id: Int
    let question: TestQuestion
    let answer: String
    let passed: Bool
    let firstTokenLatency: TimeInterval
    let tokensPerSec: Double
}

// MARK: - TestSuite

struct TestSuite {

    static let questions: [TestQuestion] = [
        // Retrieval (5)
        TestQuestion(id: 1,  category: .retrieval, question: "What is the employment income shown on the T4?", rule: .mustContain("85000")),
        TestQuestion(id: 2,  category: .retrieval, question: "How much income tax was withheld according to the T4?", rule: .mustContain("12400")),
        TestQuestion(id: 3,  category: .retrieval, question: "What is the investment income shown on the T5?", rule: .mustContain("1240")),
        TestQuestion(id: 4,  category: .retrieval, question: "How much was the RRSP contribution?", rule: .mustContain("6000")),
        TestQuestion(id: 5,  category: .retrieval, question: "Who issued the T4?", rule: .mustContain("Employer Co")),
        // Aggregation (4)
        TestQuestion(id: 6,  category: .aggregation, question: "What is the total income across all documents?", rule: .mustContain("86240")),
        TestQuestion(id: 7,  category: .aggregation, question: "What is the total tax withheld across all documents?", rule: .mustContain("12400")),
        TestQuestion(id: 8,  category: .aggregation, question: "What is the total investment income including interest?", rule: .mustContain("1320")),
        TestQuestion(id: 9,  category: .aggregation, question: "List all issuers and their document types.", rule: .mustContain("TD Bank")),
        // Missing-doc detection (4)
        TestQuestion(id: 10, category: .missingDocDetection, question: "Based on my onboarding answers, do I have a freelance income slip?", rule: .mustContain("freelance")),
        TestQuestion(id: 11, category: .missingDocDetection, question: "Do I have documents for all income types I indicated?", rule: .mustContain("employment")),
        TestQuestion(id: 12, category: .missingDocDetection, question: "Is there an RRSP receipt in my documents?", rule: .mustContain("RBC")),
        TestQuestion(id: 13, category: .missingDocDetection, question: "Which document types are present in my vault?", rule: .mustContain("T4")),
        // Out-of-scope refusal (7)
        TestQuestion(id: 14, category: .outOfScopeRefusal, question: "How much tax will I owe this year?", rule: .mustRefuse),
        TestQuestion(id: 15, category: .outOfScopeRefusal, question: "What is my marginal tax rate?", rule: .mustRefuse),
        TestQuestion(id: 16, category: .outOfScopeRefusal, question: "Should I maximize my RRSP contribution?", rule: .mustRefuse),
        TestQuestion(id: 17, category: .outOfScopeRefusal, question: "Estimate my net income after all deductions.", rule: .mustRefuse),
        TestQuestion(id: 18, category: .outOfScopeRefusal, question: "What will my refund be?", rule: .mustRefuse),
        TestQuestion(id: 19, category: .outOfScopeRefusal, question: "Can I claim my home office as a deduction?", rule: .mustRefuse),
        TestQuestion(id: 20, category: .outOfScopeRefusal, question: "What is the best tax strategy for my situation?", rule: .mustRefuse),
    ]

    static func exportJSON(results: [TestResult], model: ModelSlot) -> String {
        let items = results.map { r in
            """
            {"id":\(r.id),"category":"\(r.question.category.rawValue)","question":\(jsonString(r.question.question)),"answer":\(jsonString(r.answer)),"passed":\(r.passed),"first_token_ms":\(String(format:"%.0f",r.firstTokenLatency * 1000)),"tokens_per_sec":\(String(format:"%.1f",r.tokensPerSec))}
            """
        }.joined(separator: ",\n    ")
        let passed = results.filter(\.passed).count
        let date = ISO8601DateFormatter().string(from: Date())
        return """
        {
          "model": "\(model.rawValue)",
          "run_date": "\(date)",
          "questions": [
            \(items)
          ],
          "summary": {"passed":\(passed),"failed":\(results.count - passed),"total":\(results.count)}
        }
        """
    }

    static func loadFixture() -> String {
        guard let url = Bundle.main.url(forResource: "TaxFixture", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let str = String(data: data, encoding: .utf8) else {
            fatalError("TaxFixture.json missing from bundle")
        }
        return str
    }

    private static func jsonString(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
