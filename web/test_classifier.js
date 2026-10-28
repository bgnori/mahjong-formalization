// Run: node web/test_classifier.js
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const C = require("./classifier.js");
const T = require("./classification-table.js");

const reports = [
  [4, "four-tile-direct-report.json", 11],
  [7, "seven-tile-report.json", 49],
  [10, "ten-tile-report.json", 199],
  [13, "thirteen-tile-report.json", 708],
];
const seen = new Set();
for (const [size, file, expected] of reports) {
  const report = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "reports", file), "utf8"));
  const groups = report.irreducibleGroupsByWaitDecompositionCodes;
  assert.strictEqual(groups.length, expected);
  const table = T.codeLists[size].map((c) => c.join(","));
  for (const g of groups) {
    const r = C.classify(g.representativeTiles);
    assert.deepStrictEqual(r.waitDecompositionCodes, g.waitDecompositionCodes);
    assert.strictEqual(r.classificationId, T.idOffsets[size] + table.indexOf(g.waitDecompositionCodes.join(",")));
    seen.add(r.classificationId);
  }
}
assert.strictEqual(seen.size, 967);
for (let i = 0; i < 967; i++) assert(seen.has(i));

for (const h of ["1223m", "1223m111z", "1223m111222z", "1223m111222333z"]) {
  assert.strictEqual(C.classify(h).classificationId, 5);
}
assert.strictEqual(C.classify("1114m").classificationId, 967);
assert.strictEqual(C.classify("1114m").pathologyProfile, "healthy");
assert.strictEqual(C.classify("1111222234444m").pathologyProfile, "both");
assert.strictEqual(C.classify("89p11123456777s").pathologyProfile, "ambiguityOnly");
const a = C.classify("2333345777p"), b = C.classify("3335666678s");
assert.strictEqual(a.classificationId, b.classificationId);
assert.strictEqual(a.pathologyProfile, "healthy");
assert.strictEqual(b.pathologyProfile, "ambiguityOnly");
assert.deepStrictEqual(C.classify("3450m"), C.classify("3455m"));
assert.throws(() => C.classify("1111111m"), C.InvalidHandError);
assert.throws(() => C.classify("1m"), C.InvalidHandError);
assert.throws(() => C.classify("8z1111m"), C.InvalidHandError);
assert.throws(() => C.classify("1111z"), C.NotTenpaiError);
console.log("ok");
