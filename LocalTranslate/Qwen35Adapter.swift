import Foundation

/// Qwen3.5 (0.8B/2B/4B/9B) 用アダプター
/// Qwen3 と同じ ChatML 形式だが、/no_think は非サポート
/// 思考ブロック <think>...</think> の完全除去が必要
struct Qwen35Adapter: ModelAdapter {
    var name: String { "Qwen3.5 (GGUF)" }

    var stopTokens: [String] { ["<|im_end|>"] }

    func buildPrompt(text: String, source: Language, target: Language) -> String {
        let systemPrompt: String
        let userPrompt: String

        if target == .japanese {
            systemPrompt = "あなたは翻訳者です。与えられたテキストを正確かつ自然な日本語に翻訳してください。翻訳結果のみを出力してください。"
            userPrompt = "以下の英文を日本語に翻訳してください:\n\n\(text)"
        } else {
            systemPrompt = "You are a translator. Translate the given text accurately and completely. Output only the translation, nothing else."
            userPrompt = "Translate the following Japanese text to English:\n\n\(text)"
        }

        // assistant プレフィルで思考ブロックを即座に閉じ、翻訳のみ出力させる
        return "<|im_start|>system\n\(systemPrompt)<|im_end|>\n<|im_start|>user\n\(userPrompt)<|im_end|>\n<|im_start|>assistant\n<think>\n</think>\n\n"
    }

    func cleanOutput(_ output: String) -> String {
        var result = commonCleanOutput(output)

        // <think>...</think> ブロック全体を除去（Qwen3.5 は思考モードがデフォルト有効）
        if let thinkRange = result.range(of: "<think>[\\s\\S]*?</think>", options: .regularExpression) {
            result = result.replacingCharacters(in: thinkRange, with: "")
        }

        // 残存タグの除去（念のため）
        result = result.replacingOccurrences(of: "<think>", with: "")
        result = result.replacingOccurrences(of: "</think>", with: "")

        // ChatML トークンを除去
        result = result.replacingOccurrences(of: "<|im_end|>", with: "")
        result = result.replacingOccurrences(of: "<|im_start|>", with: "")
        result = result.replacingOccurrences(of: "<|endoftext|>", with: "")

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
