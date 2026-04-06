import Foundation

/// Qwen3 (8B/4B) 用アダプター
struct Qwen3Adapter: ModelAdapter {
    var name: String { "Qwen3 (GGUF)" }

    var stopTokens: [String] { ["<|im_end|>"] }

    func buildPrompt(text: String, source: Language, target: Language) -> String {
        // Qwen3 ChatML 形式（/no_think で思考モードを無効化）
        let systemPrompt: String
        let userPrompt: String

        if target == .japanese {
            systemPrompt = "あなたは翻訳者です。与えられたテキストを正確かつ自然な日本語に翻訳してください。翻訳結果のみを出力してください。"
            userPrompt = "以下の英文を日本語に翻訳してください:\n\n\(text) /no_think"
        } else {
            systemPrompt = "You are a translator. Translate the given text accurately and completely. Output only the translation without any explanations or preambles."
            userPrompt = "Translate the following Japanese text to English:\n\n\(text) /no_think"
        }

        return "<|im_start|>system\n\(systemPrompt)<|im_end|>\n<|im_start|>user\n\(userPrompt)<|im_end|>\n<|im_start|>assistant\n"
    }

    func cleanOutput(_ output: String) -> String {
        var result = commonCleanOutput(output)

        // Qwen3 の ChatML トークンを除去
        result = result.replacingOccurrences(of: "<|im_end|>", with: "")
        result = result.replacingOccurrences(of: "<|im_start|>", with: "")
        result = result.replacingOccurrences(of: "<|endoftext|>", with: "")

        // think タグを除去（万が一出た場合）
        result = result.replacingOccurrences(of: "<think>", with: "")
        result = result.replacingOccurrences(of: "</think>", with: "")

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
