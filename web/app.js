(function () {
  const input = document.getElementById("hand");
  const result = document.getElementById("result");
  const examples = document.getElementById("examples");
  const PROFILES = {
    healthy: "healthy (問題なし)",
    suppressionOnly: "suppressionOnly (待ちの抑制あり)",
    ambiguityOnly: "ambiguityOnly (分解の冗長あり)",
    both: "both (抑制・冗長の両方)",
  };

  function el(tag, text, className) {
    const e = document.createElement(tag);
    if (text !== undefined) e.textContent = text;
    if (className) e.className = className;
    return e;
  }

  function row(dl, label, value) {
    dl.append(el("dt", label));
    const dd = el("dd");
    if (value instanceof Node) dd.append(value);
    else dd.textContent = value;
    dl.append(dd);
  }

  function render() {
    result.replaceChildren();
    const text = input.value.trim();
    if (!text) return;
    try {
      const r = WaitClassifier.classify(text);
      const dl = el("dl");
      row(dl, "分類 ID", String(r.classificationId));
      row(dl, "病理プロファイル", PROFILES[r.pathologyProfile]);
      const waits = el("span");
      r.waits.forEach((w) => waits.append(el("span", WaitClassifier.TILE_NAMES[w], "tile")));
      row(dl, "待ち", waits);
      row(dl, "waitDecompositionCodes", el("code", "[" + r.waitDecompositionCodes.join(", ") + "]"));
      result.append(dl);
    } catch (e) {
      if (!(e instanceof WaitClassifier.WaitClassificationError)) throw e;
      result.append(el("p", e.message, "error"));
    }
  }

  ["1223m", "1114m", "5555666p", "55666677m11s", "1111234555p", "1111222234444m", "89p11123456777s", "2333345777p"].forEach((h) => {
    const b = el("button", h);
    b.type = "button";
    b.addEventListener("click", () => { input.value = h; render(); });
    examples.append(b);
  });

  input.addEventListener("input", render);
})();
