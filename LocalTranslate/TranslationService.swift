import Foundation

/// 翻訳サービスのプロトコル（将来の拡張性を考慮）
/// 例：別のローカルLLM、MLX版、クラウドAPI（オプショナル）など
public protocol TranslationService: AnyObject {
    /// サービス名
    var name: String { get }

    /// サービスの準備ができているか
    var isReady: Bool { get }

    /// モデルを読み込む
    func loadModel() async throws

    /// モデルをアンロードする
    func unloadModel()

    /// テキストを翻訳する
    /// - Parameters:
    ///   - text: 翻訳するテキスト
    ///   - sourceLanguage: 原文の言語（nilの場合は自動検出）
    ///   - targetLanguage: 翻訳先の言語
    /// - Returns: 翻訳結果
    func translate(
        _ text: String,
        from sourceLanguage: Language?,
        to targetLanguage: Language
    ) async throws -> TranslationResult
}

/// サポートする言語（英日翻訳専用）
public enum Language: String, CaseIterable, Identifiable {
    case japanese = "Japanese"
    case english = "English"

    public var id: String { rawValue }

    public var localizedName: String {
        switch self {
        case .japanese: return "日本語"
        case .english: return "English"
        }
    }
}

/// モデルタイプ
public enum ModelType: String, CaseIterable, Identifiable {
    case plamo = "plamo"
    case elyza = "elyza"
    case alma = "alma"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .plamo: return "PLaMo-2-translate"
        case .elyza: return "ELYZA-JP-8B"
        case .alma: return "ALMA-7B-Ja"
        }
    }

    public var description: String {
        switch self {
        case .plamo: return "PFN製 翻訳特化モデル（個人利用のみ）"
        case .elyza: return "ELYZA製 汎用日本語モデル（商用可）"
        case .alma: return "翻訳特化モデル（商用可）"
        }
    }

    public var licenseNote: String {
        switch self {
        case .plamo: return "⚠️ PLaMo Community License - 個人利用のみ"
        case .elyza: return "✅ Llama 3 Community License - 商用利用可"
        case .alma: return "✅ MIT License - 商用利用可"
        }
    }
}

/// 翻訳結果
public struct TranslationResult {
    /// 翻訳されたテキスト
    public let translatedText: String

    /// 検出された原文言語（自動検出の場合）
    public let detectedSourceLanguage: Language?

    /// 翻訳にかかった時間（秒）
    public let duration: TimeInterval

    /// 使用したトークン数（推定）
    public let tokenCount: Int?

    public init(
        translatedText: String,
        detectedSourceLanguage: Language? = nil,
        duration: TimeInterval,
        tokenCount: Int? = nil
    ) {
        self.translatedText = translatedText
        self.detectedSourceLanguage = detectedSourceLanguage
        self.duration = duration
        self.tokenCount = tokenCount
    }
}

/// 翻訳エラー
public enum TranslationError: LocalizedError {
    case modelNotLoaded
    case modelLoadFailed(underlying: Error)
    case translationFailed(message: String)
    case unsupportedLanguage(Language)
    case emptyInput

    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "翻訳モデルが読み込まれていません"
        case .modelLoadFailed(let error):
            return "モデルの読み込みに失敗しました: \(error.localizedDescription)"
        case .translationFailed(let message):
            return "翻訳に失敗しました: \(message)"
        case .unsupportedLanguage(let language):
            return "サポートされていない言語です: \(language.localizedName)"
        case .emptyInput:
            return "翻訳するテキストが空です"
        }
    }
}
