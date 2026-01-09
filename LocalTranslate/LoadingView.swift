//
//  LoadingView.swift
//  LocalTranslate
//

import SwiftUI

/// 翻訳中のローディング表示
struct LoadingView: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            Text("翻訳中...")
                .font(.system(size: 14))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

#Preview {
    LoadingView()
        .padding()
}
