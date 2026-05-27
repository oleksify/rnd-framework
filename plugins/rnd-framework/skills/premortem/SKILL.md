---
name: premortem
description: "Use when the orchestrator must run a premortem before writing protocol.md — spawns N Haiku agents in parallel, each imagining one failure framing, then aggregates results into premortem.md"
effort: low
user-invocable: false
---

# Premortem

A structured failure-imagination exercise run by the orchestrator before planning begins. N agents each receive one framing and imagine the milestone already shipped and failed for that reason. Results are aggregated into `premortem.md` before `protocol.md` is written.

## Core Framings

Five fixed framings. The orchestrator may add up to 2 task-generated framings derived from the specific task description. Bounds: `3 ≤ N ≤ 7`, default `N = 5`.

| ID | Label | Framing prompt |
|----|-------|---------------|
| F1 | wrong-external-service-assumption | Imagine the milestone shipped and failed because an external service behaved differently than assumed — wrong response shape, undocumented rate limit, auth scheme change, or API version mismatch. |
| F2 | data-model-misfit | Imagine the milestone shipped and failed because the data model did not fit real usage — missing fields, wrong cardinality, serialization mismatch, or schema drift between components. |
| F3 | performance-at-scale | Imagine the milestone shipped and failed due to performance at scale — N+1 queries, unbounded result sets, blocking I/O in a hot path, or memory growth that only manifests under real load. |
| F4 | auth-permission-edge-case | Imagine the milestone shipped and failed at an auth or permission boundary — a role that should be denied but isn't, a token scope mismatch, a missing ownership check, or a privilege-escalation path. |
| F5 | user-meant-something-different | Imagine the milestone shipped and failed because the requirement was misread — the user's mental model differed from the implementation's, a term was ambiguous, or an implicit expectation was never stated. |

## Per-Agent Prompt Template

The orchestrator pastes this template verbatim into each `general-purpose` (`model: "haiku"`) spawn. Replace `{FRAMING_LABEL}`, `{FRAMING_PROMPT}`, and `{TASK_DESCRIPTION}` before dispatching.

```
You are performing a premortem for a software task.

Framing: {FRAMING_LABEL}
{FRAMING_PROMPT}

Task description:
{TASK_DESCRIPTION}

Imagine the task shipped and was declared complete — then failed for exactly the reason described in the framing above.

Return a SHORT structured failure narrative with three parts:
1. The imagined failure — what broke, what the user or system observed.
2. The mechanism — the specific code path, assumption, or design choice that caused it.
3. An early-warning signal — one observable symptom that would have appeared before the full failure.

Rules:
- Write no files. Use no tools. Narrative only in your final message.
- Do not write hedged "this might happen" prose — write as if the failure is real and you are explaining it after the fact.
- Keep the whole response under 200 words.
```

## premortem.md Format

`premortem.md` is **orchestrator-owned and immutable input** — it is written by the orchestrator before `protocol.md` and is never modified by Builder or Verifier agents. Each failure mode gets a stable `FM<k>` ID (FM1, FM2, ...) that other artifacts may reference.

```markdown
# Premortem

## FM1 — wrong-external-service-assumption
**Failure:** The payment gateway returned a `402` with a non-standard body shape; the parser threw on missing `error.code` and surfaced a 500 to the user.
**Mechanism:** Integration assumed the documented response schema; staging used a mock that matched it; production did not.
**Early-warning signal:** Integration tests pass but the gateway's sandbox returns 4xx on edge amounts.

## FM2 — data-model-misfit
**Failure:** ...
**Mechanism:** ...
**Early-warning signal:** ...
```

One `## FM<k> — {framing-label}` section per returned narrative. The `FM<k>` counter increments in the order the orchestrator assigns framings (F1 → FM1, F2 → FM2, ...).

## Aggregation Rule

After all N agents respond:

1. Collect each narrative in framing-assignment order.
2. Deduplicate near-identical failure modes — if two narratives share the same root cause and mechanism, keep the more specific one and note the merge in a comment at the top of `premortem.md`.
3. Assign stable `FM<k>` IDs starting at FM1 in final order.
4. Write `premortem.md` using the format above.

Near-identical: same root cause AND same mechanism. Different symptoms alone do not qualify for deduplication.

## Emit Invocation

After writing `premortem.md`, run:

```bash
"${CLAUDE_PLUGIN_ROOT}/lib/premortem-emit.sh" "<framings_csv>" "<failure_mode_count>"
```

- `framings_csv` — comma-joined framing labels used (e.g. `"wrong-external-service-assumption,data-model-misfit,performance-at-scale,auth-permission-edge-case,user-meant-something-different"`).
- `failure_mode_count` — integer count of `FM<k>` entries written to `premortem.md`.

## Information-Barrier Note

`premortem.md` records only failure-mode **descriptions** (imagined failure, mechanism, early-warning signal). It must never contain Builder reasoning, Verifier verdict rationale, or iteration history. The orchestrator enforces this by writing `premortem.md` before any build or verification agent runs.
