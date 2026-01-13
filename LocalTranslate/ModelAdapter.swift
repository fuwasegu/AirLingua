import Foundation

/// モデルごとの翻訳ロジックを抽象化するプロトコル
protocol ModelAdapter {
    /// モデルの表示名
    var name: String { get }

    /// 停止トークン（生成を止めるトークン）
    var stopTokens: [String] { get }

    /// 翻訳用プロンプトを構築
    func buildPrompt(text: String, source: Language, target: Language) -> String

    /// 出力をクリーニング（不要なトークンや前置きを除去）
    func cleanOutput(_ output: String) -> String

    /// 入力テキストを正規化（モデルに渡す前の前処理）
    func normalizeInput(_ text: String) -> String
}

// MARK: - デフォルト実装
extension ModelAdapter {
    /// デフォルトの入力正規化（改行の統一、連続改行の削減）
    func normalizeInput(_ text: String) -> String {
        var result = text

        // \r\n や \r を \n に統一
        result = result.replacingOccurrences(of: "\r\n", with: "\n")
        result = result.replacingOccurrences(of: "\r", with: "\n")

        // 3つ以上の連続する改行を2つに（段落区切りは維持）
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        return result
    }

    /// 共通のクリーニング処理
    func commonCleanOutput(_ output: String) -> String {
        var result = output
        result = result.replacingOccurrences(of: "[end of text]", with: "")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - ファクトリ
extension ModelAdapter where Self == PLaMoAdapter {
    static func create(for modelType: ModelType) -> ModelAdapter {
        switch modelType {
        case .plamo:
            return PLaMoAdapter()
        case .elyza:
            return ElyzaAdapter()
        case .alma:
            return AlmaAdapter()
        case .qwen3_8b, .qwen3_4b:
            return Qwen3Adapter()
        }
    }
}

/// ModelType から ModelAdapter を生成するファクトリ関数
func createModelAdapter(for modelType: ModelType) -> ModelAdapter {
    switch modelType {
    case .plamo:
        return PLaMoAdapter()
    case .elyza:
        return ElyzaAdapter()
    case .alma:
        return AlmaAdapter()
    case .qwen3_8b, .qwen3_4b:
        return Qwen3Adapter()
    }
}
