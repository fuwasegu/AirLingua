import Foundation

/// llama-completion を使用した翻訳サービス
/// llama.cpp の CLI ツールを Process で呼び出す方式
/// PLaMo-2-translate と ELYZA-JP をサポート
public final class PLaMoTranslator: TranslationService {
    public var name: String {
        switch modelType {
        case .plamo: return "PLaMo-2-translate (GGUF)"
        case .elyza: return "ELYZA-JP-8B (GGUF)"
        }
    }

    private let modelPath: String
    private let modelType: ModelType
    private var llamaCompletionPath: String

    /// 推論パラメータ
    public struct Config {
        public var contextSize: Int = 4096  // 長文対応
        public var temperature: Float = 0.1
        public var maxTokens: Int = 2048    // 長い出力に対応

        public static let `default` = Config()
    }

    private var config: Config
    private var modelLoaded: Bool = false

    public var isReady: Bool {
        modelLoaded
    }

    /// 初期化
    /// - Parameters:
    ///   - modelPath: GGUF モデルファイルのパス
    ///   - modelType: モデルタイプ（PLaMo or Elyza）
    ///   - config: 推論設定
    public init(modelPath: String, modelType: ModelType = .plamo, config: Config = .default) {
        self.modelPath = modelPath
        self.modelType = modelType
        self.config = config
        // llama-completion のパスを探す
        self.llamaCompletionPath = Self.findLlamaCompletion() ?? "/opt/homebrew/bin/llama-completion"
    }

    /// llama-completion のパスを探す
    private static func findLlamaCompletion() -> String? {
        let possiblePaths = [
            "/opt/homebrew/bin/llama-completion",
            "/usr/local/bin/llama-completion",
            // フォールバック: llama-cli
            "/opt/homebrew/bin/llama-cli",
            "/usr/local/bin/llama-cli",
            // アプリバンドル内
            Bundle.main.path(forResource: "llama-completion", ofType: nil),
        ].compactMap { $0 }

        for path in possiblePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    public func loadModel() async throws {
        // モデルファイルの存在確認
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw TranslationError.modelLoadFailed(
                underlying: NSError(
                    domain: "PLaMoTranslator",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "モデルファイルが見つかりません: \(modelPath)"]
                )
            )
        }

        // llama-completion の存在確認
        guard FileManager.default.isExecutableFile(atPath: llamaCompletionPath) else {
            throw TranslationError.modelLoadFailed(
                underlying: NSError(
                    domain: "PLaMoTranslator",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "llama-completion が見つかりません。\nbrew install llama.cpp でインストールしてください。"]
                )
            )
        }

        // 簡単なテスト実行でモデルが読み込めるか確認
        // (実際の読み込みは translate 時に行う)
        modelLoaded = true
    }

    public func unloadModel() {
        modelLoaded = false
    }

    public func translate(
        _ text: String,
        from sourceLanguage: Language?,
        to targetLanguage: Language
    ) async throws -> TranslationResult {
        guard modelLoaded else {
            throw TranslationError.modelNotLoaded
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw TranslationError.emptyInput
        }

        let startTime = Date()

        // 原文言語を検出または指定
        let srcLang = sourceLanguage ?? detectLanguage(trimmedText)

        // プロンプトを構築
        let prompt = buildPrompt(text: trimmedText, source: srcLang, target: targetLanguage)

        // llama-completion を実行
        let response = try await runLlamaCompletion(prompt: prompt)

        let duration = Date().timeIntervalSince(startTime)

        // 出力を整形（モデルタイプに応じて不要な文字列を除去）
        let cleanedResponse = cleanOutput(response)

        return TranslationResult(
            translatedText: cleanedResponse,
            detectedSourceLanguage: sourceLanguage == nil ? srcLang : nil,
            duration: duration,
            tokenCount: nil
        )
    }

    // MARK: - Private Methods

    /// llama-completion を実行（バックグラウンドスレッドで）
    private func runLlamaCompletion(prompt: String) async throws -> String {
        // メインスレッドをブロックしないようにバックグラウンドで実行
        let modelPath = self.modelPath
        let llamaPath = self.llamaCompletionPath
        let maxTokens = self.config.maxTokens
        let contextSize = self.config.contextSize
        let temperature = self.config.temperature
        let modelType = self.modelType

        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: llamaPath)

            // モデルタイプに応じた引数を構築
            var arguments = [
                "-m", modelPath,
                "-p", prompt,
                "-n", String(maxTokens),
                "-c", String(contextSize),
                "--temp", String(temperature),
                "--no-display-prompt",  // プロンプトを出力に含めない
                "--no-conversation",    // 対話モードを無効化
            ]

            // モデル固有の停止トークン
            switch modelType {
            case .plamo:
                arguments += ["-r", "<|plamo:op|>"]
            case .elyza:
                arguments += ["-r", "<|eot_id|>"]
            }

            process.arguments = arguments

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            do {
                try process.run()
            } catch {
                throw TranslationError.translationFailed(
                    message: error.localizedDescription
                )
            }

            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            if process.terminationStatus != 0 {
                let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                throw TranslationError.translationFailed(
                    message: "llama-completion エラー: \(errorString)"
                )
            }

            guard let output = String(data: outputData, encoding: .utf8) else {
                throw TranslationError.translationFailed(
                    message: "出力のデコードに失敗しました"
                )
            }

            return output
        }.value
    }

    /// プロンプトを構築（モデルタイプに応じて）
    private func buildPrompt(text: String, source: Language, target: Language) -> String {
        switch modelType {
        case .plamo:
            // PLaMo-2-translate の正しいプロンプト形式
            // https://huggingface.co/pfnet/plamo-2-translate
            return "<|plamo:op|>dataset translation\n<|plamo:op|>input lang=\(source.rawValue)\n\(text)\n<|plamo:op|>output lang=\(target.rawValue)\n"

        case .elyza:
            // ELYZA Llama 3 のチャットテンプレート形式
            // https://huggingface.co/elyza/Llama-3-ELYZA-JP-8B-GGUF
            let systemPrompt = "あなたは翻訳APIです。入力テキストの翻訳のみを出力してください。「翻訳結果」「以下」などの前置きや説明は絶対に付けないでください。"
            let userPrompt: String
            if target == .japanese {
                userPrompt = "英語→日本語:\n\(text)"
            } else {
                userPrompt = "日本語→英語:\n\(text)"
            }
            return "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n\(systemPrompt)<|eot_id|><|start_header_id|>user<|end_header_id|>\n\n\(userPrompt)<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n"
        }
    }

    /// 出力をクリーニング（モデルタイプに応じて）
    private func cleanOutput(_ output: String) -> String {
        var result = output

        // 共通のクリーニング
        result = result.replacingOccurrences(of: "[end of text]", with: "")

        // モデル固有のトークンを除去
        switch modelType {
        case .plamo:
            result = result.replacingOccurrences(of: "<|plamo:op|>", with: "")

        case .elyza:
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
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 簡易的な言語検出（日本語/英語のみ）
    private func detectLanguage(_ text: String) -> Language {
        // 日本語文字（ひらがな、カタカナ、漢字）が含まれていれば日本語
        let japaneseRange = text.range(of: "[\\p{Hiragana}\\p{Katakana}\\p{Han}]", options: .regularExpression)
        if japaneseRange != nil {
            return .japanese
        }

        // それ以外は英語
        return .english
    }
}
