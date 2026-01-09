//
//  MemoryMonitor.swift
//  LocalTranslate
//
//  Created by Claude on 2026/01/09.
//

import Foundation
import Combine
import Darwin

/// アプリのメモリ使用量を監視するクラス
final class MemoryMonitor: ObservableObject {
    @Published var memoryUsageMB: Double = 0
    private var timer: Timer?

    init() {
        startMonitoring()
    }

    func startMonitoring() {
        updateMemoryUsage()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateMemoryUsage()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func updateMemoryUsage() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            let bytes = info.resident_size
            DispatchQueue.main.async {
                self.memoryUsageMB = Double(bytes) / 1024 / 1024
            }
        }
    }

    /// フォーマット済みの文字列を返す
    var formattedUsage: String {
        if memoryUsageMB >= 1024 {
            return String(format: "%.2f GB", memoryUsageMB / 1024)
        }
        return String(format: "%.1f MB", memoryUsageMB)
    }

    deinit {
        stopMonitoring()
    }
}
