import Foundation

/// PLaMo 3 Translate (0.8B/2B/8B) 用アダプター
/// PFN製 翻訳特化モデル（PFML3 形式・53言語対応）
struct PLaMo3Adapter: ModelAdapter {
    var name: String { "PLaMo-3-translate (GGUF)" }

    var stopTokens: [String] { ["<|plamo:tag|>", "<|plamo:bos|>"] }

    func buildPrompt(text: String, source: Language, target: Language) -> String {
        // PLaMo 3 Translate の PFML3 プロンプト形式
        // https://huggingface.co/pfnet/plamo-3-translate-2b-GGUF
        // Note: <|plamo:bos|> は llama.cpp が自動付与するため先頭には含めない。
        // 要素間に改行は入れず、末尾は <|plamo:msg|> で終える。
        let sourceCode = languageCode(for: source)
        let targetCode = languageCode(for: target)

        return "<|plamo:tag|>dataset<|plamo:msg|>translation"
            + "<|plamo:tag|>input<|plamo:key|>lang<|plamo:val|>\(sourceCode)<|plamo:msg|>\(text)"
            + "<|plamo:tag|>output<|plamo:key|>lang<|plamo:val|>\(targetCode)<|plamo:msg|>"
    }

    func cleanOutput(_ output: String) -> String {
        var result = commonCleanOutput(output)
        result = result.replacingOccurrences(of: "<|plamo:tag|>", with: "")
        result = result.replacingOccurrences(of: "<|plamo:bos|>", with: "")
        result = result.replacingOccurrences(of: "<|plamo:msg|>", with: "")
        result = result.replacingOccurrences(of: "<|plamo:key|>", with: "")
        result = result.replacingOccurrences(of: "<|plamo:val|>", with: "")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func languageCode(for language: Language) -> String {
        switch language {
        case .japanese: return "ja"
        case .english: return "en"
        }
    }
}
