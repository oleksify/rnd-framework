---
description: "Validate plugin structure: frontmatter, JSON files, hook references, and cross-references."
effort: low
---

# Validate Plugin Structure

Run the validation script to check the rnd-framework plugin for structural errors:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/validate.sh"
```

Report the results to the user. If any checks fail, explain what's wrong and suggest fixes.
