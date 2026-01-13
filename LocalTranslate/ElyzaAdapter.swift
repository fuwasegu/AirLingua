import Foundation

/// ELYZA-JP-8B 用アダプター
struct ElyzaAdapter: ModelAdapter {
    var name: String { "ELYZA-JP-8B (GGUF)" }

    var stopTokens: [String] { ["<|eot_id|>"] }

    func buildPrompt(text: String, source: Language, target: Language) -> String {
        // ELYZA Llama 3 のチャットテンプレート形式
        // https://huggingface.co/elyza/Llama-3-ELYZA-JP-8B-GGUF
        let systemPrompt = "あなたは翻訳APIです。入力された全文を翻訳して出力してください。途中で止めず、最後まで翻訳してください。「翻訳結果」「以下」などの前置きや説明は絶対に付けないでください。"

        let userPrompt: String
        if target == .japanese {
            userPrompt = "以下の英語を全て日本語に翻訳してください:\n\(text)"
        } else {
            userPrompt = "以下の日本語を全て英語に翻訳してください:\n\(text)"
        }

        return "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n\(systemPrompt)<|eot_id|><|start_header_id|>user<|end_header_id|>\n\n\(userPrompt)<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n"
    }

    func cleanOutput(_ output: String) -> String {
        var result = commonCleanOutput(output)

        result = result.replacingOccurrences(of: "<|eot_id|>", with: "")
        result = result.replacingOccurrences(of: "<|end_of_text|>", with: "")

        // ELYZA が付けがちな前置きを除去
        let prefixPatterns = [
            "^以下[がは]翻訳結果です[。：:]*\\s*",
            "^翻訳結果[：:]*\\s*",
            "^以下[がは].*?翻訳.*?です[。：:]*\\s*",
            "^.*?を翻訳しました[。：:]*\\s*",
        ]
        for pattern in prefixPatterns {
            if let range = result.range(of: pattern, options: .regularExpression) {
                result = String(result[range.upperBound...])
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
