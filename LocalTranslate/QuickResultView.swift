//
//  QuickResultView.swift
//  LocalTranslate
//

import SwiftUI

/// クイック翻訳結果表示ビュー
struct QuickResultView: View {
    let text: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("翻訳完了")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            ScrollView {
                Text(text)
                    .font(.system(size: 14))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Image(systemName: "doc.on.clipboard")
                    .font(.caption2)
                Text("クリップボードにコピー済み")
                    .font(.caption2)
                Spacer()
            }
            .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(width: 350, height: 150)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

#Preview {
    QuickResultView(text: "こんにちは、お元気ですか？これはテスト翻訳です。") {
        print("closed")
    }
    .padding()
}
