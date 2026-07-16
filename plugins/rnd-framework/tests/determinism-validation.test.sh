#!/usr/bin/env bash
# tests/determinism-validation.test.sh — proves the rnd-explain determinism
# gate is non-vacuous: the headless validator passes a well-formed report and
# rejects each violation class with its own distinct reason, and the same gate
# blocks a bad island at load in a real browser (self-containment / clean parse).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

SKILL_DIR="$(cd "${SCRIPT_DIR}/../skills/rnd-explain" && pwd)"
VALIDATOR="${SKILL_DIR}/report-validate.js"
TEMPLATE="${SKILL_DIR}/template.html"
FIXTURES="${SKILL_DIR}/fixtures"
CHROME_BIN="${RND_CHROME_BIN:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
RENDER_CHECK="${SCRIPT_DIR}/lib/render-check.mjs"

# --- The full well-formed report (the shipped template) passes the gate ---
tmpl_exit=0
tmpl_output="$(node "$VALIDATOR" "$TEMPLATE" 2>&1)" || tmpl_exit=$?
assert_eq "well-formed report exits 0" "0" "$tmpl_exit"
assert_contains "well-formed report reports ok" '"ok": true' "$tmpl_output"

# --- A well-formed island fixture passes too ---
wf_exit=0
wf_output="$(node "$VALIDATOR" --island "${FIXTURES}/well-formed.md" 2>&1)" || wf_exit=$?
assert_eq "well-formed island exits 0" "0" "$wf_exit"
assert_contains "well-formed island reports ok" '"ok": true' "$wf_output"

# --- The kitchen-sink render-proof fixture (every tag + a balanced quiz) passes ---
ks_exit=0
ks_output="$(node "$VALIDATOR" --island "${SCRIPT_DIR}/fixtures/render-proof-suite/kitchen-sink.md" 2>&1)" || ks_exit=$?
assert_eq "kitchen-sink island exits 0" "0" "$ks_exit"
assert_contains "kitchen-sink island reports ok" '"ok": true' "$ks_output"

# --- Each violation fixture is rejected with its own distinct reason ---
# fixture:EXPECTED_CODE — one row per pre-registered rejection class.
check_violation() {
  local fixture="$1" expected_code="$2"
  local exit_code=0 output

  output="$(node "$VALIDATOR" --island "${FIXTURES}/${fixture}.md" 2>&1)" || exit_code=$?

  local nonzero
  nonzero=$([[ $exit_code -ne 0 ]] && echo nonzero || echo zero)
  assert_eq "${fixture} is rejected (non-zero exit)" "nonzero" "$nonzero"
  assert_contains "${fixture} rejected with ${expected_code}" "\"code\": \"${expected_code}\"" "$output"
}

check_violation "missing-required-attr"       "SCHEMA_VALIDATION"
check_violation "three-section"                "SECTION_COUNT"
check_violation "reordered-sections"           "SECTION_ORDER"
check_violation "four-question-quiz"           "QUIZ_COUNT"
check_violation "quiz-length-bias"             "QUIZ_LENGTH_BIAS"
check_violation "intra-attribute-placeholder"  "UNFILLED_MARKER"
check_violation "external-url"                 "EXTERNAL_URL"
check_violation "runtime-import"               "RUNTIME_EXTERNAL_REQUEST"
check_violation "unsafe-formula-script"        "UNSAFE_FORMULA"
check_violation "unsafe-formula-annotation"    "UNSAFE_FORMULA"

# --- Render-executed proof: the same gate runs at load in a real browser.
# The offline render is the authoritative self-containment check; a static
# scan alone would miss a runtime-constructed request. Chrome-gated so a host
# without a browser degrades to a loud SKIP rather than a hard failure. ---
if [[ ! -x "$CHROME_BIN" ]]; then
  printf 'SKIP: Chrome not found at %s (render-executed gate proof skipped)\n' "$CHROME_BIN"
  report
  exit 0
fi

# The well-formed template renders offline clean, exposes the gate, and the
# gate returns ok — no error box is mounted.
render_exit=0
node "$RENDER_CHECK" "$TEMPLATE" \
  --assert 'typeof window.__VALIDATE_REPORT__ === "function"' \
  --assert 'window.__VALIDATE_REPORT__({markdoc: window.Markdoc, config: window.__MARKDOC_CONFIG__, islandSource: document.getElementById("doc").textContent}).ok === true' \
  --assert 'document.querySelectorAll(".render-error").length === 0' \
  >/dev/null 2>&1 || render_exit=$?
assert_eq "well-formed template renders offline with the gate passing" "0" "$render_exit"

# A report whose island carries an external URL is blocked at load: the gate
# throws with the distinct reason and an error box is mounted instead.
bad_report="$(mktemp -t bad-report-XXXX).html"
node -e '
  const fs = require("fs");
  const [tmpl, islandFile, out] = process.argv.slice(1);
  const html = fs.readFileSync(tmpl, "utf8");
  const island = fs.readFileSync(islandFile, "utf8");
  const open = html.indexOf(">", html.indexOf("<script type=\"text/markdoc\" id=\"doc\">"));
  const close = html.indexOf("</script>", open);
  fs.writeFileSync(out, html.slice(0, open + 1) + "\n" + island + "\n" + html.slice(close));
' "$TEMPLATE" "${FIXTURES}/external-url.md" "$bad_report"

bad_output="$(node "$RENDER_CHECK" "$bad_report" \
  --assert 'document.querySelectorAll(".render-error").length === 1' 2>&1)" || true
assert_contains "a violating island is blocked at load with its distinct reason" \
  "validation failed [EXTERNAL_URL]" "$bad_output"

rm -f "$bad_report"

# A formula that smuggles an annotation-xml HTML integration point is blocked at
# load in a real browser with the UNSAFE_FORMULA reason, an error box is mounted,
# and no smuggled script executes (window.__pwned stays undefined).
assemble_report() {
  local island="$1" out="$2"
  node -e '
    const fs = require("fs");
    const [tmpl, islandFile, out] = process.argv.slice(1);
    const html = fs.readFileSync(tmpl, "utf8");
    const island = fs.readFileSync(islandFile, "utf8");
    const open = html.indexOf(">", html.indexOf("<script type=\"text/markdoc\" id=\"doc\">"));
    const close = html.indexOf("</script>", open);
    fs.writeFileSync(out, html.slice(0, open + 1) + "\n" + island + "\n" + html.slice(close));
  ' "$TEMPLATE" "$island" "$out"
}

unsafe_report="$(mktemp -t unsafe-formula-XXXX).html"
assemble_report "${FIXTURES}/unsafe-formula-annotation.md" "$unsafe_report"

unsafe_output="$(node "$RENDER_CHECK" "$unsafe_report" \
  --assert 'document.querySelectorAll(".render-error").length === 1' \
  --assert 'typeof window.__pwned === "undefined"' \
  --assert 'document.querySelectorAll("math annotation-xml, math script, math img").length === 0' 2>&1)" || true
assert_contains "a malicious formula is blocked at load with the UNSAFE_FORMULA reason" \
  "validation failed [UNSAFE_FORMULA]" "$unsafe_output"

rm -f "$unsafe_report"

# Defense in depth: a formula that PASSES the gate but carries a non-MathML
# element reaches the render step, and the render allowlist rebuilds the math
# subtree without the foreign node -- proving the render path itself strips
# script/foreign markup even if it were ever reached with unvalidated content.
foreign_report="$(mktemp -t formula-foreign-XXXX).html"
assemble_report "${FIXTURES}/formula-foreign-element.md" "$foreign_report"

foreign_exit=0
node "$RENDER_CHECK" "$foreign_report" \
  --assert 'document.querySelectorAll(".render-error").length === 0' \
  --assert 'document.querySelectorAll("math").length === 1' \
  --assert 'document.querySelector("math mrow mi") !== null' \
  --assert 'document.querySelectorAll("math b, math script, math annotation-xml, math img, math div").length === 0' \
  --assert 'typeof window.__pwned === "undefined"' \
  >/dev/null 2>&1 || foreign_exit=$?
assert_eq "a validator-passing formula renders with foreign elements stripped by the render allowlist" "0" "$foreign_exit"

rm -f "$foreign_report"

report
