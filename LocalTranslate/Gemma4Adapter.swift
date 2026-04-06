import Foundation

/// Gemma 4 E4B 用アダプター
/// Google製 高性能汎用モデル（Gemma 4 チャットテンプレート）
struct Gemma4Adapter: ModelAdapter {
    var name: String { "Gemma 4 E4B (GGUF)" }

    var stopTokens: [String] { ["<turn|>"] }

    func buildPrompt(text: String, source: Language, target: Language) -> String {
        // Gemma 4 チャットテンプレート形式
        // <|turn>role\n...<turn|> を使用（Gemma 3 以前の <start_of_turn>/<end_of_turn> とは異なる）
        let sourceLang = languageName(for: source)
        let targetLang = languageName(for: target)

        let systemPrompt = "You are a translator. Translate the given text accurately and naturally. Output only the translation."
        let userPrompt = "Translate the following text from \(sourceLang) to \(targetLang).\n\n\(text)"

        return "<|turn>system\n\(systemPrompt)<turn|>\n<|turn>user\n\(userPrompt)<turn|>\n<|turn>model\n"
    }

    func cleanOutput(_ output: String) -> String {
        var result = commonCleanOutput(output)

        // Gemma 4 トークンを除去
        result = result.replacingOccurrences(of: "<turn|>", with: "")
        result = result.replacingOccurrences(of: "<|turn>", with: "")
        result = result.replacingOccurrences(of: "<eos>", with: "")
        // thinking トークンが混入した場合に除去
        result = result.replacingOccurrences(of: "<|think|>", with: "")
        result = result.replacingOccurrences(of: "<|channel>thought", with: "")
        result = result.replacingOccurrences(of: "<channel|>", with: "")
        result = result.replacingOccurrences(of: "<|channel>", with: "")

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func languageName(for language: Language) -> String {
        switch language {
        case .japanese: return "Japanese"
        case .english: return "English"
        }
    }
}
