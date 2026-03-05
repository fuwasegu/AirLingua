//
//  ContentView.swift
//  LocalTranslate
//
//  Created by hirosugu.takeshita on 2026/01/08.
//

import SwiftUI
import UniformTypeIdentifiers

/// 設定ビュー
struct SettingsView: View {
    @EnvironmentObject var translationManager: TranslationManager
    @EnvironmentObject var downloader: ModelDownloader
    @AppStorage("modelPath") private var modelPath: String = ""
    @AppStorage("modelType") private var modelTypeRaw: String = ModelType.plamo.rawValue
    @State private var selectedDownloadIndex: Int = ModelDownloader.availableModels.firstIndex(where: { !$0.modelType.isLegacy }) ?? 0
    @State private var showLegacyInSelect: Bool = false
    @State private var showLegacyInDownload: Bool = false
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
                    let currentModels = downloadedModels.filter { !$0.modelType.isLegacy }
                    let legacyModels = downloadedModels.filter { $0.modelType.isLegacy }

                    if !currentModels.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(currentModels, id: \.fileName) { model in
                                modelSelectRow(model)
                            }
                        }
                    }

                    if !legacyModels.isEmpty {
                        DisclosureGroup(isExpanded: $showLegacyInSelect) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(legacyModels, id: \.fileName) { model in
                                    modelSelectRow(model)
                                }
                            }
                        } label: {
                            Text("旧モデルを表示")
                                .contentShape(Rectangle())
                                .onTapGesture { showLegacyInSelect.toggle() }
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

                    if modelType == .qwen35_0_8b {
                        Text("選択中のモデルはパラメータ数が少ないため高速ですが、翻訳品質や出力が不安定です")
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.top, 4)
                    }
                }
            }

            Section("モデルをダウンロード") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(0..<ModelDownloader.availableModels.count, id: \.self) { index in
                        let model = ModelDownloader.availableModels[index]
                        if !model.modelType.isLegacy {
                            modelDownloadRow(index: index, model: model)
                        }
                    }
                }

                DisclosureGroup(isExpanded: $showLegacyInDownload) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(0..<ModelDownloader.availableModels.count, id: \.self) { index in
                            let model = ModelDownloader.availableModels[index]
                            if model.modelType.isLegacy {
                                modelDownloadRow(index: index, model: model)
                            }
                        }
                    }
                } label: {
                    Text("旧モデルを表示")
                        .contentShape(Rectangle())
                        .onTapGesture { showLegacyInDownload.toggle() }
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

    @ViewBuilder
    private func modelSelectRow(_ model: ModelDownloader.ModelInfo) -> some View {
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

    @ViewBuilder
    private func modelDownloadRow(index: Int, model: ModelDownloader.ModelInfo) -> some View {
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

