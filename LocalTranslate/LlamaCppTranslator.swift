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
        public var repeatPenalty: Float = 1.1  // 繰り返し抑制

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

    public func cleanOutput(_ text: String) -> String {
        adapter.cleanOutput(text)
    }

    public func translateStream(
        _ text: String,
        from sourceLanguage: Language?,
        to targetLanguage: Language
    ) -> AsyncThrowingStream<String, Error> {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard modelLoaded else {
            return AsyncThrowingStream { $0.finish(throwing: TranslationError.modelNotLoaded) }
        }
        guard !trimmedText.isEmpty else {
            return AsyncThrowingStream { $0.finish(throwing: TranslationError.emptyInput) }
        }

        let srcLang = sourceLanguage ?? detectLanguage(trimmedText)
        let normalizedText = adapter.normalizeInput(trimmedText)
        let prompt = adapter.buildPrompt(text: normalizedText, source: srcLang, target: targetLanguage)

        return runLlamaCompletionStream(prompt: prompt)
    }

    // MARK: - Private Methods

    /// llama-completion 用の環境変数を構築（Homebrew ライブラリパスを含む）
    private func processEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let homebrewLibPaths = ["/opt/homebrew/lib", "/usr/local/lib"]
        let existing = env["DYLD_LIBRARY_PATH"] ?? ""
        let allPaths = (existing.isEmpty ? [] : [existing]) + homebrewLibPaths
        env["DYLD_LIBRARY_PATH"] = allPaths.joined(separator: ":")
        return env
    }

    /// ggml バックエンドプラグインの検索用カレントディレクトリを決定
    ///
    /// libggml は GGML_BACKEND_DIR（コンパイル時定数）→ 実行ファイルのディレクトリ → cwd の順で
    /// バックエンドプラグインを検索する。Homebrew の ggml バージョンが上がると GGML_BACKEND_DIR の
    /// Cellar パスが存在しなくなるため、cwd フォールバックで正しいパスを指す。
    /// リリースビルドでは .so を llama-completion と同じディレクトリに同梱するため不要。
    private static func findGgmlBackendDir() -> String? {
        let candidates = [
            "/opt/homebrew/opt/ggml/libexec",
            "/usr/local/opt/ggml/libexec",
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// llama-completion をストリーミング実行
    private func runLlamaCompletionStream(prompt: String) -> AsyncThrowingStream<String, Error> {
        let modelPath = self.modelPath
        let llamaPath = self.llamaCompletionPath
        let maxTokens = self.config.maxTokens
        let contextSize = self.config.contextSize
        let temperature = self.config.temperature
        let repeatPenalty = self.config.repeatPenalty
        let stopTokens = self.adapter.stopTokens
        let adapter = self.adapter
        let env = self.processEnvironment()
        let backendDir = Self.findGgmlBackendDir()

        return AsyncThrowingStream { continuation in
            DispatchQueue(label: "llama-stream", qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: llamaPath)
                process.environment = env
                if let backendDir {
                    process.currentDirectoryURL = URL(fileURLWithPath: backendDir)
                }

                var arguments = [
                    "-m", modelPath,
                    "-p", prompt,
                    "-n", String(maxTokens),
                    "-c", String(contextSize),
                    "--temp", String(temperature),
                    "--repeat-penalty", String(repeatPenalty),
                    "--no-display-prompt",
                    "--no-conversation",
                ]

                for token in stopTokens {
                    arguments += ["-r", token]
                }

                process.arguments = arguments

                // PTY を作成（子プロセスが端末接続と認識し、stdout を逐次フラッシュする）
                var masterFd: Int32 = 0
                var slaveFd: Int32 = 0
                guard openpty(&masterFd, &slaveFd, nil, nil, nil) == 0 else {
                    continuation.finish(throwing: TranslationError.translationFailed(
                        message: "PTY の作成に失敗しました"
                    ))
                    return
                }

                // Raw モード（\n → \r\n 変換等を無効化）
                var rawAttr = Darwin.termios()
                tcgetattr(masterFd, &rawAttr)
                cfmakeraw(&rawAttr)
                tcsetattr(masterFd, TCSANOW, &rawAttr)

                process.standardOutput = FileHandle(fileDescriptor: slaveFd, closeOnDealloc: false)
                let errorPipe = Pipe()
                process.standardError = errorPipe

                do {
                    try process.run()
                } catch {
                    close(masterFd)
                    close(slaveFd)
                    continuation.finish(throwing: TranslationError.translationFailed(
                        message: error.localizedDescription
                    ))
                    return
                }

                // 親側では slave を閉じる（子プロセスが使用中）
                close(slaveFd)

                // master 側からトークンを逐次読み取り
                // PTY master は子プロセス終了時に EIO を返すので read() で直接処理
                var buf = [UInt8](repeating: 0, count: 4096)
                while true {
                    let n = Darwin.read(masterFd, &buf, buf.count)
                    if n <= 0 { break }
                    if let chunk = String(data: Data(buf[0..<n]), encoding: .utf8) {
                        let cleaned = adapter.cleanStreamChunk(chunk)
                        if !cleaned.isEmpty {
                            continuation.yield(cleaned)
                        }
                    }
                }

                close(masterFd)
                process.waitUntilExit()

                if process.terminationStatus != 0 {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    continuation.finish(throwing: TranslationError.translationFailed(
                        message: "llama-completion エラー: \(errorString)"
                    ))
                } else {
                    continuation.finish()
                }
            }
        }
    }

    /// llama-completion を実行（バックグラウンドスレッドで）
    private func runLlamaCompletion(prompt: String) async throws -> String {
        let modelPath = self.modelPath
        let llamaPath = self.llamaCompletionPath
        let maxTokens = self.config.maxTokens
        let contextSize = self.config.contextSize
        let temperature = self.config.temperature
        let repeatPenalty = self.config.repeatPenalty
        let stopTokens = self.adapter.stopTokens

        let env = self.processEnvironment()
        let backendDir = Self.findGgmlBackendDir()

        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: llamaPath)
            process.environment = env
            if let backendDir {
                process.currentDirectoryURL = URL(fileURLWithPath: backendDir)
            }

            var arguments = [
                "-m", modelPath,
                "-p", prompt,
                "-n", String(maxTokens),
                "-c", String(contextSize),
                "--temp", String(temperature),
                "--repeat-penalty", String(repeatPenalty),
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
