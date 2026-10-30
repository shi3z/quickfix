# PNG Quick Fix

**English** | [日本語](#日本語)

A small macOS tool: double-click a PNG to open it, make quick fixes, and save over the original.

## Features

- Preview, rotate left/right
- Color adjustment (brightness / contrast / saturation / color temperature)
- Drag to mosaic any region (adjustable coarseness)
- Faces are detected automatically (Apple Vision) and mosaicked on open; click the frame of any face that should *not* be mosaicked to undo it
- Undo (⌘Z), overwrite save (⌘S)

## Requirements

- macOS 12 or later (tested on Apple Silicon)
- Xcode Command Line Tools (`xcode-select --install`)

## Install

```sh
git clone https://github.com/shi3z/quickfix.git
cd quickfix
./build.sh
```

This builds `~/Applications/PNG Quick Fix.app`.

### Open PNGs by double-clicking

Make it the default app for PNG, either with:

```sh
"$HOME/Applications/PNG Quick Fix.app/Contents/MacOS/PNGQuickFix" --set-default
```

or in Finder: right-click a PNG → Get Info → Open with → choose PNG Quick Fix → Change All.

To go back to Preview, repeat the same steps and choose Preview.

## Usage

| Action | Result |
| --- | --- |
| Drag on the image | Mosaic the region (cyan frame) |
| Click a face frame (orange) | Remove its mosaic (dashed green). Click again to re-apply |
| Click a manual frame | Delete it |
| Re-detect faces | Run detection again, e.g. after rotating |
| Save (⌘S) | Overwrite the original file |

## Notes

- Saving **overwrites** the original file and cannot be undone afterwards. Keep a copy if you need the original.
- Face detection may miss small or profile faces; mosaic them manually by dragging.
- Metadata (EXIF etc.) is not preserved on save.

## License

[Apache License 2.0](LICENSE)

---

## 日本語

PNG をダブルクリックして開き、簡単な修正をして上書き保存できる macOS 用ツールです。

### 機能

- プレビュー、左右回転
- カラー調整(明るさ / コントラスト / 彩度 / 色温度)
- ドラッグした範囲にモザイク(粗さ調整可)
- 開いた時点で人の顔(Vision フレームワーク)に自動でモザイクを掛け、必要ない顔の枠だけクリックして解除
- 取り消し(⌘Z)、上書き保存(⌘S)

### 動作環境

- macOS 12 以降(Apple Silicon で動作確認)
- Xcode Command Line Tools(`xcode-select --install`)

### インストール

```sh
git clone https://github.com/shi3z/quickfix.git
cd quickfix
./build.sh
```

`~/Applications/PNG Quick Fix.app` が作られます。

#### PNG のダブルクリックで開くようにする

次のどちらかで、PNG の既定アプリにします。

```sh
"$HOME/Applications/PNG Quick Fix.app/Contents/MacOS/PNGQuickFix" --set-default
```

または Finder で PNG を右クリック →「情報を見る」→「このアプリケーションで開く」で PNG Quick Fix を選び、「すべてを変更」。

プレビュー.app に戻すには、同じ手順でプレビューを選んでください。

### 使い方

| 操作 | 内容 |
| --- | --- |
| 画像をドラッグ | 範囲にモザイク(水色の枠) |
| 顔の枠(橙)をクリック | モザイク解除(緑の点線)。もう一度で再適用 |
| 手動の枠をクリック | 枠を削除 |
| 顔を再検出 | 回転した後などにやり直す |
| 上書き保存 (⌘S) | 元ファイルに上書き |

### 注意

- 保存は元ファイルを**上書き**します。保存後は保存前の状態に戻せません。
- 顔検出は小さい顔や横顔を取りこぼすことがあります。その場合は手動で範囲を指定してください。
- 保存時にメタデータ(EXIF 等)は引き継がれません。

### ライセンス

[Apache License 2.0](LICENSE)
