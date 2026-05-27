#!/usr/bin/env bash
# Tests for path-identity helpers and the lifted assertion-walk parser in hooks/lib.sh.
# Usage: bash tests/path-identity-lib.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${SCRIPT_DIR}/../hooks/lib.sh"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

# Source the lib directly so we can call helpers as plain functions.
# lib.sh sets -euo pipefail at the top, so we need to tolerate functions that
# return non-zero without killing the test runner.
# shellcheck source=../hooks/lib.sh
source "$LIB"

# ---------------------------------------------------------------------------
# session_id_from_path — criterion 1
# ---------------------------------------------------------------------------

printf '%s\n' '--- session_id_from_path: branch-partitioned layout ---'

RESULT="$(session_id_from_path \
  '/x/.rnd/claude-130cb64f/branches/main/sessions/20260527-153014-aef926dd/builds/M2.T02.foo-self-assessment.md')"
assert_eq \
  "branch-partitioned path returns session id" \
  "20260527-153014-aef926dd" \
  "$RESULT"

printf '\n%s\n' '--- session_id_from_path: legacy layout ---'

RESULT="$(session_id_from_path \
  '/x/.rnd/slug/sessions/20260329-112654-c60504fd/audit.jsonl')"
assert_eq \
  "legacy path returns session id" \
  "20260329-112654-c60504fd" \
  "$RESULT"

printf '\n%s\n' '--- session_id_from_path: no /sessions/ component ---'

RESULT="$(session_id_from_path '/home/user/.claude/settings.json')"
assert_eq \
  "path with no /sessions/ returns empty" \
  "" \
  "$RESULT"

printf '\n%s\n' '--- session_id_from_path: sessions/ at root-adjacent position ---'

RESULT="$(session_id_from_path \
  '/Users/oleksify/.claude-personal/.rnd/claude-130cb64f/branches/main/sessions/20260527-153014-aef926dd/verifications/wave-1-verdict-map.json')"
assert_eq \
  "realistic branch path returns session id" \
  "20260527-153014-aef926dd" \
  "$RESULT"

# ---------------------------------------------------------------------------
# calib_path_from_artifact — criterion 2
# ---------------------------------------------------------------------------

printf '\n%s\n' '--- calib_path_from_artifact: branch-partitioned layout ---'

RESULT="$(calib_path_from_artifact \
  '/x/.rnd/claude-130cb64f/branches/main/sessions/20260527-153014-aef926dd/verifications/wave-1-verdict-map.json')"
assert_eq \
  "branch-partitioned path returns slug-root calibration.jsonl" \
  "/x/.rnd/claude-130cb64f/calibration.jsonl" \
  "$RESULT"

# The result must not contain /branches/ or /sessions/
[[ "$RESULT" != *"/branches/"* ]]
assert_eq "branch-partitioned result has no /branches/ segment" "0" "$(echo "$RESULT" | grep -c '/branches/' || true)"

[[ "$RESULT" != *"/sessions/"* ]]
assert_eq "branch-partitioned result has no /sessions/ segment" "0" "$(echo "$RESULT" | grep -c '/sessions/' || true)"

printf '\n%s\n' '--- calib_path_from_artifact: legacy layout ---'

RESULT="$(calib_path_from_artifact \
  '/x/.rnd/my-slug/sessions/20260329-112654-c60504fd/audit.jsonl')"
assert_eq \
  "legacy path returns slug-root calibration.jsonl" \
  "/x/.rnd/my-slug/calibration.jsonl" \
  "$RESULT"

assert_eq "legacy result has no /sessions/ segment" "0" "$(echo "$RESULT" | grep -c '/sessions/' || true)"

printf '\n%s\n' '--- calib_path_from_artifact: no .rnd component ---'

RESULT="$(calib_path_from_artifact '/home/user/settings.json')"
assert_eq \
  "path with no /.rnd/ returns empty" \
  "" \
  "$RESULT"

printf '\n%s\n' '--- calib_path_from_artifact: realistic path ---'

RESULT="$(calib_path_from_artifact \
  '/Users/oleksify/.claude-personal/.rnd/claude-130cb64f/branches/main/sessions/20260527-153014-aef926dd/builds/M2.T01-self-assessment.md')"
assert_eq \
  "realistic path ends with /claude-130cb64f/calibration.jsonl" \
  "/Users/oleksify/.claude-personal/.rnd/claude-130cb64f/calibration.jsonl" \
  "$RESULT"

# ---------------------------------------------------------------------------
# parse_contract_assertions — criterion 3
# The function emits tab-separated <assertion_id>\t<shape>\t<confidence> lines.
# ---------------------------------------------------------------------------

printf '\n%s\n' '--- parse_contract_assertions: two-assertion contract ---'

CONTRACT_CONTENT='## Area: One

### M1.area.first-assertion
Some description.
Shape: wiring
Confidence: high

### M1.area.second-assertion
Another description.
Shape: schema-migration
Confidence: stretch

## Area: Two

### M2.other.third-assertion
Third.
Shape: misc
Confidence: medium
'

# Capture output (tab-separated lines)
LINES="$(parse_contract_assertions "$CONTRACT_CONTENT")"
LINE_COUNT="$(printf '%s\n' "$LINES" | grep -c '.' || true)"
assert_eq "three assertions → three output lines" "3" "$LINE_COUNT"

FIRST_LINE="$(printf '%s\n' "$LINES" | head -1)"
assert_eq "first line assertion_id" "M1.area.first-assertion" "$(printf '%s' "$FIRST_LINE" | cut -f1)"
assert_eq "first line shape" "wiring" "$(printf '%s' "$FIRST_LINE" | cut -f2)"
assert_eq "first line confidence" "high" "$(printf '%s' "$FIRST_LINE" | cut -f3)"

SECOND_LINE="$(printf '%s\n' "$LINES" | sed -n '2p')"
assert_eq "second line assertion_id" "M1.area.second-assertion" "$(printf '%s' "$SECOND_LINE" | cut -f1)"
assert_eq "second line shape" "schema-migration" "$(printf '%s' "$SECOND_LINE" | cut -f2)"
assert_eq "second line confidence" "stretch" "$(printf '%s' "$SECOND_LINE" | cut -f3)"

THIRD_LINE="$(printf '%s\n' "$LINES" | sed -n '3p')"
assert_eq "third line assertion_id" "M2.other.third-assertion" "$(printf '%s' "$THIRD_LINE" | cut -f1)"

printf '\n%s\n' '--- parse_contract_assertions: assertion with missing Shape yields empty field ---'

MISSING_SHAPE_CONTENT='## Area: X

### M3.x.no-shape
Confidence: high
'
LINES_MISSING="$(parse_contract_assertions "$MISSING_SHAPE_CONTENT")"
SHAPE_FIELD="$(printf '%s' "$LINES_MISSING" | cut -f2)"
assert_eq "missing Shape yields empty shape field" "" "$SHAPE_FIELD"

printf '\n%s\n' '--- parse_contract_assertions: empty contract yields no output ---'

EMPTY_OUTPUT="$(parse_contract_assertions "")"
assert_eq "empty contract → empty output" "" "$EMPTY_OUTPUT"

# ---------------------------------------------------------------------------
# Verify heading_re is defined exactly once in hooks/ + lib/ (not duplicated)
# ---------------------------------------------------------------------------

printf '\n%s\n' '--- heading_re defined exactly once in hooks/ + lib/ ---'

HEADING_RE_COUNT="$(grep -rn 'heading_re=.*M\[0-9\]' \
  "${SCRIPT_DIR}/../hooks" "${SCRIPT_DIR}/../lib" 2>/dev/null | wc -l | tr -d '[:space:]')"
assert_eq "heading_re defined exactly once" "1" "$HEADING_RE_COUNT"

# ---------------------------------------------------------------------------
report
