---
id: R-PY3
role: reality-auditor
language: python
tags: [anomaly, inconsistency, cross-check]
applicable_task_types: [new-feature, bugfix, refactor, config]
scope: Python version claims in pyproject.toml, CI matrix, and README must agree or the lowest supported version is undefined.
specializes: [P-EFFECTS-EDGE-01]
---

Specializes the effects-at-the-edge principle by flagging the three-source Python version declaration: when `requires-python`, the CI matrix, and the README each name a different minimum version, users installing on the boundary version get an untested or broken environment.

**Good audit observation:**
> Three sources declare Python version support and they disagree. `pyproject.toml` sets `requires-python = ">=3.11"`, the GitHub Actions matrix in `.github/workflows/ci.yml` tests on `["3.10", "3.11", "3.12"]`, and `README.md` states "requires Python 3.9+". The matrix tests 3.10, which `pyproject.toml` would reject at install time. The README's 3.9 claim is contradicted by both other sources. Cross-check by reading `pyproject.toml [project] requires-python`, the `python-version` matrix entries in the CI workflow, and the prerequisites section of `README.md` — then pick one authoritative source and align the others to it.

**Worse audit observation:**
> The project declares Python version requirements in several places. The minimum version should be kept consistent.

**Why good is better:** The good observation names all three sources, quotes the specific values from each, and identifies the concrete contradiction (CI tests a version pyproject would reject). The worse observation notes the topic of consistency without checking whether the values actually agree. A user who installs on Python 3.10 against a `requires-python = ">=3.11"` constraint will get a pip error; a CI matrix that tests 3.10 while the package rejects it is running tests that cannot reproduce in a fresh install.
