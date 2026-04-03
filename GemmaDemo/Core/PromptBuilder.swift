import Foundation

enum PromptMode {
    case tax(fixture: String)
    case raw
}

struct PromptBuilder {

    static func build(mode: PromptMode, userQuestion: String) -> String {
        let userContent: String
        switch mode {
        case .tax(let fixture):
            userContent = """
            \(systemPrompt)

            Documents:
            \(fixture)

            \(userQuestion)
            """
        case .raw:
            userContent = userQuestion
        }
        return "<start_of_turn>user\n\(userContent)<end_of_turn>\n<start_of_turn>model\n"
    }

    static let systemPrompt = """
    You are a tax document review assistant.
    Answer only based on the structured document data below.
    Never invent, estimate, or approximate numeric values not present in the data.
    If you cannot answer from the data, say: "I don't have enough information in the provided documents to answer that."
    """
}
