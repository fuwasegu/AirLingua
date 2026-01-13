//
//  ContentView.swift
//  LocalTranslate
//
//  Created by hirosugu.takeshita on 2026/01/08.
//

import SwiftUI
import UniformTypeIdentifiers

/// メインコンテンツビュー
struct ContentView: View {
    @EnvironmentObject var translationManager: TranslationManager
    @StateObject private var memoryMonitor = MemoryMonitor()
    @State private var inputText: String = ""
    @State private var outputText: String = ""
    @State private var isTranslating: Bool = false
    @State private var selectedTargetLanguage: Language = .japanese
    @State private var selectedSourceLanguage: Language? = nil  // nil = 自動検出
    @State private var showingError: Bool = false
    @State private var errorMessage: String = ""

    var body: some View {
        VStack(spacing: 16) {
            // ヘッダー
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AirLingua")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(translationManager.modelType.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    StatusIndicator(isReady: translationManager.isReady, isLoading: translationManager.isLoading)
                    Text(memoryMonitor.formattedUsage)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal)

            // 言語選択
            HStack(spacing: 8) {
                LanguagePicker(
                    label: "From",
                    selection: Binding(
                        get: { selectedSourceLanguage ?? .english },
                        set: { selectedSourceLanguage = $0 }
                    ),
                    includeAuto: true,
                    isAuto: selectedSourceLanguage == nil,
                    onAutoToggle: { selectedSourceLanguage = nil }
                )

                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)

                LanguagePicker(
                    label: "To",
                    selection: $selectedTargetLanguage,
                    includeAuto: false,
                    isAuto: false,
                    onAutoToggle: {}
                )
            }
            .padding(.horizontal)

            // 入力エリア
            VStack(alignment: .leading, spacing: 4) {
                Text("原文")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: $inputText)
                    .font(.body)
                    .frame(minHeight: 100)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            }
            .padding(.horizontal)

            // 翻訳ボタン
            Button(action: translate) {
                HStack {
                    if isTranslating {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(.circular)
                    }
                    Text(isTranslating ? "翻訳中..." : "翻訳")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(inputText.isEmpty || isTranslating || !translationManager.isReady)
            .padding(.horizontal)

            // 出力エリア
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("翻訳結果")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    if !outputText.isEmpty {
                        Button(action: copyToClipboard) {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("クリップボードにコピー")
                    }
                }
                TextEditor(text: .constant(outputText))
                    .font(.body)
                    .frame(minHeight: 100)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            }
            .padding(.horizontal)

            // フッター（ライセンス表記）
            HStack {
                Spacer()
                Text(translationManager.modelType.licenseNote)
                    .font(.caption2)
                    .foregroundColor(translationManager.modelType == .plamo ? .orange : .secondary)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .frame(minWidth: 400, minHeight: 450)
        .padding(.vertical)
        .alert("エラー", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .task {
            // アプリ起動時にモデルを読み込む
            if !translationManager.isReady && !translationManager.isLoading {
                await translationManager.loadModel()
            }
        }
    }

    private func translate() {
        guard !inputText.isEmpty else { return }

        isTranslating = true
        Task { @MainActor in
            do {
                let result = try await translationManager.translate(
                    inputText,
                    from: selectedSourceLanguage,
                    to: selectedTargetLanguage
                )
                outputText = result.translatedText
                isTranslating = false
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
                isTranslating = false
            }
        }
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(outputText, forType: .string)
    }
}

/// ステータスインジケーター
struct StatusIndicator: View {
    let isReady: Bool
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var statusColor: Color {
        if isLoading {
            return .orange
        }
        return isReady ? .green : .red
    }

    private var statusText: String {
        if isLoading {
            return "読み込み中"
        }
        return isReady ? "準備完了" : "未読み込み"
    }
}

/// 言語選択ピッカー
struct LanguagePicker: View {
    let label: String
    @Binding var selection: Language
    let includeAuto: Bool
    let isAuto: Bool
    let onAutoToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)

            if includeAuto {
                Menu {
                    Button("自動検出") {
                        onAutoToggle()
                    }
                    Divider()
                    ForEach(Language.allCases) { language in
                        Button(language.localizedName) {
                            selection = language
                        }
                    }
                } label: {
                    Text(isAuto ? "自動検出" : selection.localizedName)
                        .frame(minWidth: 100)
                }
            } else {
                Picker("", selection: $selection) {
                    ForEach(Language.allCases) { language in
                        Text(language.localizedName).tag(language)
                    }
                }
                .labelsHidden()
                .frame(minWidth: 100)
            }
        }
    }
}

/// 設定ビュー
struct SettingsView: View {
    @EnvironmentObject var translationManager: TranslationManager
    @EnvironmentObject var downloader: ModelDownloader
    @AppStorage("modelPath") private var modelPath: String = ""
    @AppStorage("modelType") private var modelTypeRaw: String = ModelType.plamo.rawValue
    @State private var selectedDownloadIndex: Int = 0
    @State private var refreshTrigger: Bool = false  // 再描画用トリガー

    private var modelType: ModelType {
        ModelType(rawValue: modelTypeRaw) ?? .plamo
    }

    /// ダウンロード済みモデルのリスト
    private var downloadedModels: [ModelDownloader.ModelInfo] {
        let _ = refreshTrigger  // 再描画トリガー
        return ModelDownloader.availableModels.filter { downloader.isModelDownloaded($0) }
    }

    var body: some View {
        Form {
            Section("使用するモデル") {
                if downloadedModels.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.down.circle")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("モデルがダウンロードされていません")
                            .foregroundColor(.secondary)
                        Text("下の「モデルをダウンロード」からダウンロードしてください")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(downloadedModels, id: \.fileName) { model in
                            let isSelected = modelPath == downloader.modelsDirectory.appendingPathComponent(model.fileName).path

                            HStack {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(isSelected ? .accentColor : .secondary)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.name)
                                    Text(model.licenseNote)
                                        .font(.caption)
                                        .foregroundColor(model.modelType == .plamo ? .orange : .green)
                                }

                                Spacer()
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectModel(model)
                            }
                        }
                    }

                    // 現在のモデルのライセンス警告
                    if modelType == .plamo {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("PLaMo は個人利用のみ。社内配布不可。")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        .padding(.top, 4)
                    }
                }
            }

            Section("モデルをダウンロード") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(0..<ModelDownloader.availableModels.count, id: \.self) { index in
                        let model = ModelDownloader.availableModels[index]
                        let isDownloaded = downloader.isModelDownloaded(model)

                        HStack {
                            Image(systemName: !isDownloaded && selectedDownloadIndex == index ? "circle.fill" : "circle")
                                .foregroundColor(!isDownloaded && selectedDownloadIndex == index ? .accentColor : .secondary)
                                .font(.caption)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(model.name)
                                        .foregroundColor(isDownloaded ? .secondary : .primary)
                                    if isDownloaded {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.caption)
                                    }
                                }
                                Text("\(model.sizeDescription) \(model.licenseNote)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if !isDownloaded {
                                selectedDownloadIndex = index
                            }
                        }
                        .opacity(isDownloaded ? 0.5 : 1.0)
                    }
                }

                if downloader.isDownloading {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: downloader.progress) {
                            Text("ダウンロード中...")
                        }
                        Text("\(downloader.formattedSize(downloader.downloadedBytes)) / \(downloader.formattedSize(downloader.totalBytes))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("キャンセル") {
                            downloader.cancel()
                        }
                    }
                    .padding(.top, 8)
                } else {
                    let selectedModel = ModelDownloader.availableModels[selectedDownloadIndex]
                    let isSelectedDownloaded = downloader.isModelDownloaded(selectedModel)

                    Button("ダウンロード開始") {
                        Task {
                            await downloader.downloadModel(selectedModel)
                            if downloader.error == nil {
                                selectModel(selectedModel)
                                refreshTrigger.toggle()
                            }
                        }
                    }
                    .disabled(isSelectedDownloaded || downloader.isDownloading)
                    .padding(.top, 8)
                }

                if let error = downloader.error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Section("カスタムモデル") {
                HStack {
                    TextField("モデルパス", text: $modelPath)
                        .textFieldStyle(.roundedBorder)
                    Button("選択...") {
                        selectModelFile()
                    }
                }
                Text("リストにないモデルを使用する場合はファイルを直接選択")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("ライセンス情報") {
                VStack(alignment: .leading, spacing: 12) {
                    // 現在のモデルのライセンス
                    HStack(spacing: 8) {
                        Text(modelType.licenseNote)
                            .font(.subheadline)
                    }

                    Divider()

                    // PLaMo ライセンス
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PLaMo Community License")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text("年間売上10億円以下の個人・企業は無料。社内配布は不可。")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Link("詳細", destination: URL(string: "https://www.preferred.jp/ja/plamo-community-license/")!)
                            .font(.caption2)
                    }

                    // ELYZA ライセンス
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Llama 3 Community License")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text("MAU 7億未満であれば商用利用可。社内配布可。")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Link("詳細", destination: URL(string: "https://llama.meta.com/llama3/license/")!)
                            .font(.caption2)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 550, height: 550)
        .padding()
    }

    private func selectModelFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "GGUF モデルファイルを選択"

        if panel.runModal() == .OK, let url = panel.url {
            modelPath = url.path
            // ファイル名からモデルタイプを推測
            let fileName = url.lastPathComponent.lowercased()
            if fileName.contains("elyza") || fileName.contains("llama") {
                modelTypeRaw = ModelType.elyza.rawValue
                translationManager.modelType = .elyza
            } else {
                modelTypeRaw = ModelType.plamo.rawValue
                translationManager.modelType = .plamo
            }
            Task {
                translationManager.unloadModel()
                await translationManager.loadModel()
            }
            refreshTrigger.toggle()
        }
    }

    /// モデルを選択して使用
    private func selectModel(_ model: ModelDownloader.ModelInfo) {
        let path = downloader.modelsDirectory.appendingPathComponent(model.fileName).path
        modelPath = path
        modelTypeRaw = model.modelType.rawValue
        translationManager.modelType = model.modelType
        Task {
            translationManager.unloadModel()
            await translationManager.loadModel()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(TranslationManager())
}
