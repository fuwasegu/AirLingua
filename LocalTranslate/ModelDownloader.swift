import Foundation
import Combine

/// モデルダウンローダー
@MainActor
class ModelDownloader: NSObject, ObservableObject {
    @Published var isDownloading: Bool = false
    @Published var progress: Double = 0.0
    @Published var downloadedBytes: Int64 = 0
    @Published var totalBytes: Int64 = 0
    @Published var error: String?

    private var downloadTask: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<URL, Error>?

    /// 利用可能なモデル
    struct ModelInfo {
        let name: String
        let fileName: String
        let url: URL
        let sizeDescription: String
        let modelType: ModelType
        let licenseNote: String
    }

    /// ダウンロード可能なモデル一覧
    static let availableModels: [ModelInfo] = [
        // PLaMo モデル（個人利用のみ）
        ModelInfo(
            name: "PLaMo-2-translate Q3_K_M",
            fileName: "plamo-2-translate-Q3_K_M.gguf",
            url: URL(string: "https://huggingface.co/mmnga/plamo-2-translate-gguf/resolve/main/plamo-2-translate-Q3_K_M.gguf")!,
            sizeDescription: "約 4.6 GB",
            modelType: .plamo,
            licenseNote: "⚠️ 個人利用のみ"
        ),
        ModelInfo(
            name: "PLaMo-2-translate Q4_K_S",
            fileName: "plamo-2-translate-Q4_K_S.gguf",
            url: URL(string: "https://huggingface.co/mmnga/plamo-2-translate-gguf/resolve/main/plamo-2-translate-Q4_K_S.gguf")!,
            sizeDescription: "約 5.5 GB",
            modelType: .plamo,
            licenseNote: "⚠️ 個人利用のみ"
        ),
        // ELYZA モデル（商用可）
        ModelInfo(
            name: "ELYZA-JP-8B Q4_K_M",
            fileName: "Llama-3-ELYZA-JP-8B-q4_k_m.gguf",
            url: URL(string: "https://huggingface.co/elyza/Llama-3-ELYZA-JP-8B-GGUF/resolve/main/Llama-3-ELYZA-JP-8B-q4_k_m.gguf")!,
            sizeDescription: "約 4.9 GB",
            modelType: .elyza,
            licenseNote: "✅ 商用利用可"
        ),
        // ALMA モデル（翻訳特化・商用可）
        ModelInfo(
            name: "ALMA-7B-Ja Q4_K_M（推奨）",
            fileName: "webbigdata-ALMA-7B-Ja-q4_K_M.gguf",
            url: URL(string: "https://huggingface.co/mmnga/webbigdata-ALMA-7B-Ja-gguf/resolve/main/webbigdata-ALMA-7B-Ja-q4_K_M.gguf")!,
            sizeDescription: "約 4.1 GB",
            modelType: .alma,
            licenseNote: "✅ 商用利用可（MIT）"
        ),
        // Qwen3 モデル（多言語対応・商用可）
        ModelInfo(
            name: "Qwen3-8B Q4_K_M",
            fileName: "Qwen3-8B-Q4_K_M.gguf",
            url: URL(string: "https://huggingface.co/Qwen/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q4_K_M.gguf")!,
            sizeDescription: "約 5.0 GB",
            modelType: .qwen3_8b,
            licenseNote: "✅ 商用利用可（Apache 2.0）"
        ),
        ModelInfo(
            name: "Qwen3-4B-Instruct Q4_K_M",
            fileName: "Qwen3-4B-Instruct-2507-Q4_K_M.gguf",
            url: URL(string: "https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/main/Qwen3-4B-Instruct-2507-Q4_K_M.gguf")!,
            sizeDescription: "約 2.5 GB",
            modelType: .qwen3_4b,
            licenseNote: "✅ 商用利用可（Apache 2.0）"
        ),
    ]

    /// モデル保存ディレクトリ
    var modelsDirectory: URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            // フォールバック: ホームディレクトリを使用
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/AirLingua/models")
        }
        return appSupport.appendingPathComponent("AirLingua/models")
    }

    /// モデルがダウンロード済みかチェック
    func isModelDownloaded(_ model: ModelInfo) -> Bool {
        let path = modelsDirectory.appendingPathComponent(model.fileName).path
        return FileManager.default.fileExists(atPath: path)
    }

    /// 特定のモデルタイプのファイルが存在するかチェック
    func hasModelForType(_ type: ModelType) -> Bool {
        // ダウンロード済みモデルの中に該当タイプがあるか
        for model in Self.availableModels where model.modelType == type {
            if isModelDownloaded(model) {
                return true
            }
        }
        // または現在設定されているモデルパスが存在するか
        let currentPath = UserDefaults.standard.string(forKey: "modelPath") ?? ""
        if FileManager.default.fileExists(atPath: currentPath) {
            // ファイル名からタイプを推測
            let fileName = (currentPath as NSString).lastPathComponent.lowercased()
            if type == .plamo && fileName.contains("plamo") {
                return true
            }
            if type == .elyza && (fileName.contains("elyza") || fileName.contains("llama")) {
                return true
            }
        }
        return false
    }

    /// ダウンロード済みモデルのパスを取得
    func downloadedModelPath(_ model: ModelInfo) -> String? {
        let path = modelsDirectory.appendingPathComponent(model.fileName).path
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.main)
    }()

    /// モデルをダウンロード
    func downloadModel(_ model: ModelInfo) async {
        isDownloading = true
        progress = 0.0
        downloadedBytes = 0
        totalBytes = 0
        error = nil

        do {
            // ディレクトリを作成
            try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

            let destinationURL = modelsDirectory.appendingPathComponent(model.fileName)

            // 既存ファイルがあれば削除
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            // ダウンロード（進捗付き）
            let tempURL = try await downloadWithProgress(from: model.url)

            // ダウンロードしたファイルを移動
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)

            progress = 1.0

            // モデルパスとタイプを設定
            UserDefaults.standard.set(destinationURL.path, forKey: "modelPath")
            UserDefaults.standard.set(model.modelType.rawValue, forKey: "modelType")

            isDownloading = false

        } catch {
            self.error = error.localizedDescription
            isDownloading = false
        }
    }

    /// 進捗付きダウンロード
    private func downloadWithProgress(from url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let task = urlSession.downloadTask(with: url)
            self.downloadTask = task
            task.resume()
        }
    }

    /// ダウンロードをキャンセル
    func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
        // continuation が残っている場合はキャンセルエラーで resume
        if let continuation = continuation {
            continuation.resume(throwing: DownloadError.cancelled)
            self.continuation = nil
        }
        isDownloading = false
    }

    /// フォーマットされたサイズ文字列
    func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    enum DownloadError: LocalizedError {
        case invalidResponse
        case httpError(statusCode: Int)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "サーバーからの応答が不正です"
            case .httpError(let statusCode):
                return "HTTPエラー: \(statusCode)"
            case .cancelled:
                return "ダウンロードがキャンセルされました"
            }
        }
    }
}

// MARK: - URLSessionDownloadDelegate
extension ModelDownloader: URLSessionDownloadDelegate {
    // delegateQueue が OperationQueue.main なので、これらのメソッドはメインスレッドで呼ばれる
    // ただし nonisolated なので、MainActor isolation を明示的に指定する必要がある

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // 一時ファイルをコピー（元のファイルは自動削除される）
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gguf")
        do {
            try FileManager.default.copyItem(at: location, to: tempURL)
            Task { @MainActor in
                self.continuation?.resume(returning: tempURL)
                self.continuation = nil
            }
        } catch {
            Task { @MainActor in
                self.continuation?.resume(throwing: error)
                self.continuation = nil
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        Task { @MainActor in
            self.downloadedBytes = totalBytesWritten
            self.totalBytes = totalBytesExpectedToWrite
            if totalBytesExpectedToWrite > 0 {
                self.progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            Task { @MainActor in
                self.continuation?.resume(throwing: error)
                self.continuation = nil
            }
        }
    }
}
