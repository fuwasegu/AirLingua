import Foundation

/// ALMA-7B-Ja 用アダプター
struct AlmaAdapter: ModelAdapter {
    var name: String { "ALMA-7B-Ja (GGUF)" }

    var stopTokens: [String] { ["</s>"] }

    func buildPrompt(text: String, source: Language, target: Language) -> String {
        // ALMA-7B-Ja の翻訳プロンプト形式
        // https://huggingface.co/webbigdata/ALMA-7B-Ja
        if target == .japanese {
            return "Translate this from English to Japanese:\nEnglish: \(text)\nJapanese:"
        } else {
            return "Translate this from Japanese to English:\nJapanese: \(text)\nEnglish:"
        }
    }

    func cleanOutput(_ output: String) -> String {
        var result = commonCleanOutput(output)
        result = result.replacingOccurrences(of: "</s>", with: "")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// ALMA は改行があると途中で止まる問題があるため、改行をスペースに置換
    func normalizeInput(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ")
    }
}
