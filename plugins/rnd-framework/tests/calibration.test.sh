#!/usr/bin/env bash
# tests/calibration.test.sh — Tests for lib/calibration.sh CLI surface
# and audit-event.sh tier_escalated emission.
# Usage: bash tests/calibration.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

CALIB="${PLUGIN_ROOT}/lib/calibration.sh"
AUDIT="${PLUGIN_ROOT}/lib/audit-event.sh"

# ---------------------------------------------------------------------------
# Temp environment: isolated calibration.jsonl and RND_DIR
# ---------------------------------------------------------------------------

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

CALIB_DIR="${TMP_DIR}/plugin-data"
mkdir -p "$CALIB_DIR"

SESSION_DIR="${TMP_DIR}/session"
mkdir -p "$SESSION_DIR"

# Seed calibration.jsonl: 10 records — 7 PASS + 3 FALSE_PASS, all NORMAL.
CALIB_FILE="${CALIB_DIR}/calibration.jsonl"

cat > "$CALIB_FILE" <<'JSONL'
{"criticality":"NORMAL","verdict":"PASS","falseVerdictFlag":null}
{"criticality":"NORMAL","verdict":"PASS","falseVerdictFlag":null}
{"criticality":"NORMAL","verdict":"PASS","falseVerdictFlag":null}
{"criticality":"NORMAL","verdict":"PASS","falseVerdictFlag":null}
{"criticality":"NORMAL","verdict":"PASS","falseVerdictFlag":null}
{"criticality":"NORMAL","verdict":"PASS","falseVerdictFlag":null}
{"criticality":"NORMAL","verdict":"PASS","falseVerdictFlag":null}
{"criticality":"NORMAL","verdict":"PASS","falseVerdictFlag":"FALSE_PASS"}
{"criticality":"NORMAL","verdict":"PASS","falseVerdictFlag":"FALSE_PASS"}
{"criticality":"NORMAL","verdict":"PASS","falseVerdictFlag":"FALSE_PASS"}
JSONL

printf '\n--- calibration: help and CLI surface ---\n'

# Test 1: --help exits 0 and mentions all four subcommands
out="$(CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$CALIB" --help 2>&1)"
exit_code=0
CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$CALIB" --help >/dev/null 2>&1 || exit_code=$?
assert_eq "--help exits 0" "0" "$exit_code"
assert_contains "--help mentions window"          "window"          "$out"
assert_contains "--help mentions false_pass_rate" "false_pass_rate" "$out"
assert_contains "--help mentions should_promote"  "should_promote"  "$out"
assert_contains "--help mentions promote_tier"    "promote_tier"    "$out"

printf '\n--- calibration: false_pass_rate ---\n'

# Test 2: false_pass_rate NORMAL on seeded fixture = 0.30
rate="$(CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$CALIB" false_pass_rate NORMAL)"
assert_eq "false_pass_rate NORMAL = 0.30" "0.30" "$rate"

printf '\n--- calibration: should_promote ---\n'

# Test 3: should_promote NORMAL exits 0 (rate 0.30 >= 0.20, escalation not disabled)
promote_exit=0
CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$CALIB" should_promote NORMAL || promote_exit=$?
assert_eq "should_promote NORMAL exits 0 when rate >= 0.20" "0" "$promote_exit"

# Test 4: RND_DISABLE_AUTO_ESCALATION=1 → should_promote exits non-zero
disabled_exit=0
CLAUDE_PLUGIN_DATA="$CALIB_DIR" RND_DISABLE_AUTO_ESCALATION=1 "$CALIB" should_promote NORMAL || disabled_exit=$?
if [[ "$disabled_exit" -ne 0 ]]; then
  assert_eq "should_promote exits non-zero when escalation disabled" "non-zero" "non-zero"
else
  assert_eq "should_promote exits non-zero when escalation disabled" "non-zero" "0"
fi

printf '\n--- calibration: promote_tier ---\n'

# Test 5: promote_tier LOW → NORMAL
low_out="$(CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$CALIB" promote_tier LOW)"
assert_eq "promote_tier LOW = NORMAL" "NORMAL" "$low_out"

# Test 6: promote_tier NORMAL → HIGH
med_out="$(CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$CALIB" promote_tier NORMAL)"
assert_eq "promote_tier NORMAL = HIGH" "HIGH" "$med_out"

# Test 7: promote_tier HIGH → HIGH (ceiling)
high_out="$(CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$CALIB" promote_tier HIGH)"
assert_eq "promote_tier HIGH = HIGH" "HIGH" "$high_out"

# Test 8: promote_tier BOGUS → exits non-zero
bogus_exit=0
CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$CALIB" promote_tier BOGUS >/dev/null 2>&1 || bogus_exit=$?
if [[ "$bogus_exit" -ne 0 ]]; then
  assert_eq "promote_tier BOGUS exits non-zero" "non-zero" "non-zero"
else
  assert_eq "promote_tier BOGUS exits non-zero" "non-zero" "0"
fi

printf '\n--- calibration: tier_escalated audit event ---\n'

# Test 9: audit-event.sh tier_escalated appends a line where .event == "tier_escalated"
AUDIT_FILE="${SESSION_DIR}/audit.jsonl"
RND_DIR="$SESSION_DIR" "$AUDIT" tier_escalated T7 "NORMAL->HIGH"

event_val="$(jq -r '.event' "$AUDIT_FILE")"
assert_eq "audit-event tier_escalated writes event field" "tier_escalated" "$event_val"

task_val="$(jq -r '.task_id' "$AUDIT_FILE")"
assert_eq "audit-event tier_escalated writes task_id" "T7" "$task_val"

tool_val="$(jq -r '.tool' "$AUDIT_FILE")"
assert_eq "audit-event tier_escalated writes tool (tier transition)" "NORMAL->HIGH" "$tool_val"

report
