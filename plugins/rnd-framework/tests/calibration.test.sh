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

printf '\n--- calibration: assertion_id_window subcommand ---\n'

# Seed a mixed calibration file: some records carry assertion_id, historical ones don't.
MIXED_DIR="${TMP_DIR}/mixed-plugin-data"
mkdir -p "$MIXED_DIR"
MIXED_FILE="${MIXED_DIR}/calibration.jsonl"

cat > "$MIXED_FILE" <<'JSONL'
{"criticality":"NORMAL","verdict":"PASS","falseVerdictFlag":null}
{"criticality":"NORMAL","verdict":"PASS","falseVerdictFlag":"FALSE_PASS","assertion_id":"M1.foo.bar"}
{"criticality":"HIGH","verdict":"FAIL","falseVerdictFlag":null,"assertion_id":"M1.foo.baz"}
{"criticality":"NORMAL","verdict":"PASS","falseVerdictFlag":null,"assertion_id":"M1.foo.bar"}
JSONL

# Test 10: assertion_id_window returns only records matching the given assertion_id
matched="$(CLAUDE_PLUGIN_DATA="$MIXED_DIR" "$CALIB" assertion_id_window "M1.foo.bar")"
count="$(printf '%s\n' "$matched" | jq -sc 'length')"
assert_eq "assertion_id_window M1.foo.bar returns 2 records" "2" "$count"

# Test 11: assertion_id_window for an absent id returns empty output
absent="$(CLAUDE_PLUGIN_DATA="$MIXED_DIR" "$CALIB" assertion_id_window "M1.not.present")"
assert_eq "assertion_id_window absent id returns empty" "" "$absent"

# Test 12: window NORMAL still returns historical records (without assertion_id) unchanged
all_normal="$(CLAUDE_PLUGIN_DATA="$MIXED_DIR" "$CALIB" window NORMAL)"
normal_count="$(printf '%s\n' "$all_normal" | jq -sc 'length')"
assert_eq "window NORMAL includes records without assertion_id" "3" "$normal_count"

# Test 13: assertion_id_window filters by assertion_id across different criticalities
all_baz="$(CLAUDE_PLUGIN_DATA="$MIXED_DIR" "$CALIB" assertion_id_window "M1.foo.baz")"
baz_count="$(printf '%s\n' "$all_baz" | jq -sc 'length')"
assert_eq "assertion_id_window M1.foo.baz returns 1 record (HIGH criticality)" "1" "$baz_count"

printf '\n--- calibration: false_verdict_flag snake_case back-compat ---\n'

# Set up a fixture with both spellings to prove both are counted
SNAKE_DIR="${TMP_DIR}/snake-plugin-data"
mkdir -p "$SNAKE_DIR"
SNAKE_FILE="${SNAKE_DIR}/calibration.jsonl"

# 10 records: 5 with legacy camelCase key, 5 with new snake_case key
# 2 legacy FALSE_PASS + 2 snake FALSE_PASS + 6 clean = 4/10 = 0.40
printf '%s\n' \
  '{"criticality":"NORMAL","verdict":"PASS","falseVerdictFlag":null}' \
  '{"criticality":"NORMAL","verdict":"PASS","falseVerdictFlag":null}' \
  '{"criticality":"NORMAL","verdict":"PASS","falseVerdictFlag":null}' \
  '{"criticality":"NORMAL","verdict":"PASS","falseVerdictFlag":null}' \
  '{"criticality":"NORMAL","verdict":"PASS","falseVerdictFlag":null}' \
  '{"criticality":"NORMAL","verdict":"PASS","falseVerdictFlag":null}' \
  '{"criticality":"NORMAL","verdict":"PASS","falseVerdictFlag":"FALSE_PASS"}' \
  '{"criticality":"NORMAL","verdict":"PASS","falseVerdictFlag":"FALSE_PASS"}' \
  '{"criticality":"NORMAL","verdict":"PASS","false_verdict_flag":"FALSE_PASS"}' \
  '{"criticality":"NORMAL","verdict":"PASS","false_verdict_flag":"FALSE_PASS_PROXY"}' \
  > "$SNAKE_FILE"

# Test 14: legacy falseVerdictFlag records are counted (back-compat)
legacy_rate="$(CLAUDE_PLUGIN_DATA="$SNAKE_DIR" "$CALIB" false_pass_rate NORMAL)"
assert_eq "false_pass_rate counts legacy falseVerdictFlag AND new false_verdict_flag" "0.40" "$legacy_rate"

# Test 15: should_promote responds to snake_case records (rate 0.40 >= 0.20)
snake_promote=0
CLAUDE_PLUGIN_DATA="$SNAKE_DIR" "$CALIB" should_promote NORMAL || snake_promote=$?
assert_eq "should_promote exits 0 with mixed-spelling fixture (rate 0.40)" "0" "$snake_promote"

# Test 16: a fixture with ONLY snake_case false_verdict_flag records is counted
SNAKE_ONLY_DIR="${TMP_DIR}/snake-only-plugin-data"
mkdir -p "$SNAKE_ONLY_DIR"
printf '%s\n' \
  '{"criticality":"NORMAL","verdict":"PASS","false_verdict_flag":null}' \
  '{"criticality":"NORMAL","verdict":"PASS","false_verdict_flag":null}' \
  '{"criticality":"NORMAL","verdict":"PASS","false_verdict_flag":null}' \
  '{"criticality":"NORMAL","verdict":"PASS","false_verdict_flag":null}' \
  '{"criticality":"NORMAL","verdict":"PASS","false_verdict_flag":null}' \
  '{"criticality":"NORMAL","verdict":"PASS","false_verdict_flag":null}' \
  '{"criticality":"NORMAL","verdict":"PASS","false_verdict_flag":null}' \
  '{"criticality":"NORMAL","verdict":"PASS","false_verdict_flag":"FALSE_PASS"}' \
  '{"criticality":"NORMAL","verdict":"PASS","false_verdict_flag":"FALSE_PASS"}' \
  '{"criticality":"NORMAL","verdict":"PASS","false_verdict_flag":"FALSE_PASS"}' \
  > "${SNAKE_ONLY_DIR}/calibration.jsonl"

snake_only_rate="$(CLAUDE_PLUGIN_DATA="$SNAKE_ONLY_DIR" "$CALIB" false_pass_rate NORMAL)"
assert_eq "false_pass_rate with snake_case-only fixture = 0.30" "0.30" "$snake_only_rate"

# ---------------------------------------------------------------------------
# false_pass_rate rounds, not truncates. 2 FALSE_PASS of 3 → 0.6667.
# Revert-proof: the old integer %d.%02d path truncated to 0.66.
# ---------------------------------------------------------------------------
printf '\n--- calibration: false_pass_rate rounds (not truncates) ---\n'

ROUND_DIR="${TMP_DIR}/round-data"
mkdir -p "$ROUND_DIR"
cat > "${ROUND_DIR}/calibration.jsonl" <<'JSONL'
{"criticality":"LOW","verdict":"PASS","false_verdict_flag":"FALSE_PASS"}
{"criticality":"LOW","verdict":"PASS","false_verdict_flag":"FALSE_PASS"}
{"criticality":"LOW","verdict":"PASS","false_verdict_flag":null}
JSONL

round_rate="$(CLAUDE_PLUGIN_DATA="$ROUND_DIR" "$CALIB" false_pass_rate LOW)"
assert_eq "false_pass_rate 2/3 rounds to 0.67 (not truncated 0.66)" "0.67" "$round_rate"

report
