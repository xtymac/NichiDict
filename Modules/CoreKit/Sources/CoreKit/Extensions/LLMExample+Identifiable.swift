import Foundation

extension LLMExample: Identifiable {
    public var id: String {
        "\(japanese)|\(chinese)|\(english)"
    }
}
