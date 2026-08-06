# 日本語フォントの同梱について

## なぜ同梱するのか

Flutter Web の CanvasKit レンダラは、**ブラウザのシステムフォントを使わない**。
アプリに無いグリフに出会うたび、実行時に `https://fonts.gstatic.com/s/` から
Noto フォントをダウンロードして描画する。

同梱前のデプロイ済みビルドを調べたところ、次の状態だった。

| 項目 | 実測値 |
| --- | --- |
| レンダラ | canvaskit |
| 同梱フォント | MaterialIcons のみ |
| 日本語グリフ | 実行時に gstatic から取得 |
| Noto Sans JP の分割数 | 124 スライス（1 つ約 44KB） |

このため、次の問題が起きていた。

- 取得が完了するまで日本語が**豆腐（□）**で描画される。
  特に最初に表示されるログイン画面はキャッシュが空なので目立つ。
- `flutter_service_worker.js` はクロスオリジンの gstatic をキャッシュしないため、
  キャッシュが切れるたびに再発する。
- プロキシやファイアウォールが `fonts.gstatic.com` を遮断している環境では、
  **日本語が恒久的に豆腐のまま**になる。

なお `--web-renderer html` による回避は、Flutter 3.29 で HTML レンダラが
削除されたため使えない（本リポジトリの開発環境は 3.44.8）。

## 収録範囲

`frontend/assets/fonts/NotoSansJP-{Regular,Bold}.ttf`

- 元フォント: Noto Sans JP v56（Google Fonts 配布の static TTF）
- ライセンス: SIL Open Font License 1.1
- 収録文字数: 7,661 字 / cmap 7,326 グリフ
  - JIS X 0208（第1・第2水準漢字、かな、約物）
  - ASCII、Latin-1 補助
  - 一般句読点、通貨記号、文字様記号、矢印、幾何学模様
  - CJK 記号、半角・全角形

フル版は Regular + Bold で 11MB あるが、上記サブセットで **4.6MB** に収まる。
CJK 統合漢字ブロック全体（U+4E00-9FFF）を入れると 8.8MB になり削減効果が薄いため、
実用範囲である JIS X 0208 に絞っている。

## 再生成の手順

異体字などで不足が出た場合は、以下でサブセットを作り直す。

```bash
pip install fonttools brotli

# 1. 元フォントを取得（URL は Google Fonts の css2 API から得られる）
curl -A "Mozilla/4.0" \
  "https://fonts.googleapis.com/css2?family=Noto+Sans+JP:wght@400;700"
# 上で表示された .ttf の URL を curl で保存する
#   -> NotoSansJP-Regular.ttf / NotoSansJP-Bold.ttf

# 2. 収録したい文字の一覧を作る
python3 - <<'PY'
chars = set()
for hi in range(0xA1, 0xFF):          # JIS X 0208 を EUC-JP 経由で列挙
    for lo in range(0xA1, 0xFF):
        try:
            chars.add(bytes([hi, lo]).decode('euc_jp'))
        except Exception:
            pass
for a, b in [(0x20, 0x7F), (0xA0, 0x100), (0x2000, 0x2070), (0x20A0, 0x20C0),
             (0x2100, 0x2150), (0x2190, 0x2200), (0x25A0, 0x2600),
             (0x3000, 0x3100), (0xFF00, 0xFFF0)]:
    chars |= {chr(c) for c in range(a, b)}
open('subset.txt', 'w', encoding='utf-8').write(''.join(sorted(chars)))
PY

# 3. サブセット化して frontend/assets/fonts/ に配置
for w in Regular Bold; do
  pyftsubset "NotoSansJP-$w.ttf" --text-file=subset.txt --layout-features='*' \
    --output-file="frontend/assets/fonts/NotoSansJP-$w.ttf"
done
```

## 収録漏れの確認

リポジトリ内で実際に使っている文字がすべて収録されているかを検査する。

```bash
python3 - <<'PY'
import glob
from fontTools.ttLib import TTFont

for weight in ('Regular', 'Bold'):
    font = TTFont(f'frontend/assets/fonts/NotoSansJP-{weight}.ttf')
    cmap = set()
    for table in font['cmap'].tables:
        cmap |= set(table.cmap.keys())

    text = ''
    for path in (glob.glob('frontend/lib/**/*.dart', recursive=True)
                 + glob.glob('backend/app/**/*.py', recursive=True)
                 + glob.glob('supabase/migrations/*.sql')
                 + ['frontend/web/index.html', 'frontend/web/manifest.json']):
        text += open(path, encoding='utf-8').read()

    missing = sorted(c for c in set(text) if ord(c) > 0x7F and ord(c) not in cmap)
    print(weight, 'missing:', ''.join(missing) if missing else 'none')
PY
```

## 注意点

- `fontFamily: 'monospace'` を明示している箇所は、テーマの `fontFamily` 指定が
  効かない。そのラベルに日本語を含む場合は
  `fontFamilyFallback: const ['NotoSansJP']` を併記すること。
- ユーザーの表示名など、**アプリ側で内容を決められない文字列**には
  JIS X 0208 外の漢字が来る可能性がある。その場合だけは従来どおり
  gstatic からの遅延取得にフォールバックする（表示はされるが一瞬遅れる）。
