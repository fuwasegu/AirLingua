//
//  AppDelegate.swift
//  LocalTranslate
//

import AppKit
import SwiftUI
import Combine
import Carbon

/// アプリケーションデリゲート
/// - メニューバー常駐
/// - macOS サービス（右クリックメニュー）の登録
/// - 翻訳マネージャーの管理
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let translationManager = TranslationManager()
    let modelDownloader = ModelDownloader()
    private let memoryMonitor = MemoryMonitor()

    /// メニューバーアイテム
    private var statusItem: NSStatusItem?

    /// グローバルホットキー（Carbon）
    private var japaneseHotKeyRef: EventHotKeyRef?
    private var englishHotKeyRef: EventHotKeyRef?
    private var carbonEventHandler: EventHandlerRef?

    /// メモリ表示用メニューアイテム
    private var memoryMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // メニューバー常駐アプリとして設定
        NSApp.setActivationPolicy(.accessory)

        // メニューバーアイコンを設定
        setupStatusBar()

        // macOS サービスの登録
        NSApp.servicesProvider = self

        // サービスメニューを更新
        NSUpdateDynamicServices()

        // モデル切り替え時にステータスバーを更新
        translationManager.onModelLoaded = { [weak self] in
            self?.updateStatusBarMenu()
        }

        // グローバルホットキーを登録
        setupGlobalHotkey()

        // アクセシビリティ権限チェック（アップデートで署名が変わると権限が切れる）
        checkAccessibilityPermission()

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
        if let ref = japaneseHotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = englishHotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = carbonEventHandler { RemoveEventHandler(ref) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        print("DEBUG: applicationShouldTerminateAfterLastWindowClosed called, returning false")
        return false
    }

    /// アクセシビリティ権限をチェックし、必要に応じてユーザーに案内する
    private func checkAccessibilityPermission() {
        guard !AXIsProcessTrusted() else { return }

        // 一度も許可されたことがない場合はシステムダイアログで案内
        if !UserDefaults.standard.bool(forKey: "accessibilityPrompted") {
            UserDefaults.standard.set(true, forKey: "accessibilityPrompted")
            AXIsProcessTrustedWithOptions(
                [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            )
            return
        }

        // 以前は許可されていたのに無効になった場合（アップデートで署名が変わった等）
        let alert = NSAlert()
        alert.messageText = "アクセシビリティ権限の再設定が必要です"
        alert.informativeText = "アプリのアップデートにより権限が無効になりました。\n「システム設定」→「アクセシビリティ」で AirLingua を一度削除してから再度追加してください。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "設定を開く")
        alert.addButton(withTitle: "後で")

        if alert.runModal() == .alertFirstButtonReturn {
            AXIsProcessTrustedWithOptions(
                [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            )
        }
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
        menu.delegate = self

        // タイトル + バージョン
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let titleItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let titleString = NSMutableAttributedString(
            string: "AirLingua",
            attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)]
        )
        titleString.append(NSAttributedString(
            string: "  v\(version)",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
        ))
        titleItem.attributedTitle = titleString
        menu.addItem(titleItem)

        // ステータス情報（小さめのセカンダリカラー）
        let statusAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]

        let modelItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        modelItem.attributedTitle = NSAttributedString(
            string: "  モデル: \(translationManager.modelType.displayName)",
            attributes: statusAttrs
        )
        menu.addItem(modelItem)

        let memoryItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        memoryItem.attributedTitle = NSAttributedString(
            string: "  メモリ: \(memoryMonitor.formattedUsage)",
            attributes: statusAttrs
        )
        menu.addItem(memoryItem)
        self.memoryMenuItem = memoryItem

        if translationManager.modelType == .plamo {
            let licenseItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            licenseItem.attributedTitle = NSAttributedString(
                string: "  ⚠️ 個人利用のみ",
                attributes: statusAttrs
            )
            menu.addItem(licenseItem)
        }

        menu.addItem(NSMenuItem.separator())

        // ショートカット案内（セクションヘッダー + キー表示）
        let shortcutHeader = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        shortcutHeader.attributedTitle = NSAttributedString(
            string: "ショートカット",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        menu.addItem(shortcutHeader)

        let shortcutAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
        ]

        let jpShortcut = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        jpShortcut.attributedTitle = NSAttributedString(
            string: "  ⌃⌥J  日本語に翻訳",
            attributes: shortcutAttrs
        )
        menu.addItem(jpShortcut)

        let enShortcut = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        enShortcut.attributedTitle = NSAttributedString(
            string: "  ⌃⌥E  英語に翻訳",
            attributes: shortcutAttrs
        )
        menu.addItem(enShortcut)

        if AXIsProcessTrusted() {
            let hintItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            hintItem.attributedTitle = NSAttributedString(
                string: "  テキストを選択してショートカットキーを押す",
                attributes: statusAttrs
            )
            menu.addItem(hintItem)
        } else {
            let hintItem = NSMenuItem(title: "", action: #selector(openAccessibilitySettings), keyEquivalent: "")
            hintItem.attributedTitle = NSAttributedString(
                string: "  ⚠ アクセシビリティ権限が必要です",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.systemOrange,
                ]
            )
            menu.addItem(hintItem)
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

    /// 設定ウィンドウ（strong参照で保持）
    private var settingsWindow: NSWindow?

    @objc private func openAccessibilitySettings() {
        AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        )
    }

    @objc private func openSettings() {
        // 既存のウィンドウがあれば前面に
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // 設定ビューを作成
        let settingsView = SettingsView()
            .environmentObject(translationManager)
            .environmentObject(modelDownloader)

        let hostingView = NSHostingView(rootView: settingsView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 550, height: 550),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "AirLingua 設定"
        window.contentView = hostingView
        window.isReleasedWhenClosed = false  // 閉じても解放しない
        window.center()
        window.makeKeyAndOrderFront(nil)

        self.settingsWindow = window

        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Global Hotkey (Carbon RegisterEventHotKey)

    /// グローバルホットキーを登録（Carbon API — アクセシビリティ権限不要）
    private func setupGlobalHotkey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let event = event, let userData = userData else {
                    return OSStatus(eventNotHandledErr)
                }

                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()

                switch hotKeyID.id {
                case 1: delegate.translateSelectedText(to: .japanese)
                case 2: delegate.translateSelectedText(to: .english)
                default: break
                }

                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &carbonEventHandler
        )

        // ⌃⌥J → 日本語に翻訳
        var jpID = EventHotKeyID(signature: OSType(0x414C4E47), id: 1)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_J),
            UInt32(controlKey | optionKey),
            jpID,
            GetApplicationEventTarget(),
            0,
            &japaneseHotKeyRef
        )

        // ⌃⌥E → 英語に翻訳
        var enID = EventHotKeyID(signature: OSType(0x414C4E47), id: 2)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_E),
            UInt32(controlKey | optionKey),
            enID,
            GetApplicationEventTarget(),
            0,
            &englishHotKeyRef
        )
    }

    /// 選択テキストを取得して翻訳
    /// - AX API で選択テキスト直接取得 → 翻訳
    /// - AX 失敗時は ⌘C シミュレートでフォールバック
    /// - いずれも失敗した場合は何もしない
    nonisolated private func translateSelectedText(to language: Language) {
        // 1. AX API で選択テキストを直接取得（権限があれば成功、なければ nil）
        let axText = getSelectedTextViaAccessibility()

        if let axText, !axText.isEmpty {
            Task { @MainActor [weak self] in
                await self?.quickTranslate(text: axText, to: language)
            }
            return
        }

        // 2. ⌘C シミュレートで選択テキストをコピー（権限不足なら空振りする）
        let savedChangeCount = NSPasteboard.general.changeCount

        let source = CGEventSource(stateID: .privateState)
        let cKeyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
        cKeyDown?.flags = .maskCommand
        cKeyDown?.post(tap: .cghidEventTap)
        let cKeyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        cKeyUp?.flags = .maskCommand
        cKeyUp?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if NSPasteboard.general.changeCount != savedChangeCount {
                // ⌘C 成功: コピーされたテキストを翻訳
                if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
                    Task { @MainActor [weak self] in
                        await self?.quickTranslate(text: text, to: language)
                    }
                    return
                }
            }

            // AX も ⌘C も失敗: 選択テキストが取得できなかったので何もしない
        }
    }

    /// Accessibility API でフォーカス中の要素から選択テキストを取得
    nonisolated private func getSelectedTextViaAccessibility() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        let focusResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        guard focusResult == .success, let element = focusedElement else { return nil }

        var selectedText: AnyObject?
        let textResult = AXUIElementCopyAttributeValue(
            element as! AXUIElement,
            kAXSelectedTextAttribute as CFString,
            &selectedText
        )
        guard textResult == .success, let text = selectedText as? String else { return nil }
        return text
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

    /// クイック翻訳（ストリーミング表示）
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

        let stream = translationManager.translateStream(text, from: nil, to: targetLanguage)

        do {
            var fullText = ""
            var isFirstChunk = true

            for try await chunk in stream {
                fullText += chunk

                if isFirstChunk {
                    // 最初のチャンクが来たらローディングを消して結果ウィンドウを表示
                    hideLoading()
                    showQuickResult("", at: displayPosition)
                    isFirstChunk = false
                }

                // NSTextView を直接更新（AppKit なので即反映）
                resultTextView?.string = fullText
                currentResultText = fullText
            }

            // ストリームが空だった場合
            if isFirstChunk {
                hideLoading()
                showQuickResult("", at: displayPosition)
            }

            // 完了後に最終クリーニング
            let cleaned = translationManager.cleanOutput(fullText)
            resultTextView?.string = cleaned
            currentResultText = cleaned
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
        window.isReleasedWhenClosed = false

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
    /// ストリーミング更新用の NSTextView 参照
    private weak var resultTextView: NSTextView?
    /// 現在表示中の翻訳結果テキスト
    private var currentResultText: String = ""

    /// 結果ウィンドウを安全に閉じる
    private func closeResultWindow() {
        resultWindow?.orderOut(nil)
        resultWindow = nil
        currentResultText = ""
    }

    /// クイック翻訳結果を表示（純粋な AppKit）
    private func showQuickResult(_ text: String, at position: NSPoint) {
        // 既存の結果ウィンドウを閉じる
        closeResultWindow()

        // 翻訳結果を保存（コピー用）
        currentResultText = text

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
        let closeButton = HoverButton(frame: NSRect(x: windowWidth - 32, y: headerY, width: 20, height: 20))
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "閉じる")
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeResultButtonClicked)
        closeButton.autoresizingMask = [.minXMargin, .minYMargin]
        containerView.addSubview(closeButton)

        // コピーボタン（右上、閉じるボタンの左）
        let copyButton = HoverButton(frame: .zero)
        copyButton.bezelStyle = .inline
        copyButton.isBordered = false
        copyButton.title = "Copy"
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "コピー")
        copyButton.imagePosition = .imageLeading
        copyButton.contentTintColor = .secondaryLabelColor
        copyButton.font = NSFont.systemFont(ofSize: 11)
        copyButton.target = self
        copyButton.action = #selector(copyResultButtonClicked)
        copyButton.sizeToFit()
        copyButton.frame.size.height = 20
        copyButton.frame.origin = NSPoint(
            x: closeButton.frame.minX - copyButton.frame.width,
            y: headerY
        )
        copyButton.autoresizingMask = [.minXMargin, .minYMargin]
        containerView.addSubview(copyButton)

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

        self.resultTextView = textView

        // リサイズ可能なウィンドウ
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.contentView = containerView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
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

    @objc private func copyResultButtonClicked(_ sender: NSButton) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentResultText, forType: .string)

        // ボタンのテキストを一時的に変更してフィードバック
        let originalTitle = sender.title
        let rightEdge = sender.frame.maxX
        let originalY = sender.frame.origin.y
        let originalHeight = sender.frame.height
        sender.title = "Copied!"
        sender.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        sender.contentTintColor = .systemGreen
        sender.sizeToFit()
        sender.frame = NSRect(x: rightEdge - sender.frame.width, y: originalY, width: sender.frame.width, height: originalHeight)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            sender.title = originalTitle
            sender.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
            sender.contentTintColor = .controlAccentColor
            sender.sizeToFit()
            sender.frame = NSRect(x: rightEdge - sender.frame.width, y: originalY, width: sender.frame.width, height: originalHeight)
        }
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

    /// モデル切り替え通知
    var onModelLoaded: (() -> Void)?

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
            onModelLoaded?()
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
        isLoading = false
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

    /// ストリーム完了後の最終クリーニング
    func cleanOutput(_ text: String) -> String {
        translator?.cleanOutput(text) ?? text
    }

    /// ストリーミング翻訳を実行
    func translateStream(
        _ text: String,
        from sourceLanguage: Language?,
        to targetLanguage: Language
    ) -> AsyncThrowingStream<String, Error> {
        guard let translator = translator else {
            return AsyncThrowingStream { $0.finish(throwing: TranslationError.modelNotLoaded) }
        }

        return translator.translateStream(text, from: sourceLanguage, to: targetLanguage)
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    /// メニューが開かれる直前に呼ばれる
    /// Note: NSMenuDelegate は nonisolated なので、MainActor プロパティへのアクセスは Task 経由で行う。
    /// AppKit はメインスレッドでコールバックを呼ぶため、Task は即座に実行される。
    nonisolated func menuWillOpen(_ menu: NSMenu) {
        Task { @MainActor in
            updateStatusBarMenu()
        }
    }
}
