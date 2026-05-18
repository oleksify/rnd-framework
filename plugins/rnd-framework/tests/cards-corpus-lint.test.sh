#!/usr/bin/env bash
# tests/cards-corpus-lint.test.sh — Generic corpus linter for flash-card format conformance.
#
# Advisory mode (default): prints offenders, exits 0.
# Strict mode: CARDS_LINT_STRICT=1 — exits non-zero on any violation.

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(cd "$TESTS_DIR/.." && pwd)"
CARDS_DIR="$PLUGIN_DIR/cards"
LIB_SH="$PLUGIN_DIR/hooks/lib.sh"

source "$TESTS_DIR/test-helpers.sh"
# strip_frontmatter is defined in lib.sh; source it for consistent frontmatter parsing.
source "$LIB_SH"

VIOLATIONS=0

# Extracts a single frontmatter field value by field name.
# Reads from the card file path; prints value or empty string.
_get_field() {
  local file="$1"
  local field="$2"
  awk -v field="$field" '
    /^---$/ { n++; next }
    n == 1 && $0 ~ "^" field ":" {
      sub("^" field ":[[:space:]]*", "")
      print
      exit
    }
  ' "$file"
}

# Reports a violation: prints the message and increments VIOLATIONS.
_violation() {
  local file="$1"
  local msg="$2"
  printf '  FAIL  %s: %s\n' "$file" "$msg"
  VIOLATIONS=$((VIOLATIONS + 1))
}

printf 'Scanning %s ...\n\n' "$CARDS_DIR"

while IFS= read -r card_file; do
  rel="${card_file#"$PLUGIN_DIR/"}"
  lang_dir="$(basename "$(dirname "$card_file")")"
  role_dir="$(basename "$(dirname "$(dirname "$card_file")")")"
  filename="$(basename "$card_file")"

  content="$(< "$card_file")"

  # (a) 6 required frontmatter fields present
  for field in id role language tags applicable_task_types scope; do
    val="$(_get_field "$card_file" "$field")"
    if [[ -z "$val" ]]; then
      _violation "$rel" "missing frontmatter field: $field"
    fi
  done

  # (b) id: value matches the filename's <id> suffix
  id_val="$(_get_field "$card_file" "id")"
  expected_id="${filename#CARD-}"
  expected_id="${expected_id%.md}"
  if [[ -n "$id_val" && "$id_val" != "$expected_id" ]]; then
    _violation "$rel" "id: '$id_val' does not match filename suffix '$expected_id'"
  fi

  # (c) role: matches the role directory
  role_val="$(_get_field "$card_file" "role")"
  if [[ -n "$role_val" && "$role_val" != "$role_dir" ]]; then
    _violation "$rel" "role: '$role_val' does not match directory '$role_dir'"
  fi

  # (d) language: matches the lang directory
  lang_val="$(_get_field "$card_file" "language")"
  if [[ -n "$lang_val" && "$lang_val" != "$lang_dir" ]]; then
    _violation "$rel" "language: '$lang_val' does not match directory '$lang_dir'"
  fi

  # (e) scope: is >= 4 whitespace-separated words AND not exactly small|medium|large
  scope_val="$(_get_field "$card_file" "scope")"
  if [[ -n "$scope_val" ]]; then
    scope_lower="$(printf '%s' "$scope_val" | tr '[:upper:]' '[:lower:]')"
    if [[ "$scope_lower" == "small" || "$scope_lower" == "medium" || "$scope_lower" == "large" ]]; then
      _violation "$rel" "scope: is a bare size label ('$scope_val'); must be a descriptive sentence"
    else
      word_count="$(printf '%s' "$scope_val" | wc -w | tr -d ' ')"
      if [[ "$word_count" -lt 4 ]]; then
        _violation "$rel" "scope: has only $word_count word(s); must be >= 4 words"
      fi
    fi
  fi

  # (f) body contains no ^## or ^### lines
  body="$(printf '%s' "$content" | strip_frontmatter)"
  if printf '%s\n' "$body" | grep -qE '^#{2,3} '; then
    _violation "$rel" "body contains a Markdown heading (## or ###)"
  fi

  # (g) body contains the appropriate bold labels
  if [[ "$role_dir" == "cleanup" ]]; then
    if ! printf '%s\n' "$body" | grep -q '^\*\*Before'; then
      _violation "$rel" "body missing **Before label (cleanup cards use Before/After/Why after is better)"
    fi
    if ! printf '%s\n' "$body" | grep -q '^\*\*After'; then
      _violation "$rel" "body missing **After label (cleanup cards use Before/After/Why after is better)"
    fi
    if ! printf '%s\n' "$body" | grep -q '\*\*Why after is better'; then
      _violation "$rel" "body missing **Why after is better label"
    fi
  else
    if ! printf '%s\n' "$body" | grep -q '^\*\*Good'; then
      _violation "$rel" "body missing **Good label"
    fi
    if ! printf '%s\n' "$body" | grep -q '^\*\*Worse'; then
      _violation "$rel" "body missing **Worse label"
    fi
    if ! printf '%s\n' "$body" | grep -q '\*\*Why good is better'; then
      _violation "$rel" "body missing **Why good is better label"
    fi
  fi

done < <(find "$CARDS_DIR" -name "CARD-*.md" | sort)

printf '\n'

if [[ "$VIOLATIONS" -gt 0 ]]; then
  printf '  %d violation(s) found.\n' "$VIOLATIONS"

  if [[ "${CARDS_LINT_STRICT:-1}" == "1" ]]; then
    printf '  CARDS_LINT_STRICT=1: exiting non-zero.\n'
    exit 1
  else
    printf '  Advisory mode (CARDS_LINT_STRICT=0): violations noted but not failing.\n'
    printf '\n  0 pass, %d fail (%d total)\n' "$VIOLATIONS" "$VIOLATIONS"
    exit 0
  fi
else
  printf '  No violations found.\n'
  printf '\n  %d pass, 0 fail (%d total)\n' "$(find "$CARDS_DIR" -name "CARD-*.md" | wc -l | tr -d ' ')" "$(find "$CARDS_DIR" -name "CARD-*.md" | wc -l | tr -d ' ')"
  exit 0
fi
