---
id: R-PY1
role: reality-auditor
language: python
tags: [anomaly, inconsistency, cross-check]
applicable_task_types: [new-feature, bugfix, refactor, config]
scope: Version-pin drift between requirements.txt, pyproject.toml, and poetry.lock produces silent environment divergence.
specializes: [P-EFFECTS-EDGE-01]
---

Specializes the effects-at-the-edge principle by flagging the three-file dependency declaration pattern: when the same package appears in all three files with different version pins, the file used at install time silently wins over the others.

**Good audit observation:**
> All three declaration files mention `requests`, but the pins diverge: `pyproject.toml` declares `requests>=2.31,<3`, `poetry.lock` resolves to `requests 2.30.0`, and `requirements.txt` has no pin at all (`requests`). Run `uv pip compile --check pyproject.toml` or `pip-compile --dry-run requirements.in` to surface the locked vs. declared mismatch. The lockfile trailing a minor version behind the pyproject lower bound suggests the lockfile was not regenerated after the constraint was tightened — any environment built from `requirements.txt` alone will accept any `requests` version, including ones the project has not tested against.

**Worse audit observation:**
> The project uses `requests` and it appears in the dependency files. Pinning looks reasonable.

**Why good is better:** The good observation cross-checks all three sources and names the specific version discrepancy as the anomaly. The worse observation confirms the package exists in dependency files without comparing them. Drift between `pyproject.toml`, the lockfile, and `requirements.txt` is a real class of production failure — environments built from different entry points diverge silently, and the bug appears only when a version boundary is crossed.
