import Foundation

/// Qwen3 (8B/4B) 用アダプター
struct Qwen3Adapter: ModelAdapter {
    var name: String { "Qwen3 (GGUF)" }

    var stopTokens: [String] { ["<|im_end|>"] }

    func buildPrompt(text: String, source: Language, target: Language) -> String {
        // Qwen3 ChatML 形式（/no_think で思考モードを無効化）
        let systemPrompt = "You are a translator. Translate the given text accurately and completely. Output only the translation without any explanations or preambles."

        let userPrompt: String
        if target == .japanese {
            userPrompt = "Translate the following English text to Japanese:\n\n\(text) /no_think"
        } else {
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
