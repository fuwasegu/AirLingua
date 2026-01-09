//
//  AppDelegate.swift
//  LocalTranslate
//

import AppKit
import SwiftUI
import Combine

/// アプリケーションデリゲート
/// - メニューバー常駐
/// - macOS サービス（右クリックメニュー）の登録
/// - 翻訳マネージャーの管理
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let translationManager = TranslationManager()

    /// メニューバーアイテム
    private var statusItem: NSStatusItem?

    /// ポップオーバーウィンドウ
    private var popoverWindow: NSWindow?
    private var popoverHostingView: NSHostingView<TranslationPopoverView>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // メニューバーアイコンを設定
        setupStatusBar()

        // macOS サービスの登録
        NSApp.servicesProvider = self

        // サービスメニューを更新
        NSUpdateDynamicServices()

        // モデルを自動ロード
        Task {
            await translationManager.loadModel()
            if translationManager.isReady {
                print("モデルのロード完了")
            } else {
                print("モデルのロード失敗: \(translationManager.errorMessage ?? "不明なエラー")")
            }
        }

        print("LocalTranslate サービスを登録しました")
    }

    func applicationWillTerminate(_ notification: Notification) {
        translationManager.unloadModel()
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "AirLingua")
        }

        updateStatusBarMenu()
    }

    /// メニューバーのメニューを更新
    private func updateStatusBarMenu() {
        let menu = NSMenu()

        // タイトル（モデル名）
        let titleItem = NSMenuItem(title: "AirLingua", action: nil, keyEquivalent: "")
        menu.addItem(titleItem)

        // 現在のモデル表示
        let modelItem = NSMenuItem(title: "モデル: \(translationManager.modelType.displayName)", action: nil, keyEquivalent: "")
        modelItem.isEnabled = false
        menu.addItem(modelItem)

        // ライセンス警告（PLaMoの場合）
        if translationManager.modelType == .plamo {
            let licenseItem = NSMenuItem(title: "⚠️ 個人利用のみ", action: nil, keyEquivalent: "")
            licenseItem.isEnabled = false
            menu.addItem(licenseItem)
        }

        menu.addItem(NSMenuItem.separator())

        // 設定
        let settingsItem = NSMenuItem(title: "設定...", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // 終了
        menu.addItem(NSMenuItem(title: "終了", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    /// 設定ウィンドウ
    private var settingsWindow: NSWindow?

    @objc private func openSettings() {
        // 既存のウィンドウがあれば前面に
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // 設定ビューを作成
        let settingsView = SettingsView()
            .environmentObject(translationManager)

        let hostingView = NSHostingView(rootView: settingsView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 550, height: 550),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "AirLingua 設定"
        window.contentView = hostingView
        window.center()
        window.makeKeyAndOrderFront(nil)

        self.settingsWindow = window

        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Services

    /// 「日本語に翻訳」サービス
    /// このメソッドは Info.plist の NSServices で定義されたサービスから呼び出される
    @objc func translateToJapanese(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        translateText(from: pboard, to: .japanese)
    }

    /// 「英語に翻訳」サービス
    @objc func translateToEnglish(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        translateText(from: pboard, to: .english)
    }

    /// 汎用翻訳サービス（クイック翻訳）
    private func translateText(from pboard: NSPasteboard, to targetLanguage: Language) {
        guard let text = pboard.string(forType: .string), !text.isEmpty else {
            return
        }

        // クイック翻訳を実行
        Task {
            await quickTranslate(text: text, to: targetLanguage)
        }
    }

    /// ローディングウィンドウ（強参照で保持）
    private var loadingWindow: NSWindow?

    /// クイック翻訳（結果だけ表示）
    private func quickTranslate(text: String, to targetLanguage: Language) async {
        // マウス位置を使用
        let displayPosition = NSEvent.mouseLocation

        // ローディング表示
        showLoading(at: displayPosition)

        // モデルがロードされていない場合は自動でロード
        if !translationManager.isReady {
            await translationManager.loadModel()
        }

        guard translationManager.isReady else {
            hideLoading()
            showQuickError("モデルが読み込まれていません。\n設定からモデルファイルを選択してください。")
            return
        }

        do {
            let result = try await translationManager.translate(text, from: nil, to: targetLanguage)

            hideLoading()

            // 結果をポップアップで表示
            showQuickResult(result.translatedText, at: displayPosition)
        } catch {
            hideLoading()
            showQuickError("翻訳エラー: \(error.localizedDescription)")
        }
    }

    /// ローディング表示（純粋な AppKit で実装）
    private func showLoading(at position: NSPoint) {
        hideLoading()

        // 背景ビュー
        let containerView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 150, height: 50))
        containerView.material = .popover
        containerView.blendingMode = .behindWindow
        containerView.state = .active
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 10

        // スピナー
        let spinner = NSProgressIndicator(frame: NSRect(x: 15, y: 12, width: 24, height: 24))
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)
        containerView.addSubview(spinner)

        // ラベル
        let label = NSTextField(labelWithString: "翻訳中...")
        label.frame = NSRect(x: 45, y: 15, width: 90, height: 20)
        label.font = NSFont.systemFont(ofSize: 14)
        label.textColor = .labelColor
        containerView.addSubview(label)

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 150, height: 50),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentView = containerView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = true

        window.setFrameOrigin(NSPoint(
            x: position.x - 75,
            y: position.y - 70
        ))
        window.orderFront(nil)

        self.loadingWindow = window
    }

    /// ローディングを非表示
    private func hideLoading() {
        loadingWindow?.orderOut(nil)
        loadingWindow = nil
    }

    /// エラー表示
    private func showQuickError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "AirLingua"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// 結果ウィンドウ
    private var resultWindow: NSPanel?

    /// 結果ウィンドウを安全に閉じる
    private func closeResultWindow() {
        resultWindow?.orderOut(nil)
        resultWindow = nil
    }

    /// クイック翻訳結果を表示（純粋な AppKit）
    private func showQuickResult(_ text: String, at position: NSPoint) {
        // 既存の結果ウィンドウを閉じる
        closeResultWindow()

        let windowWidth: CGFloat = 400
        let windowHeight: CGFloat = 250

        // 背景ビュー
        let containerView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight))
        containerView.material = .popover
        containerView.blendingMode = .behindWindow
        containerView.state = .active
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 12
        containerView.autoresizingMask = [.width, .height]

        // ヘッダー（上部に固定）
        let headerY = windowHeight - 32
        let checkIcon = NSImageView(frame: NSRect(x: 12, y: headerY, width: 20, height: 20))
        checkIcon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
        checkIcon.contentTintColor = .systemGreen
        checkIcon.autoresizingMask = [.minYMargin]
        containerView.addSubview(checkIcon)

        let headerLabel = NSTextField(labelWithString: "翻訳完了")
        headerLabel.frame = NSRect(x: 36, y: headerY + 2, width: 80, height: 16)
        headerLabel.font = NSFont.systemFont(ofSize: 12)
        headerLabel.textColor = .secondaryLabelColor
        headerLabel.autoresizingMask = [.minYMargin]
        containerView.addSubview(headerLabel)

        // 閉じるボタン（右上に固定）
        let closeButton = NSButton(frame: NSRect(x: windowWidth - 32, y: headerY, width: 20, height: 20))
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "閉じる")
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeResultButtonClicked)
        closeButton.autoresizingMask = [.minXMargin, .minYMargin]
        containerView.addSubview(closeButton)

        // 区切り線（上部に固定）
        let separatorY = windowHeight - 40
        let separator = NSBox(frame: NSRect(x: 12, y: separatorY, width: windowWidth - 24, height: 1))
        separator.boxType = .separator
        separator.autoresizingMask = [.width, .minYMargin]
        containerView.addSubview(separator)

        // 翻訳結果テキスト（リサイズに追従）
        let scrollView = NSScrollView(frame: NSRect(x: 12, y: 12, width: windowWidth - 24, height: windowHeight - 60))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false  // スクロールバーを常に表示
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.autoresizingMask = [.width, .height]

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: windowWidth - 24, height: windowHeight - 60))
        textView.string = text
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.autoresizingMask = [.width]
        scrollView.documentView = textView
        containerView.addSubview(scrollView)

        // リサイズ可能なウィンドウ
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        window.title = "翻訳結果"
        window.contentView = containerView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 300, height: 150)  // 最小サイズ

        // 指定位置に表示（ウィンドウ中央がマウス位置付近に）
        window.setFrameOrigin(NSPoint(
            x: position.x - windowWidth / 2,
            y: position.y - windowHeight - 20
        ))
        window.orderFront(nil)

        self.resultWindow = window
    }

    @objc private func closeResultButtonClicked() {
        closeResultWindow()
    }

    // MARK: - Popover

    /// イベントモニター
    private var eventMonitor: Any?

    /// 翻訳ポップオーバーを表示
    func showPopover(with text: String, targetLanguage: Language) {
        // 既存のポップオーバーを閉じる
        closePopover()

        // ポップオーバービューを作成
        let popoverView = TranslationPopoverView(
            inputText: text,
            targetLanguage: targetLanguage,
            translationManager: translationManager,
            onClose: { [weak self] in
                self?.closePopover()
            }
        )

        let hostingView = NSHostingView(rootView: popoverView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)

        // ウィンドウを作成
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = true
        window.isMovableByWindowBackground = true

        // マウス位置に表示
        let mouseLocation = NSEvent.mouseLocation
        let screenFrame = NSScreen.main?.frame ?? .zero

        var windowOrigin = NSPoint(
            x: mouseLocation.x - 200,  // ウィンドウの中央をマウス位置に
            y: mouseLocation.y - 320   // マウスの少し下に表示
        )

        // 画面外にはみ出さないように調整
        windowOrigin.x = max(10, min(windowOrigin.x, screenFrame.width - 410))
        windowOrigin.y = max(10, min(windowOrigin.y, screenFrame.height - 310))

        window.setFrameOrigin(windowOrigin)
        window.makeKeyAndOrderFront(nil)

        self.popoverWindow = window
        self.popoverHostingView = hostingView

        // ウィンドウの外をクリックしたら閉じる
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            if let window = self?.popoverWindow,
               !window.frame.contains(NSEvent.mouseLocation) {
                self?.closePopover()
            }
            return event
        }
    }

    /// ポップオーバーを閉じる
    func closePopover() {
        // イベントモニターを解除
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }

        if let window = popoverWindow {
            window.contentView = nil
            window.close()
            popoverWindow = nil
        }
        popoverHostingView = nil
    }
}

// MARK: - Translation Manager

/// 翻訳マネージャー
/// 翻訳サービスのライフサイクル管理とステート管理
@MainActor
class TranslationManager: ObservableObject {
    @Published var isReady: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private var translator: TranslationService?

    /// モデルパス
    var modelPath: String {
        get { UserDefaults.standard.string(forKey: "modelPath") ?? defaultModelPath }
        set { UserDefaults.standard.set(newValue, forKey: "modelPath") }
    }

    /// モデルタイプ
    var modelType: ModelType {
        get {
            if let rawValue = UserDefaults.standard.string(forKey: "modelType"),
               let type = ModelType(rawValue: rawValue) {
                return type
            }
            return .plamo
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "modelType")
        }
    }

    /// デフォルトのモデルパス
    private var defaultModelPath: String {
        // アプリケーションサポートディレクトリ内のモデルを探す
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return ""
        }
        let modelDir = appSupport.appendingPathComponent("AirLingua/models")

        // .gguf ファイルを探す
        if let files = try? FileManager.default.contentsOfDirectory(atPath: modelDir.path) {
            if let ggufFile = files.first(where: { $0.hasSuffix(".gguf") }) {
                return modelDir.appendingPathComponent(ggufFile).path
            }
        }
        return ""
    }

    /// モデルを読み込む
    func loadModel() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        do {
            let path = modelPath
            guard FileManager.default.fileExists(atPath: path) else {
                throw TranslationError.modelLoadFailed(
                    underlying: NSError(
                        domain: "TranslationManager",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "モデルファイルが見つかりません: \(path)\n設定画面からモデルファイルを選択してください。"]
                    )
                )
            }

            let translator = PLaMoTranslator(modelPath: path, modelType: modelType)
            try await translator.loadModel()

            self.translator = translator
            isReady = true
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isReady = false
            isLoading = false
        }
    }

    /// モデルをアンロード
    func unloadModel() {
        translator?.unloadModel()
        translator = nil
        isReady = false
    }

    /// 翻訳を実行
    func translate(
        _ text: String,
        from sourceLanguage: Language?,
        to targetLanguage: Language
    ) async throws -> TranslationResult {
        guard let translator = translator else {
            throw TranslationError.modelNotLoaded
        }

        return try await translator.translate(text, from: sourceLanguage, to: targetLanguage)
    }
}
