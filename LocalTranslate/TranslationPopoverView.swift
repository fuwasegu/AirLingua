import SwiftUI

/// 翻訳結果を表示するポップオーバービュー
struct TranslationPopoverView: View {
    let inputText: String
    let targetLanguage: Language
    let translationManager: TranslationManager
    let onClose: () -> Void

    @State private var translatedText: String = ""
    @State private var isTranslating: Bool = true
    @State private var errorMessage: String?
    @State private var duration: TimeInterval?
    @State private var detectedLanguage: Language?

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            HStack {
                Text("PLaMo 翻訳")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // コンテンツ
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // 原文
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("原文")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if let detected = detectedLanguage {
                                Text("(\(detected.localizedName))")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                        Text(inputText)
                            .font(.body)
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                    }

                    // 矢印
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.down")
                            .foregroundColor(.secondary)
                        Text(targetLanguage.localizedName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }

                    // 翻訳結果
                    VStack(alignment: .leading, spacing: 4) {
                        Text("翻訳結果")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if isTranslating {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("翻訳中...")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                        } else if let error = errorMessage {
                            Text(error)
                                .font(.body)
                                .foregroundColor(.red)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(6)
                        } else {
                            Text(translatedText)
                                .font(.body)
                                .foregroundColor(.primary)
                                .textSelection(.enabled)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)
                        }
                    }
                }
                .padding(16)
            }

            Divider()

            // フッター
            HStack {
                if let time = duration {
                    Text(String(format: "%.2f秒", time))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // コピーボタン
                Button(action: copyToClipboard) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text("コピー")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(translatedText.isEmpty || isTranslating)

                // 貼り付けボタン（選択中のテキストを置換）
                Button(action: pasteAndReplace) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.clipboard")
                        Text("貼り付け")
                    }
                    .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .disabled(translatedText.isEmpty || isTranslating)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))

            // ライセンス表記
            HStack {
                Spacer()
                Text("Built with PLaMo")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
                Spacer()
            }
            .padding(.bottom, 6)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 400, height: 300)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
        .task {
            await performTranslation()
        }
    }

    private func performTranslation() async {
        isTranslating = true
        errorMessage = nil

        // モデルが読み込まれていない場合は読み込む
        if !translationManager.isReady {
            await translationManager.loadModel()
        }

        do {
            let result = try await translationManager.translate(
                inputText,
                from: nil,  // 自動検出
                to: targetLanguage
            )
            await MainActor.run {
                translatedText = result.translatedText
                duration = result.duration
                detectedLanguage = result.detectedSourceLanguage
                isTranslating = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isTranslating = false
            }
        }
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(translatedText, forType: .string)
    }

    private func pasteAndReplace() {
        // クリップボードにコピーしてから閉じる
        // ユーザーは Cmd+V で貼り付けできる
        copyToClipboard()
        onClose()

        // キーストロークをシミュレートして自動貼り付け（オプショナル）
        // これはアクセシビリティ権限が必要
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            simulatePaste()
        }
    }
}

/// Cmd+V キーストロークをシミュレート
private func simulatePaste() {
    let source = CGEventSource(stateID: .hidSystemState)

    // Cmd キーを押す
    let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
    cmdDown?.flags = .maskCommand

    // V キーを押す
    let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
    vDown?.flags = .maskCommand

    // V キーを離す
    let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
    vUp?.flags = .maskCommand

    // Cmd キーを離す
    let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)

    // イベントを送信
    cmdDown?.post(tap: .cghidEventTap)
    vDown?.post(tap: .cghidEventTap)
    vUp?.post(tap: .cghidEventTap)
    cmdUp?.post(tap: .cghidEventTap)
}

#Preview {
    TranslationPopoverView(
        inputText: "Hello, World! This is a test message for translation.",
        targetLanguage: .japanese,
        translationManager: TranslationManager(),
        onClose: {}
    )
}
