#!/usr/bin/env bash
# replan-archive.sh — Move the four canonical plan artifacts into a versioned
# prior-plans/replan-<k>/ subdirectory, where <k> is the next available integer.
#
# Usage:
#   replan-archive.sh <rnd_dir>
#
# Arguments:
#   rnd_dir  Path to the active RND session directory.
#
# Canonical artifacts moved:
#   protocol.md
#   validation-contract.md
#   features.json
#   AGENTS.md
#
# Scope artifacts copied (NOT moved):
#   scope.json
#   scope.md
#
# The frozen scope stays at the session root for the whole pipeline run, so it
# is copied (never moved) into the archive dir to give the differ an old-vs-
# proposed pair. Each copy is guarded so a pre-scope session is a clean no-op.
#
# Output:
#   Prints the created archive directory path on stdout.
#
# Exit codes:
#   0  Archive directory created and artifacts moved.
#   1  Missing argument.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  printf 'Usage: replan-archive.sh <rnd_dir>\n' >&2
  exit 1
fi

rnd_dir="$1"
prior_plans_dir="${rnd_dir}/prior-plans"

# Pre-scan: if none of the four canonical artifacts exist, there is nothing
# to archive. Exit silently without creating an empty replan-<k>/ directory
# that would litter the session tree.
found=0
for artifact in protocol.md validation-contract.md features.json AGENTS.md; do
  if [[ -f "${rnd_dir}/${artifact}" ]]; then
    found=1
    break
  fi
done

if [[ "$found" -eq 0 ]]; then
  exit 0
fi

# Determine the next available replan-<k> index.
k=1
while [[ -d "${prior_plans_dir}/replan-${k}" ]]; do
  k=$((k + 1))
done

archive_dir="${prior_plans_dir}/replan-${k}"
mkdir -p "$archive_dir"

for artifact in protocol.md validation-contract.md features.json AGENTS.md; do
  src="${rnd_dir}/${artifact}"
  if [[ -f "$src" ]]; then
    mv "$src" "${archive_dir}/${artifact}"
  fi
done

# Scope artifacts are frozen at the session root and must outlive a re-plan, so
# they are COPIED into the archive rather than moved. The differ reads these
# copies to diff the old scope against any proposed change.
for scope_artifact in scope.json scope.md; do
  src="${rnd_dir}/${scope_artifact}"
  if [[ -f "$src" ]]; then
    cp "$src" "${archive_dir}/${scope_artifact}"
  fi
done

printf '%s\n' "$archive_dir"
