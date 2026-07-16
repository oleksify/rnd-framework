#!/usr/bin/env bash
# tests/render-proof-suite.test.sh — the committed render-proof: a kitchen-sink
# Markdoc island exercising every custom tag in the vocabulary (callout, all 4
# chart types, all 3 diagram kinds, formula, kpi, mock, stepper, a GFM
# pipe-table, a fenced code block, and a 5-question quiz), assembled into a
# full report and mounted in headless Chrome. Proves the whole tag vocabulary
# renders together with zero thrown/console errors, not just one tag at a time.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

SKILL_DIR="$(cd "${SCRIPT_DIR}/../skills/rnd-explain" && pwd)"
VALIDATOR="${SKILL_DIR}/report-validate.js"
TEMPLATE="${SKILL_DIR}/template.html"
RENDER_CHECK="${SCRIPT_DIR}/lib/render-check.mjs"
ISLAND="${SCRIPT_DIR}/fixtures/render-proof-suite/kitchen-sink.md"
CHROME_BIN="${RND_CHROME_BIN:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"

# --- First: the kitchen-sink island must pass the determinism gate on its own
# terms (schema + structural checks), independent of any browser. ---
gate_exit=0
gate_output="$(node "$VALIDATOR" --island "$ISLAND" --template "$TEMPLATE" 2>&1)" || gate_exit=$?
assert_eq "kitchen-sink island passes the determinism gate" "0" "$gate_exit"
assert_contains "kitchen-sink island reports ok" '"ok": true' "$gate_output"

# --- Assemble the island into a full self-contained report the same way the
# skill would: splice it into the template's island placeholder. ---
assembled_report="$(mktemp -t kitchen-sink-XXXX).html"
node -e '
  const fs = require("fs");
  const [tmpl, islandFile, out] = process.argv.slice(1);
  const html = fs.readFileSync(tmpl, "utf8");
  const island = fs.readFileSync(islandFile, "utf8");
  const open = html.indexOf(">", html.indexOf("<script type=\"text/markdoc\" id=\"doc\">"));
  const close = html.indexOf("</script>", open);
  fs.writeFileSync(out, html.slice(0, open + 1) + "\n" + island + "\n" + html.slice(close));
' "$TEMPLATE" "$ISLAND" "$assembled_report"

if [[ ! -x "$CHROME_BIN" ]]; then
  printf 'SKIP: Chrome not found at %s (kitchen-sink render-proof skipped)\n' "$CHROME_BIN"
  rm -f "$assembled_report"
  report
  exit 0
fi

# --- Mount the assembled report offline and assert every tag + the quiz
# render, with zero thrown/console errors (the harness fails the whole run on
# any exception or console.error, so a clean exit already proves that half). ---
smoke_exit=0
smoke_output="$(node "$RENDER_CHECK" "$assembled_report" \
  --assert 'window.__VALIDATE_REPORT__({markdoc: window.Markdoc, config: window.__MARKDOC_CONFIG__, islandSource: document.getElementById("doc").textContent}).ok === true' \
  --assert 'document.querySelectorAll(".render-error").length === 0' \
  --assert 'document.querySelectorAll(".callout").length === 1' \
  --assert 'document.querySelectorAll(".kpi").length === 3' \
  --assert 'document.querySelectorAll(".mock").length === 1' \
  --assert 'document.querySelectorAll("table").length === 1 && document.querySelectorAll("table tr").length === 5 && document.querySelectorAll("table th").length === 3' \
  --assert 'document.querySelectorAll("pre[data-language]").length === 1 && document.querySelector("pre").textContent.indexOf(String.fromCharCode(10)) !== -1' \
  --assert 'document.querySelectorAll("svg.chart").length === 4' \
  --assert 'document.querySelector("svg.chart[data-type=\"bar\"] rect") !== null' \
  --assert 'document.querySelectorAll("svg.chart[data-type=\"line\"] polyline").length === 1' \
  --assert 'document.querySelector("svg.chart[data-type=\"scatter\"] circle") !== null' \
  --assert 'document.querySelector("svg.chart[data-type=\"area\"] path") !== null' \
  --assert 'document.querySelectorAll("svg.diagram").length === 3' \
  --assert 'document.querySelectorAll("svg.diagram[data-kind=\"graph\"] .node-box").length === 3' \
  --assert 'document.querySelectorAll("svg.diagram[data-kind=\"tree\"] .node-box").length === 3' \
  --assert 'document.querySelectorAll("svg.diagram[data-kind=\"sequence\"] .lifeline").length === 2' \
  --assert 'document.querySelectorAll("math").length === 1' \
  --assert 'document.querySelectorAll("x-stepper").length === 1 && document.querySelector("x-stepper").getAttribute("data-index") === "0"' \
  --assert 'document.querySelectorAll(".quiz-card").length === 5' \
  --assert 'document.querySelector(".quiz-score").textContent === "Score: 0 / 5"' \
  --assert '(function(){ var c=document.querySelector(".quiz-card[data-index=\"0\"]"); c.querySelector(".quiz-option[data-option-index=\"1\"]").click(); return c.getAttribute("data-answered")==="true" && c.querySelector(".quiz-option[data-option-index=\"1\"]").classList.contains("quiz-correct"); })()' \
  --assert 'document.querySelector(".quiz-card[data-index=\"0\"] .quiz-feedback").textContent.length > 0' \
  --assert 'document.querySelector(".quiz-score").textContent === "Score: 1 / 5"' \
  --assert '(function(){ document.querySelector(".quiz-card[data-index=\"0\"] .quiz-option[data-option-index=\"0\"]").click(); return document.querySelector(".quiz-score").textContent === "Score: 1 / 5"; })()' \
  --assert '(function(){ var s=document.querySelector("x-stepper"); s.querySelector(".stepper-next").click(); return s.getAttribute("data-index")==="1"; })()' \
  --assert '(function(){ var s=document.querySelector("x-stepper"); s.querySelector(".stepper-prev").click(); return s.getAttribute("data-index")==="0"; })()' \
  2>&1)" || smoke_exit=$?

assert_eq "kitchen-sink report mounts offline with every tag + the quiz rendered, zero errors" "0" "$smoke_exit"

if [[ "$smoke_exit" -ne 0 ]]; then
  printf '%s\n' "$smoke_output"
fi

rm -f "$assembled_report"

# --- Negative chart values render below a zero baseline instead of producing a
# negative (invalid, silently dropped) rect height. ---
NEG_ISLAND="${SCRIPT_DIR}/fixtures/render-proof-suite/negative-chart.md"

neg_gate_exit=0
node "$VALIDATOR" --island "$NEG_ISLAND" --template "$TEMPLATE" >/dev/null 2>&1 || neg_gate_exit=$?
assert_eq "negative-value chart island passes the determinism gate" "0" "$neg_gate_exit"

neg_report="$(mktemp -t negative-chart-XXXX).html"
node -e '
  const fs = require("fs");
  const [tmpl, islandFile, out] = process.argv.slice(1);
  const html = fs.readFileSync(tmpl, "utf8");
  const island = fs.readFileSync(islandFile, "utf8");
  const open = html.indexOf(">", html.indexOf("<script type=\"text/markdoc\" id=\"doc\">"));
  const close = html.indexOf("</script>", open);
  fs.writeFileSync(out, html.slice(0, open + 1) + "\n" + island + "\n" + html.slice(close));
' "$TEMPLATE" "$NEG_ISLAND" "$neg_report"

neg_exit=0
neg_output="$(node "$RENDER_CHECK" "$neg_report" \
  --assert 'document.querySelectorAll(".render-error").length === 0' \
  --assert 'document.querySelectorAll("svg.chart[data-type=\"bar\"] rect").length === 5' \
  --assert 'Array.prototype.every.call(document.querySelectorAll("svg.chart[data-type=\"bar\"] rect"), function(r){ return parseFloat(r.getAttribute("height")) >= 0; })' \
  --assert 'Array.prototype.some.call(document.querySelectorAll("svg.chart[data-type=\"bar\"] rect"), function(r){ return parseFloat(r.getAttribute("height")) > 0; })' \
  --assert 'document.querySelectorAll("svg.chart[data-type=\"line\"] polyline").length === 1' \
  --assert 'document.querySelector("svg.chart[data-type=\"area\"] path") !== null' \
  2>&1)" || neg_exit=$?

assert_eq "negative-value chart renders every bar with a non-negative height and no dropped geometry" "0" "$neg_exit"

if [[ "$neg_exit" -ne 0 ]]; then
  printf '%s\n' "$neg_output"
fi

rm -f "$neg_report"

report
