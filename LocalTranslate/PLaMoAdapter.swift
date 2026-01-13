import Foundation

/// PLaMo-2-translate 用アダプター
struct PLaMoAdapter: ModelAdapter {
    var name: String { "PLaMo-2-translate (GGUF)" }

    var stopTokens: [String] { ["<|plamo:op|>"] }

    func buildPrompt(text: String, source: Language, target: Language) -> String {
        // PLaMo-2-translate の正しいプロンプト形式
        // https://huggingface.co/pfnet/plamo-2-translate
        "<|plamo:op|>dataset translation\n<|plamo:op|>input lang=\(source.rawValue)\n\(text)\n<|plamo:op|>output lang=\(target.rawValue)\n"
    }

    func cleanOutput(_ output: String) -> String {
        var result = commonCleanOutput(output)
        result = result.replacingOccurrences(of: "<|plamo:op|>", with: "")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
