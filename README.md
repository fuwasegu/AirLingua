# AirLingua

ローカル LLM を使った macOS 向け翻訳アプリ。右クリックメニューから即座に翻訳できます。

## 特徴

- **完全ローカル処理** - インターネット接続不要、プライバシー安全
- **右クリックで翻訳** - テキスト選択 → 右クリック → 「AirLingua: 日本語に翻訳」
- **メニューバー常駐** - 軽量でいつでもアクセス可能
- **複数モデル対応** - PLaMo-2-translate / ELYZA-JP-8B

## インストール

### Homebrew

```bash
brew tap fuwasegu/tap
brew install --cask airlingua
```

### 手動インストール

[Releases](https://github.com/fuwasegu/AirLingua/releases) から最新の ZIP をダウンロードして、`AirLingua.app` を `/Applications` に移動。

## 必要条件

- macOS 14.0 (Sonoma) 以上
- [llama.cpp](https://github.com/ggerganov/llama.cpp) がインストール済み

```bash
brew install llama.cpp
```

## 使い方

1. アプリを起動（メニューバーに常駐）
2. 設定からモデルをダウンロード
3. テキストを選択して右クリック →「サービス」→「AirLingua: 日本語に翻訳」

## 対応モデル

| モデル | サイズ | ライセンス |
|--------|--------|------------|
| PLaMo-2-translate | ~4.6-5.5 GB | 個人利用のみ |
| ELYZA-JP-8B | ~4.9 GB | 商用利用可 (Llama 3) |

## ライセンス

MIT License
