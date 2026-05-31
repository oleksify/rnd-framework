## Commands

All commands are namespaced `/rnd-framework:*`.

### Pipeline

| Command | Purpose |
|---|---|
| `rnd-start <task>` | Full pipeline: Plan → Build → Verify → Integrate |
| `rnd-plan <task>` | Planning only — decompose into task specs |
| `rnd-build <T3\|wave-2\|next>` | Build a task or wave |
| `rnd-verify <T3\|wave-2\|all>` | Independent verification |
| `rnd-integrate <wave-2\|final>` | Merge outputs, run integration tests |
| `rnd-debug <bug>` | Reproduce, diagnose, fix, verify |

### Navigating a run

| Command | Purpose |
|---|---|
| `rnd-status` | Pipeline status dashboard |
| `rnd-resume` | Resume an interrupted pipeline |
| `rnd-history` | Browse past sessions |
| `rnd-roadmap <goal>` | Plan or continue a multi-session roadmap |

### Review and analysis

| Command | Purpose |
|---|---|
| `rnd-review` | Evidence-based review of recent changes |
| `rnd-audit` | Full codebase audit |
| `rnd-brainstorm` | Funnel a vague idea into a focused plan |
| `rnd-narrative` | Prose narrative of a session |
| `rnd-stats` | Per-shape non-PASS rate, drift, and gaps |
| `rnd-remeasure` | Compare current metrics against the baseline |
| `rnd-scan` | Scan the project, build a facts sheet |

### Maintenance

| Command | Purpose |
|---|---|
| `rnd-calibrate` | Record a ground-truth verdict correction |
| `rnd-validate` | Validate plugin structure |
| `rnd-doctor` | Runtime environment diagnostics |
| `rnd-bump` | Bump version, update the changelog |
