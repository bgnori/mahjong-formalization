# ブラウザ版 待ち形分類器

[examples/irreducible_wait_classifier.py](../examples/irreducible_wait_classifier.py) の JavaScript 移植です。入力した牌姿はブラウザ内だけで処理され、サーバには送信されません。

## ローカルで試す

```sh
python3 -m http.server 8000 --directory web
# http://localhost:8000/ を開く
```

`index.html` はビルド不要の通常の `<script>` 構成なので、ファイルを直接ブラウザで開いても動きます。

牌姿は `1223m111z` のような形式(4 / 7 / 10 / 13 枚、`0` は赤5)で入力します。

## 開発

- `classification-table.js` は生成物です。分類表を更新したら `python3 web/generate_table.py` で再生成します。
- テスト: `node web/test_classifier.js`(`reports/` の全代表牌姿が 967 分類に一致することなどを確認します)。
