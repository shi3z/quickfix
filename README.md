# PNG Quick Fix

PNG をダブルクリックして開き、簡単な修正をして上書き保存できる macOS 用ツールです。

## 機能

- プレビュー、左右回転
- カラー調整(明るさ / コントラスト / 彩度 / 色温度)
- ドラッグした範囲にモザイク(粗さ調整可)
- 開いた時点で人の顔(Vision フレームワーク)に自動でモザイクを掛け、必要ない顔の枠だけクリックして解除
- 取り消し(⌘Z)、上書き保存(⌘S)

## 動作環境

- macOS 12 以降(Apple Silicon で動作確認)
- Xcode Command Line Tools(`xcode-select --install`)

## インストール

```sh
git clone https://github.com/shi3z/quickfix.git
cd quickfix
./build.sh
```

`~/Applications/PNG Quick Fix.app` が作られます。

### PNG のダブルクリックで開くようにする

次のどちらかで、PNG の既定アプリにします。

```sh
"$HOME/Applications/PNG Quick Fix.app/Contents/MacOS/PNGQuickFix" --set-default
```

または Finder で PNG を右クリック →「情報を見る」→「このアプリケーションで開く」で PNG Quick Fix を選び、「すべてを変更」。

元のプレビューに戻すには、同じ手順でプレビュー.app を選んでください。

## 使い方

| 操作 | 内容 |
| --- | --- |
| 画像をドラッグ | 範囲にモザイク(水色の枠) |
| 顔の枠(橙)をクリック | モザイク解除(緑の点線)。もう一度で再適用 |
| 手動の枠をクリック | 枠を削除 |
| 顔を再検出 | 回転した後などにやり直す |
| 上書き保存 (⌘S) | 元ファイルに上書き |

## 注意

- 保存は元ファイルを**上書き**します。保存後は保存前の状態に戻せません。
- 顔検出は小さい顔や横顔を取りこぼすことがあります。その場合は手動で範囲を指定してください。
- 保存時にメタデータ(EXIF 等)は引き継がれません。

## ライセンス

[Apache License 2.0](LICENSE)
