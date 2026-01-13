//
//  LocalTranslateApp.swift
//  LocalTranslate
//
//  Created by hirosugu.takeshita on 2026/01/08.
//

import SwiftUI

@main
struct LocalTranslateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // メニューバー常駐型 - MenuBarExtra でアプリを維持
        // 実際のメニューは AppDelegate で管理
        // 設定画面も AppDelegate.openSettings() で管理
        MenuBarExtra {
            EmptyView()
        } label: {
            EmptyView()
        }
        .menuBarExtraStyle(.menu)
    }
}
