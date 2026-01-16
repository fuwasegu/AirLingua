import Foundation

/// TranslateGemma-4B 用アダプター
/// Google製 翻訳特化モデル（Gemma 3 ベース）
struct TranslateGemmaAdapter: ModelAdapter {
    var name: String { "TranslateGemma-4B (GGUF)" }

    var stopTokens: [String] { ["<end_of_turn>"] }

    func buildPrompt(text: String, source: Language, target: Language) -> String {
        // Gemma 3 チャットテンプレート形式
        // TranslateGemma は翻訳特化なのでシンプルな指示で動く
        let sourceLang = languageCode(for: source)
        let targetLang = languageCode(for: target)

        let instruction = "Translate the following text from \(sourceLang) to \(targetLang). Output only the translation."

        return "<start_of_turn>user\n\(instruction)\n\n\(text)<end_of_turn>\n<start_of_turn>model\n"
    }

    func cleanOutput(_ output: String) -> String {
        var result = commonCleanOutput(output)

        // Gemma トークンを除去
        result = result.replacingOccurrences(of: "<end_of_turn>", with: "")
        result = result.replacingOccurrences(of: "<start_of_turn>", with: "")
        result = result.replacingOccurrences(of: "<eos>", with: "")

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Language を ISO 言語コードに変換
    private func languageCode(for language: Language) -> String {
        switch language {
        case .japanese:
            return "Japanese"
        case .english:
            return "English"
        }
    }
}
