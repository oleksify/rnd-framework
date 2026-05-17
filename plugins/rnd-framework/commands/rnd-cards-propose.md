---
description: "Scan calibration.jsonl for recurring FAIL/NEEDS_ITERATION feedback clusters and surface draft cards for human review."
argument-hint: "[--calibration=<path>] [--threshold=<0.0-1.0>] [--min-cluster=<int>]"
effort: low
---

# R&D Framework: Propose Flash Cards

Scan the project's calibration log for clusters of recurring verifier feedback and surface draft cards. The loop closes on user-triggered review — nothing is written to the `cards/` tree automatically.

## What it does

1. Reads `calibration.jsonl` (default: `$CLAUDE_PLUGIN_DATA/calibration.jsonl`, falling back to `lib/rnd-dir.sh --calibration`).
2. Filters records where `.verdict == "FAIL"` or `.verdict == "NEEDS_ITERATION"` and `.feedback` is a non-empty string.
3. Tokenises each `feedback` into lowercase 4-grams.
4. Computes pairwise Jaccard similarity over the 4-gram sets; links pairs at or above `--threshold` (default `0.4`).
5. Forms clusters via single-link agglomeration (transitive closure of the link graph).
6. Surfaces clusters with at least `--min-cluster` members (default `3`).
7. For each surfaced cluster prints: cluster size, shared 4-grams (up to 5), up to two sample feedback texts, and a draft card scaffold the human can copy-edit into `plugins/rnd-framework/cards/<role>/<lang>/CARD-<ID>.md`.

## Flags

| Flag | Default | Purpose |
|------|---------|---------|
| `--calibration=<path>` | `$CLAUDE_PLUGIN_DATA/calibration.jsonl` or `rnd-dir.sh --calibration` | Path to the calibration log to scan |
| `--threshold=<float>` | `0.4` | Jaccard similarity threshold for linking two feedback strings |
| `--min-cluster=<int>` | `3` | Minimum cluster size to surface (singletons are always suppressed) |
| `--help` | — | Print usage and exit 0 |

## Invocation

```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/rnd-cards-propose.sh"
```

Or with explicit flags:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/rnd-cards-propose.sh" \
    --threshold=0.5 \
    --min-cluster=4
```

## Output

Markdown printed to stdout. Each surfaced cluster looks like:

```
## Cluster 1

**Cluster size:** 5

**Shared patterns:**
- `the function does not validate`
- `does not validate inputs before`
- ...

**Sample feedback:**

> The function does not validate inputs before dispatching to the handler...
> The function does not validate inputs and silently drops malformed records...

**Draft card scaffold:**

```markdown
---
role: builder
lang: generic
tags: []
applicable_task_types: []
---

# (Edit: Card title here)

(Edit: Card body — guidance to address the recurring failure pattern)
```

---
```

When no clusters meet the threshold, the command prints `No clusters of size >= <N> found at threshold <X>.` and exits 0.

## Loop closure

`rnd-cards-propose` is intentionally a manual, on-demand command — no daemon, no automatic insertion. The human reads the draft scaffolds, decides which ones are worth promoting to real cards, and authors them by hand. This keeps the card library curated rather than auto-generated.

## Related

- `${CLAUDE_PLUGIN_ROOT}/lib/card-retrieve.sh` — the retrieval helper that consumes the cards once they exist.
- `${CLAUDE_PLUGIN_ROOT}/skills/rnd-cards/SKILL.md` — card authoring format and tag taxonomy.
- `/rnd-framework:rnd-cards-impact` — measure whether shipped cards actually reduced iterations-to-PASS.
