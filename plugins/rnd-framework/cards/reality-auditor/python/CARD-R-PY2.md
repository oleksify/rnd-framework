---
id: R-PY2
role: reality-auditor
language: python
tags: [anomaly, cross-check, skepticism]
applicable_task_types: [new-feature, bugfix, refactor, config]
scope: The Python import name and the PyPI package name often differ and must be verified independently.
specializes: [P-IMPOSSIBLE-01]
---

Specializes the impossible-states principle by flagging import-vs-package name mismatches: a dependency declaration that looks correct can fail at runtime when the import name differs from the PyPI distribution name.

**Good audit observation:**
> `src/config.py` imports `import yaml` but `pyproject.toml` lists no `yaml` package — it lists `PyYAML==6.0.1`. These are the same library, but the import name (`yaml`) does not match the PyPI name (`PyYAML`). Confirm the install actually provides the expected module by running `python -c 'import yaml; print(yaml.__file__)'` — if it prints a path under the active virtualenv, the install is wired correctly. Other common mismatches to watch for in this codebase: `import cv2` (PyPI: `opencv-python`), `import sklearn` (PyPI: `scikit-learn`), `import PIL` (PyPI: `Pillow`). A freshly created virtualenv with only `pip install -r requirements.txt` should be the test environment.

**Worse audit observation:**
> The project imports `yaml` and declares `PyYAML` as a dependency. This is a standard Python library.

**Why good is better:** The good observation names the specific mismatch, provides the shell command to verify the active install, and enumerates other common mismatches in the same codebase. The worse observation treats the mismatch as a known pattern and stops — it never verifies that the declared package actually provides the import. In CI environments where packages may be installed from different sources, a name mismatch can silently install the wrong package or leave the import unresolvable.
