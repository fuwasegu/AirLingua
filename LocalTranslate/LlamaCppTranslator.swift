import Foundation

/// llama-completion を使用した翻訳サービス
/// llama.cpp の CLI ツールを Process で呼び出す方式
/// ModelAdapter パターンで複数モデルをサポート
public final class LlamaCppTranslator: TranslationService {
    public var name: String { adapter.name }

    private let modelPath: String
    private let adapter: ModelAdapter
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
    ///   - modelType: モデルタイプ
    ///   - config: 推論設定
    public init(modelPath: String, modelType: ModelType = .plamo, config: Config = .default) {
        self.modelPath = modelPath
        self.adapter = createModelAdapter(for: modelType)
        self.config = config
        self.llamaCompletionPath = Self.findLlamaCompletion() ?? "/opt/homebrew/bin/llama-completion"
    }

    /// llama-completion のパスを探す
    private static func findLlamaCompletion() -> String? {
        let possiblePaths = [
            // アプリバンドル内（優先）
            Bundle.main.path(forResource: "llama-completion", ofType: nil),
            // システムにインストールされている場合
            "/opt/homebrew/bin/llama-completion",
            "/usr/local/bin/llama-completion",
            "/opt/homebrew/bin/llama-cli",
            "/usr/local/bin/llama-cli",
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
                    domain: "LlamaCppTranslator",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "モデルファイルが見つかりません: \(modelPath)"]
                )
            )
        }

        // llama-completion の存在確認
        guard FileManager.default.isExecutableFile(atPath: llamaCompletionPath) else {
            throw TranslationError.modelLoadFailed(
                underlying: NSError(
                    domain: "LlamaCppTranslator",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "llama-completion が見つかりません。\nbrew install llama.cpp でインストールしてください。"]
                )
            )
        }

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

        // アダプターで入力を正規化
        let normalizedText = adapter.normalizeInput(trimmedText)

        // アダプターでプロンプトを構築
        let prompt = adapter.buildPrompt(text: normalizedText, source: srcLang, target: targetLanguage)

        // llama-completion を実行
        let response = try await runLlamaCompletion(prompt: prompt)

        let duration = Date().timeIntervalSince(startTime)

        // アダプターで出力をクリーニング
        let cleanedResponse = adapter.cleanOutput(response)

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
        let modelPath = self.modelPath
        let llamaPath = self.llamaCompletionPath
        let maxTokens = self.config.maxTokens
        let contextSize = self.config.contextSize
        let temperature = self.config.temperature
        let stopTokens = self.adapter.stopTokens

        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: llamaPath)

            var arguments = [
                "-m", modelPath,
                "-p", prompt,
                "-n", String(maxTokens),
                "-c", String(contextSize),
                "--temp", String(temperature),
                "--no-display-prompt",
                "--no-conversation",
            ]

            // アダプターから停止トークンを追加
            for token in stopTokens {
                arguments += ["-r", token]
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

    /// 簡易的な言語検出（日本語/英語のみ）
    private func detectLanguage(_ text: String) -> Language {
        let japaneseRange = text.range(of: "[\\p{Hiragana}\\p{Katakana}\\p{Han}]", options: .regularExpression)
        if japaneseRange != nil {
            return .japanese
        }
        return .english
    }
}

// MARK: - 後方互換性のための型エイリアス
public typealias PLaMoTranslator = LlamaCppTranslator
