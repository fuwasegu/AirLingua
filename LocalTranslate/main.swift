//
//  main.swift
//  LocalTranslate
//

import AppKit

let app = NSApplication.shared
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    app.delegate = delegate
}
app.run()
