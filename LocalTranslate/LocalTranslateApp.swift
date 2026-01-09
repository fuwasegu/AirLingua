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
        // メニューバー常駐型なのでウィンドウは表示しない
        Settings {
            SettingsView()
                .environmentObject(appDelegate.translationManager)
        }
    }
}
