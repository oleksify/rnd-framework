#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

failed_files=()

for test_file in *.test.sh; do
  [[ -f "$test_file" ]] || continue
  printf '=== %s ===\n' "$test_file"
  if bash "$test_file"; then
    : # tests passed
  else
    failed_files+=("$test_file")
  fi
  printf '\n'
done

if [[ ${#failed_files[@]} -eq 0 ]]; then
  printf 'All test files passed.\n'
  exit 0
else
  printf 'FAILED: %s\n' "${failed_files[*]}"
  exit 1
fi
