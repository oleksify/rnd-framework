---
description: "Start the R&D orchestration framework for a complex task. Runs the full pipeline: Plan → Build → Verify → Integrate using specialized agents."
argument-hint: "[--tier=prototype|standard|high-stakes] [--multi-judge] <description of the feature, refactor, or bug fix>"
effort: high
---

# R&D Framework: Full Pipeline

You are orchestrating a complex coding task using the R&D framework — a scientific-method pipeline.

The orchestrator (this session) spawns specialized agents for each phase. Use `subagent_type` to spawn agents (e.g., `subagent_type: "rnd-framework:rnd-builder"`). Agents communicate results back via `SendMessage`. The orchestrator manages phase gates, collects artifacts, and coordinates the pipeline. See `rnd-framework:rnd-orchestration` for agent roles and coordination protocol.

### User-Facing Brief Relay

Agents (Planner, Builder, Debugger, Integrator) write user-facing narrative briefs to `$RND_DIR/briefs/` and notify you with `SendMessage` of the form:

```
[user-brief] <context>: <short title> — see <file path>
```

When you receive a `[user-brief]` message:

1. Read the referenced briefs file.
2. Surface the newest entry (everything appended since the last relay) to the user in chat, as a short update. Keep formatting light — one paragraph per entry, no ceremony.
3. **NEVER include brief content in a Verifier spawn prompt.** The `/briefs/` path is mechanically blocked from Verifier agents by the three PreToolUse gate hooks, but the orchestrator is the upstream gate — do not paste brief text into Verifier context under any circumstance. The same rule applies to `$RND_DIR/builds/T<id>-self-assessment.md`.

Briefs let the user understand what's happening in the background without waiting until phase completion. They are the primary mechanism for "developer stays informed during long agent runs" and must not compromise the information barrier.

## Setup

Determine the RND artifacts directory and create its structure:

```bash
RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" -c)
```

Use `$RND_DIR` for all artifact paths below.

## Task Input

If `$ARGUMENTS` is empty (user ran `/rnd-framework:rnd-start` with no task description):

1. **Quick codebase scan:** `git log --oneline -10`, TODO/FIXME comments, recent changes.
2. **Ask with `AskUserQuestion`:** 2-4 concrete suggestions based on what you found, plus "Describe a different task".
3. Use the selected or typed task as the task description and proceed to Phase 0.

**Never fall back to plain text** — `AskUserQuestion` is mandatory at every decision point.

If `$ARGUMENTS` is provided, skip this section and proceed directly.

## Phase 0.1: Pipeline Tier Selection

Pipeline ceremony costs tokens. A quick prototype and a security-critical migration should not run the same pipeline. Ask the user to pick the ceremony level BEFORE discovery begins.

**If `$ARGUMENTS` contains `--tier=prototype`, `--tier=standard`, or `--tier=high-stakes`**, use that value directly — skip the prompt. Strip the flag from the task description before further processing.

**Otherwise**, ask with `AskUserQuestion` (one question, three options):

- **Prototype / Experiment** — No agents. No verification. Orchestrator implements inline, shows the diff. For throwaway exploration, quick hacks, API experimentation.
- **Standard (Recommended)** — Full pipeline: Plan → Build → Verify → Integrate. Single-judge verification. Reality Audit for tasks with external deps.
- **High-stakes** — Full pipeline with amplified verification: multi-judge consensus on every HIGH-criticality task, Reality Audit on every task regardless of external-dep declaration, iteration budget 5. Use for security/auth/financial/data-integrity code.

Store the selection as `PIPELINE_TIER` for the remainder of the session.

**Route based on tier:**
- `PIPELINE_TIER=prototype` → Skip the rest of this file and follow the "Prototype Short-Circuit Flow" section below.
- `PIPELINE_TIER=standard` → Proceed to Phase 0 as written. No overrides.
- `PIPELINE_TIER=high-stakes` → Proceed to Phase 0. Apply two overrides when you reach Phase 2.5 and Phase 3:
  - Phase 2.5: Spawn the Reality Auditor for every task in the wave, even if `External dependencies` is absent.
  - Phase 3: For every HIGH-criticality task, invoke `rnd-framework:rnd-multi-judge` (equivalent to setting `--multi-judge` on the task).

## Prototype Short-Circuit Flow

**Entry condition:** `PIPELINE_TIER=prototype`. Use this flow in place of Phase 0 through Phase 6.

The orchestrator implements the task directly. No Planner, Builder, Verifier, or Integrator agents are spawned. There are no pre-registration, manifest, verification, or integration artifacts. `$RND_DIR` is still created but most of it remains empty — this is expected.

1. **Quick codebase scan.** Glob/Grep to locate the files that matter. 2-5 minutes of context-gathering. No Local Experts scan, no project-facts reload, no KISS/FP skill loading unless the task explicitly calls for discipline.

2. **State the plan in chat.** One paragraph: what files will change, what logic, what you are explicitly NOT doing. Do not write `plan.md`. Do not create a pre-registration.

3. **Implement directly.** Use Edit/Write. No TDD unless the task is about tests. No self-assessment artifact. No briefs. Keep the working tree honest — you own the diff.

4. **Summarize the diff.** 3-5 lines: files touched, behavior change, anything surprising. Then `AskUserQuestion`:
   - "Looks good — wrap up"
   - "Iterate on the prototype" — continue revising inline based on feedback
   - "Upgrade to Standard pipeline and verify" — this restarts the pipeline at Phase 0 with `PIPELINE_TIER=standard`. The prototype diff becomes the starting point; the Planner and Verifier will inspect what was built.

5. **Wrap-up.** Invoke `rnd-framework:rnd-formatting` on changed files. Skip doc-polish unless the user asks. Do not auto-commit.

**When to reject the prototype tier:** If the task description implies production impact (auth, payments, migrations, data deletion, deployment, anything user-facing at scale) and the user still picked Prototype, push back once with `AskUserQuestion`: "This looks like production work — switch to Standard?" before proceeding. Users overriding after being asked once is their call.

## Phase 0: Discovery

Before planning, explore the codebase and gather requirements.

1. **Explore the codebase.** Use Glob/Grep to identify: existing patterns, relevant files/modules, architectural conventions, and constraints.

2. **Discover local experts.** Invoke `rnd-framework:rnd-local-experts` to scan `.claude/agents/` and `.claude/skills/` for project-local agents and skills. If none exist, record `Local Experts Discovered: none` and continue.

3. **Load coding practices.** Detect which languages/frameworks are present. Invoke `rnd-framework:kiss-practices` and `rnd-framework:fp-practices` in a single message (parallel).

4. **Check roadmap scope.** Run `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" --roadmap` to get the roadmap path. Check if the file exists.

   - **If `roadmap.md` exists:** Read it and display milestone progress. Use `AskUserQuestion` with options:
     - "Start next milestone: [milestone title] (Recommended)" — use the milestone description as the task
     - "Start a different task" — continue with `$ARGUMENTS`, ignoring the roadmap
     - "Manage roadmap" — route to `/rnd-framework:rnd-roadmap`
   - **If `roadmap.md` does not exist:** If the task seems multi-day, `AskUserQuestion`: "Create a roadmap first (Recommended)" or "Proceed as single session". If single-session, skip silently.

5. **Load project facts.** Check for a persistent project facts file:

   ```bash
   FACTS_PATH=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" --facts)
   ```

   - **If `project-facts.md` exists:** Read it and compare its `Scan commit:` line against `git rev-parse HEAD`.
     - **If fresh** (commits match): Use the facts directly — they will populate plan.md's Environment Setup, Infrastructure, Worker Guidelines, and Testing Strategy sections during Phase 1. Skip the manual discovery checklist.
     - **If stale** (commits differ): Use `AskUserQuestion`: "Rescan project facts (Recommended)" — run `/rnd-framework:rnd-scan`, then continue; "Use existing facts" — proceed with stale facts; "Do manual discovery" — fall through to the checklist below.
   - **If `project-facts.md` does not exist:** Use `AskUserQuestion`: "Scan project now (Recommended)" — run `/rnd-framework:rnd-scan`, then continue; "Do manual discovery" — run the environment checklist below.

   **Manual discovery fallback** (only when project-facts.md is missing and user declines scan):
   - **Package manager:** Glob for package.json, Cargo.toml, mix.exs, go.mod, pyproject.toml
   - **Test framework:** Grep for test runner configs (vitest, jest, pytest, etc.), count existing tests, identify exact run commands
   - **CI config:** Read .github/workflows/ or equivalent — extract build/test/deploy commands
   - **External services:** Grep for https:// URLs in source to catalog APIs, databases, third-party services (note auth requirements)
   - **Environment variables:** Read .env.example or .env.template, Grep for process.env/ENV references
   - **Secrets and off-limits:** Infer from .gitignore, CI secrets config, and sensitive file paths

   Present findings to the user via `AskUserQuestion` for confirmation and gap-filling. This feeds into the Environment Setup, Infrastructure, and Testing Strategy sections of plan.md.

6. **Identify ambiguities.** Note what is unclear: scope boundaries, architectural choices, integration points, edge cases, or user preferences.

7. **Ask 3-5 clarifying questions** using `AskUserQuestion`. Focus on scope, patterns, constraints, and preferences. Provide 2-4 options per question based on what you found in the codebase.

8. **Compile discovery context.** Summarize: (a) codebase findings, (b) local experts, (c) KISS/FP rules, (d) environment/infrastructure findings, (e) user answers, (f) constraints.

**Skip condition:** If the task description is already highly specific (file paths, approach details, clear scope), skip Phase 0 and proceed to Phase 0.5.

## Phase 0.5: Design Exploration

Before committing to a plan, explore architectural alternatives. Invoke `rnd-framework:rnd-design` for the full protocol.

**Skip condition:** Skip if the task is highly specific or a small refactor with no meaningful architectural ambiguity.

If **auto-continue mode is ON**, automatically select the recommended approach and proceed to Phase 1 without pausing.

Otherwise:

1. **Generate 2-3 architectural alternatives** from Phase 0 context.
2. **Recommend one approach** with reasons tied to Phase 0 constraints.
3. **Save design spec** to `$RND_DIR/design-spec.md`. Status: `STATUS: DRAFT`.
4. **Present for approval** — `AskUserQuestion`: "Approve design (Recommended)", "Approve with modifications", "Choose or request a different alternative", "Skip design phase".
5. **Iterate on feedback** (max 3 rounds). After 3 rounds without approval, report blocked.
6. **Finalize** — set `STATUS: APPROVED`.

## Phase 1: Plan

**Spawn a Planner agent** to decompose the task.

Before spawning, retrieve relevant flash cards for the planner role. Task type is unknown at this point (no pre-reg exists yet), so default to `infra` and rely on role-only filtering:

```bash
# Cards: Phase 1 Planner
CARD_PATHS=$(bash "${CLAUDE_PLUGIN_ROOT}/lib/card-retrieve.sh" \
  --role=planner \
  --task-type="${TASK_TYPE:-infra}" \
  --tags="${CARD_TAGS:-}")

if [[ -n "$CARD_PATHS" ]]; then
  CARD_BODIES=$(printf '%s\n' "$CARD_PATHS" | xargs cat)
  CARDS_HEADER_PREPEND=$'# Reference examples for tasks like this one\n\n'"$CARD_BODIES"$'\n\n'
  CARD_IDS=$(printf '%s\n' "$CARD_PATHS" | xargs -n1 basename | tr '\n' ',')
  CARD_IDS="${CARD_IDS%,}"
else
  CARDS_HEADER_PREPEND=""
  CARD_IDS="none"
fi
```

```
Agent({
  description: "Plan task decomposition",
  subagent_type: "rnd-framework:rnd-planner",
  mode: "acceptEdits",
  prompt: "${CARDS_HEADER_PREPEND}Task: <task description>\nRND_DIR: <path>\nDiscovery context: <Phase 0 findings>"
})
```

After the spawn returns, emit a card-injection audit event:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/lib/audit-event.sh card_injection "T0" "planner:${CARD_IDS}"
```

The Planner writes `$RND_DIR/plan.md` with pre-registrations, dependency matrix, and execution schedule.

**Gate 1:** Read the returned `plan.md`. Every criterion must be empirically verifiable — a skeptical Verifier must produce a true/false result from evidence alone. "Works correctly", "handles errors", "is performant" are automatic rejections. If any criterion is vague, send the Planner back with specific feedback.

**After Gate 1 passes:** Summarize the plan to the user. Use `AskUserQuestion` with options:
- "Approve plan and auto-continue (Recommended)" — run the full pipeline automatically, pausing only for escalations
- "Approve plan and start building" — proceed with manual gates at each phase boundary
- "Request plan revisions"
- "Add more tasks"

If the user selects "Approve plan and auto-continue", set **auto-continue mode = ON**. This skips happy-path gates in Phases 2, 3, and 5. Escalation gates are always preserved.

Once approved, create a `TaskCreate` entry for each task.

## Phase 2: Build (per wave)

**Before each wave:** Scan `$RND_DIR/builds/` and `$RND_DIR/verifications/` to confirm which tasks are complete. Skip tasks that already have build manifests or verification reports.

**For each task in the wave, spawn a Builder agent.**

Before spawning, retrieve relevant flash cards for the builder role. Use the task's declared task type and card tags from its pre-registration (default to `infra` when the task type cannot be inferred):

```bash
# Cards: Phase 2 Builder
CARD_PATHS=$(bash "${CLAUDE_PLUGIN_ROOT}/lib/card-retrieve.sh" \
  --role=builder \
  --task-type="${TASK_TYPE:-infra}" \
  --tags="${CARD_TAGS:-}")

if [[ -n "$CARD_PATHS" ]]; then
  CARD_BODIES=$(printf '%s\n' "$CARD_PATHS" | xargs cat)
  CARDS_HEADER_PREPEND=$'# Reference examples for tasks like this one\n\n'"$CARD_BODIES"$'\n\n'
  CARD_IDS=$(printf '%s\n' "$CARD_PATHS" | xargs -n1 basename | tr '\n' ',')
  CARD_IDS="${CARD_IDS%,}"
else
  CARDS_HEADER_PREPEND=""
  CARD_IDS="none"
fi
```

```
Agent({
  description: "Build task T<id>",
  subagent_type: "rnd-framework:rnd-builder",
  mode: "acceptEdits",
  prompt: "${CARDS_HEADER_PREPEND}Task: T<id>\nRND_DIR: <path>\nPre-registration: <paste from plan.md>\nLearnings: <language-specific learnings if any>"
})
```

After the spawn returns, emit a card-injection audit event:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/lib/audit-event.sh card_injection "T<id>" "builder:${CARD_IDS}"
```

Do NOT build tasks yourself. The Builder agent handles implementation, TDD, manifest creation, and self-assessment. It returns a status code: DONE, DONE_WITH_CONCERNS, NEEDS_CONTEXT, or BLOCKED.

**Route each result:**

| Status code | Action |
|-------------|--------|
| `DONE` | Proceed to Gate 2. |
| `DONE_WITH_CONCERNS` | Proceed to Gate 2. Note concerns for verification. |
| `NEEDS_CONTEXT` | `AskUserQuestion` to get missing info. Re-spawn Builder with the answer. |
| `BLOCKED` | `AskUserQuestion`: "Re-plan this task (Recommended)", "Provide a workaround", "Skip this task". |

**Gate 2:** Verify `$RND_DIR/builds/T<id>-manifest.md` exists and is non-empty (use Bash `test -s`). If missing, report via `AskUserQuestion`. `TaskUpdate` each passing task to `completed`.

**After Gate 2:** If **auto-continue mode is ON**, proceed directly to Phase 2.5. Otherwise, `AskUserQuestion`:
- "Proceed to verification (Recommended)"
- "Review build artifacts first"

## Phase 2.5: Reality Audit (blocking)

For each task in the wave, **spawn a Reality Auditor agent.**

Before spawning, retrieve relevant flash cards for the reality-auditor role using the task's declared task type and card tags (default to `infra`):

```bash
# Cards: Phase 2.5 Reality-auditor
CARD_PATHS=$(bash "${CLAUDE_PLUGIN_ROOT}/lib/card-retrieve.sh" \
  --role=reality-auditor \
  --task-type="${TASK_TYPE:-infra}" \
  --tags="${CARD_TAGS:-}")

if [[ -n "$CARD_PATHS" ]]; then
  CARD_BODIES=$(printf '%s\n' "$CARD_PATHS" | xargs cat)
  CARDS_HEADER_PREPEND=$'# Reference examples for tasks like this one\n\n'"$CARD_BODIES"$'\n\n'
  CARD_IDS=$(printf '%s\n' "$CARD_PATHS" | xargs -n1 basename | tr '\n' ',')
  CARD_IDS="${CARD_IDS%,}"
else
  CARDS_HEADER_PREPEND=""
  CARD_IDS="none"
fi
```

```
Agent({
  description: "Audit external contracts",
  subagent_type: "rnd-framework:rnd-reality-auditor",
  mode: "acceptEdits",
  prompt: "${CARDS_HEADER_PREPEND}Task: T<id>\nRND_DIR: <path>\nManifest: $RND_DIR/builds/T<id>-manifest.md\nExternal dependencies: <from pre-registration>"
})
```

After the spawn returns, emit a card-injection audit event:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/lib/audit-event.sh card_injection "T<id>" "reality-auditor:${CARD_IDS}"
```

Statuses: `VALIDATED_ALL`, `VALIDATED_PARTIAL`, `INVALID_FOUND`, `SKIPPED`. If `INVALID_FOUND`, route back to Phase 2 with the reality report as feedback before verification.

## Phase 3: Verify (per wave — batch verification)

**CRITICAL: Information Barrier.** The Verifier runs in a separate context window and cannot see the Builder's reasoning. The `read-gate.sh` hook blocks reads of self-assessment files. Do NOT pass self-assessment content to the Verifier.

**Batch verification:** Spawn ONE Verifier agent per wave with ALL task pre-registrations in the prompt. The Verifier processes each task in the wave sequentially, then returns a per-task verdict map JSON saved to `$RND_DIR/verifications/wave-<N>-verdict-map.json`.

**Verdict map schema:**
```json
{
  "T1": {
    "verdict": "PASS",
    "evidence": ["grep for X exited 0", "test foo passed"],
    "feedback": ""
  },
  "T2": {
    "verdict": "NEEDS_ITERATION",
    "evidence": ["criterion Y not met: output missing field Z"],
    "feedback": "The response schema omits the 'feedback' field required by the criterion."
  }
}
```
Valid verdict values: `PASS`, `PASS_QUALITY_NEEDS_ITERATION`, `NEEDS_ITERATION`, `FAIL`. The `feedback` field is required and non-empty for any non-PASS verdict; empty string for PASS.

**Determine the criticality of tasks in the wave to route correctly:**

- **Wave contains only LOW or NORMAL tasks:** Spawn a single Verifier agent for the whole wave.

  Before spawning, retrieve relevant flash cards for the verifier role. This is a wave-level spawn — use one shared retrieval call for the whole wave with `task-type=infra` so wave card priming is uniform across all tasks in the wave:

  ```bash
  # Cards: Phase 3 Verifier (wave)
  CARD_PATHS=$(bash "${CLAUDE_PLUGIN_ROOT}/lib/card-retrieve.sh" \
    --role=verifier \
    --task-type="${TASK_TYPE:-infra}" \
    --tags="${CARD_TAGS:-}")

  if [[ -n "$CARD_PATHS" ]]; then
    CARD_BODIES=$(printf '%s\n' "$CARD_PATHS" | xargs cat)
    CARDS_HEADER_PREPEND=$'# Reference examples for tasks like this one\n\n'"$CARD_BODIES"$'\n\n'
    CARD_IDS=$(printf '%s\n' "$CARD_PATHS" | xargs -n1 basename | tr '\n' ',')
    CARD_IDS="${CARD_IDS%,}"
  else
    CARDS_HEADER_PREPEND=""
    CARD_IDS="none"
  fi
  ```

```
Agent({
  description: "Verify wave <N> tasks",
  subagent_type: "rnd-framework:rnd-verifier",
  mode: "acceptEdits",
  prompt: "${CARDS_HEADER_PREPEND}Wave: <N>\nRND_DIR: <path>\nTasks in wave: T<id1>, T<id2>, ...\nAll task pre-registrations:\n<paste each task pre-reg from plan.md>"
})
```

  After the spawn returns, emit a card-injection audit event (wave-scoped task id):

  ```bash
  bash ${CLAUDE_PLUGIN_ROOT}/lib/audit-event.sh card_injection "wave-<N>" "verifier:${CARD_IDS}"
  ```

- **Wave contains any HIGH-criticality task:** Invoke the `rnd-framework:rnd-multi-judge` protocol for the whole wave. The skill runs a first-pass escalation gate: a single Sonnet/medium verifier runs first; if it returns PASS the full dual-judge protocol is skipped and PASS is the final verdict; if it returns FAIL, NEEDS_ITERATION, PASS_QUALITY_NEEDS_ITERATION, or AMEND_REQUIRED it is promoted to Judge A and a second judge (Judge B) is spawned. Set `RND_MULTI_JUDGE_ALWAYS=1` to bypass the gate and restore exact pre-gate behavior (both judges always spawn in parallel). Both judges each receive all wave task pre-registrations and each returns a per-task verdict map. Tiebreaker is triggered per-task — only for tasks where Judge A and Judge B disagree. See that skill for the full wave-batched protocol.

  After the first-pass verdict is known, write the `escalationGate` object to the calibration record for each task: `{ "firstPassVerdict": "<verdict>", "escalated": <true|false>, "overturned": <true|false> }`. Write silently as a graceful no-op if `calibration.jsonl` does not yet exist.

The Verifier writes per-task traceability artifacts for every task in the wave: a `T<id>-pass-receipt.json` for PASS tasks, or a full `T<id>-verification.md` prose report for FAIL/NEEDS_ITERATION tasks (auto-materialized). PASS_QUALITY_NEEDS_ITERATION tasks get both. Plus the aggregate verdict map.

The Verifier saves the aggregate verdict map to: `$RND_DIR/verifications/wave-<N>-verdict-map.json`

Do NOT verify tasks yourself. The Verifier agent independently writes experiment tests, runs them, inspects the code, and produces per-task verification reports. It returns a per-task verdict map.

**Gate 3:** Verify `$RND_DIR/verifications/wave-<N>-verdict-map.json` exists and is non-empty. Read the verdict map and dispatch each task based on its verdict:

| Verdict | Action |
|---------|--------|
| `PASS` | `TaskUpdate` to `completed`. Route to Phase 4 (cleanup). |
| `PASS_QUALITY_NEEDS_ITERATION` | Same as PASS. Save quality feedback. Does NOT block integration. Route to Phase 4. |
| `NEEDS_ITERATION` | Keep `in_progress`. Track with `metadata: {"iteration": N}`. Enter Phase 5 for this task. |
| `FAIL` | Do NOT iterate — route to re-planning. |
| `AMEND_REQUIRED` | Route to Phase 3.5: Amendment Flow. Does NOT block other tasks in the wave. The Verifier must cite a concrete spec defect in the `feedback` field; without a cited defect, treat as `NEEDS_ITERATION`. |

**After Gate 3:** Summarize per-task verdicts from the verdict map. Then route:

- All PASS/PASS_QUALITY: auto-continue to Phase 4, or `AskUserQuestion`: "Proceed to cleanup (Recommended)", "Review verification reports".
- Any NEEDS_ITERATION: auto-continue to Phase 5, or `AskUserQuestion`: "Iterate on failing tasks (Recommended)", "Skip failing tasks and continue".
- Any FAIL (always pauses): `AskUserQuestion`: "Re-plan failing tasks (Recommended)", "Iterate anyway", "Skip failing tasks and continue".

## Phase 3.5: Amendment Flow (AMEND_REQUIRED only)

**Entry condition:** One or more tasks in the wave received an `AMEND_REQUIRED` verdict. This phase is conditional — it does NOT affect tasks with PASS, NEEDS_ITERATION, or FAIL verdicts.

**Wave-continuation semantics:** AMEND_REQUIRED on one task does NOT block other tasks in the wave. Tasks that PASS or PASS_QUALITY_NEEDS_ITERATION proceed through Phase 4 (cleanup) and Phase 6 (integration) normally. The AMEND_REQUIRED task pauses independently for the arbiter + user gate, then re-joins the pipeline at the next available re-verification slot after amendment resolution.

For each task with an `AMEND_REQUIRED` verdict, execute the following steps independently:

### Step 1: Spawn the Amendment Arbiter

Spawn the arbiter agent with **strictly scoped inputs** — the original task pre-registration text plus the Verifier's AMEND_REQUIRED feedback (including the cited spec defect). No build manifest, no self-assessment, no code, no briefs, no cleanup reports are passed to the arbiter.

```
Agent({
  description: "Amendment arbiter for T<id>",
  subagent_type: "rnd-framework:rnd-amendment-arbiter",
  mode: "acceptEdits",
  prompt: "Task pre-registration:\n<paste verbatim from plan.md>\n\nVerifier AMEND_REQUIRED feedback:\n<paste verbatim from verdict map 'feedback' field>"
})
```

### Step 2: Read Arbiter Output and Branch

The arbiter emits one of three structured responses:

- **`AMEND { field, old, new, rationale }`** — Proceed to Step 3 (user gate). The arbiter may include multiple AMEND entries for multiple fields.
- **`REBUILD { rationale }`** — Treat as `NEEDS_ITERATION`; skip Steps 3-5 and route directly to Phase 5 with the original Verifier feedback.
- **`ESCALATE_REPLAN { rationale }`** — Spawn a Planner micro-spawn for this task only. The Planner receives the original pre-reg and the arbiter's rationale. After micro-replan, re-enter the pipeline at Phase 2 for the re-planned task.

### Step 3: User Gate (mandatory)

Present the arbiter's amendment proposal to the user. Use `AskUserQuestion` with exactly these structured options:

- **"Approve amendment (Recommended)"** — Mutate `plan.md` pre-registration via Edit (update only the fields specified in the AMEND output). Then proceed to Step 4.
- **"Reject — treat as NEEDS_ITERATION"** — Discard the arbiter proposal. Route to Phase 5 with the original Verifier feedback. The resulting NEEDS_ITERATION rebuild consumes one iteration from the task's budget; the rejection itself is not a separate debit.
- **"Override to FAIL and re-plan"** — Route to re-planning for this task.

After the user decides, append a record to `$RND_DIR/briefs/T<id>-amendments.md` (create if absent) with these required fields:

```markdown
## Amendment — <ISO timestamp>

**Cited defect:** <verbatim from Verifier feedback>
**Arbiter recommendation:** <AMEND | REBUILD | ESCALATE_REPLAN>
**Arbiter full output:** <verbatim arbiter response>
**User decision:** approved | rejected | overridden-to-fail
```

Then write a calibration record to `calibration.jsonl` with `verdict: "AMEND_REQUIRED"` and `amendmentData: { userDecision: "approved" | "rejected" | "overridden-to-fail", arbitersRecommendation: "AMEND" | "REBUILD" | "ESCALATE_REPLAN" }`.

### Step 4: Re-Prove Check (if applicable)

If the mutated task pre-registration contains `Proof: lean`, re-trigger the Proof Gate for this task before re-verification. The Lean proof is now stale — it proved properties of the old criteria. Re-prove is mandatory. If Lean is unavailable and the Proof Gate would normally skip, the existing skip behavior applies; proceed to Step 5.

### Step 5: Re-Verification (clean-slate)

Spawn the Verifier with the now-mutated pre-registration as if it were the original. The Verifier prompt MUST NOT mention amendments or amendment history — clean-slate re-verification only. The Verifier sees only the current (mutated) pre-reg text.

Before spawning, retrieve relevant flash cards for the verifier role using the amended task's task type and card tags (default to `infra`):

```bash
# Cards: Phase 3.5 Step 5 Verifier (re-verify after amendment)
CARD_PATHS=$(bash "${CLAUDE_PLUGIN_ROOT}/lib/card-retrieve.sh" \
  --role=verifier \
  --task-type="${TASK_TYPE:-infra}" \
  --tags="${CARD_TAGS:-}")

if [[ -n "$CARD_PATHS" ]]; then
  CARD_BODIES=$(printf '%s\n' "$CARD_PATHS" | xargs cat)
  CARDS_HEADER_PREPEND=$'# Reference examples for tasks like this one\n\n'"$CARD_BODIES"$'\n\n'
  CARD_IDS=$(printf '%s\n' "$CARD_PATHS" | xargs -n1 basename | tr '\n' ',')
  CARD_IDS="${CARD_IDS%,}"
else
  CARDS_HEADER_PREPEND=""
  CARD_IDS="none"
fi
```

```
Agent({
  description: "Re-verify T<id> after amendment",
  subagent_type: "rnd-framework:rnd-verifier",
  mode: "acceptEdits",
  prompt: "${CARDS_HEADER_PREPEND}Wave: <N>\nRND_DIR: <path>\nTasks in wave: T<id>\nAll task pre-registrations:\n<paste mutated pre-reg from plan.md>"
})
```

After the spawn returns, emit a card-injection audit event:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/lib/audit-event.sh card_injection "T<id>" "verifier:${CARD_IDS}"
```

Route the re-verification verdict via Gate 3 as normal. The re-verification spawn intentionally uses a single-task wave (the amended task only) — clean-slate isolation from sibling tasks in the original wave.

## Phase 4: Cleanup (per task)

After each task passes Gate 3, spawn a Cleanup agent to sweep dead code and stale artifacts introduced or exposed by that task's changes.

**Spawn a Cleanup agent.**

Before spawning, retrieve relevant flash cards for the cleanup role using the task's declared task type and card tags (default to `infra`):

```bash
# Cards: Phase 4 Cleanup
CARD_PATHS=$(bash "${CLAUDE_PLUGIN_ROOT}/lib/card-retrieve.sh" \
  --role=cleanup \
  --task-type="${TASK_TYPE:-infra}" \
  --tags="${CARD_TAGS:-}")

if [[ -n "$CARD_PATHS" ]]; then
  CARD_BODIES=$(printf '%s\n' "$CARD_PATHS" | xargs cat)
  CARDS_HEADER_PREPEND=$'# Reference examples for tasks like this one\n\n'"$CARD_BODIES"$'\n\n'
  CARD_IDS=$(printf '%s\n' "$CARD_PATHS" | xargs -n1 basename | tr '\n' ',')
  CARD_IDS="${CARD_IDS%,}"
else
  CARDS_HEADER_PREPEND=""
  CARD_IDS="none"
fi
```

```
Agent({
  description: "Cleanup task T<id>",
  subagent_type: "rnd-framework:rnd-cleanup",
  mode: "acceptEdits",
  prompt: "${CARDS_HEADER_PREPEND}Task: T<id>\nRND_DIR: <path>\nPre-registration: <paste from plan.md>\nBuild manifest: $RND_DIR/builds/T<id>-manifest.md\nVerifier artifact: $RND_DIR/verifications/T<id>-pass-receipt.json (PASS) or $RND_DIR/verifications/T<id>-verification.md (FAIL/NEEDS_ITERATION)"
})
```

After the spawn returns, emit a card-injection audit event:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/lib/audit-event.sh card_injection "T<id>" "cleanup:${CARD_IDS}"
```

The Cleanup agent inspects the working tree for dead code, unused imports, unreachable exports, and leftover scaffolding. It applies fixes in-place and produces `$RND_DIR/cleanup/T<id>-cleanup-report.md`. If applied fixes break re-verification, the agent rolls back its changes and notes `cleanup: rolled_back` in the report.

**Gate 4:** Verify `$RND_DIR/cleanup/T<id>-cleanup-report.md` exists and is non-empty.

- If the report contains `cleanup: rolled_back`, note `cleanup: skipped (rollback)` in `$RND_DIR/iteration-log.md` and proceed — this is NOT a pipeline failure.
- If the file is missing, `AskUserQuestion`: "Re-run cleanup", "Skip cleanup for this task".

**After Gate 4:** If **auto-continue mode is ON**, proceed directly to Phase 6 (Integrate) once all tasks in the wave have completed cleanup. Otherwise, `AskUserQuestion`:
- "Proceed to integration (Recommended)"
- "Review cleanup reports"

## Phase 4.5: Polish (wave-level)

After all tasks in the wave have completed cleanup (Phase 4), spawn ONE Polisher agent to detect and fix cross-task seam issues across the full wave.

**Spawn a Polisher agent:**

```
Agent({
  description: "Polish wave <N>",
  subagent_type: "rnd-framework:rnd-polisher",
  mode: "acceptEdits",
  prompt: "Wave: <N>\nRND_DIR: <path>\nTasks in wave: T<id1>, T<id2>, ..."
})
```

The Polisher inspects the combined wave diff for cross-task duplication, naming and API drift across task boundaries, helpers that should be lifted to a shared location, and structural inconsistencies. It applies fixes in-place and produces `$RND_DIR/polish/wave-<N>-polish-report.md`. If applied fixes break re-verification, the agent rolls back its changes and notes `polish: skipped (broke verification)` in the report.

**Gate 4.5:** Verify `$RND_DIR/polish/wave-<N>-polish-report.md` exists and is non-empty.

- If the report contains `polish: skipped (broke verification)` or `polish: skipped (no findings)`, proceed — this is NOT a pipeline failure.
- If the file is missing, `AskUserQuestion`: "Re-run polish", "Skip polish for this wave".

**After Gate 4.5:** If **auto-continue mode is ON**, proceed directly to Phase 5 (Wave-Level Iteration) or Phase 6 (Integrate) as appropriate. Otherwise, `AskUserQuestion`:
- "Proceed to integration (Recommended)"
- "Review polish report"

## Phase 5: Wave-Level Iteration (if needed)

Iteration operates at the wave level — a single Builder spawn handles ALL failing tasks in the wave, and re-verification re-batches the full wave.

1. **Collect the full wave failure report**: extract per-task feedback from `$RND_DIR/verifications/wave-<N>-verdict-map.json` for every task with verdict `FAIL` or `NEEDS_ITERATION`. This is the "affected slice" — do not iterate tasks that passed.
2. **Spawn ONE Builder agent** with the full wave failure report (the complete per-task verdict map with evidence refs for all failing tasks — not just feedback for a single task). Do NOT fix the code yourself. The Builder must address every failing task in a single pass.
3. After the Builder returns, **loop back to Phase 3** to re-batch-verify the full wave (same Verifier spawn, same information barrier, all tasks).
4. **If wave re-verification returns all PASS**, extract learnings via `rnd-framework:rnd-learning`.
5. **Wave iteration budget**: budget = per-task budget of the highest-criticality task in the wave (LOW=2, NORMAL=3, HIGH=5). If the wave rebuild still has failures after budget exhausted, `AskUserQuestion`:
   - "Re-plan failing tasks"
   - "Skip failing tasks and continue (Recommended)"
   - "Stop pipeline"

Track wave iterations in `$RND_DIR/iteration-log.md` using the `## Wave-<N> Iteration Log` template (see `rnd-framework:rnd-iteration`).

### Skip Procedure

1. `TaskUpdate`: `status: "completed"`, `metadata: {"skipped": true, "reason": "..."}`.
2. Check downstream dependents via `TaskList`. Warn the user and `AskUserQuestion` for each: skip dependent, proceed anyway, or re-plan.

## Phase 6: Integrate

**Spawn an Integrator agent:**

```
Agent({
  description: "Integrate verified wave",
  subagent_type: "rnd-framework:rnd-integrator",
  mode: "acceptEdits",
  prompt: "Wave: <N>\nRND_DIR: <path>\nVerified tasks: <list of T<id>s>"
})
```

Do NOT integrate yourself. The Integrator merges verified outputs, runs integration tests, and produces `$RND_DIR/integration/wave-<N>-report.md`.

**Gate 5:** Verify `$RND_DIR/integration/wave-<N>-report.md` exists and is non-empty.

**After Gate 5:** Summarize results.

If SHIP and more waves remain: auto-continue to Phase 2 next wave, or `AskUserQuestion`:
- "Proceed to next wave (Recommended)"
- "Review integration report"

If SHIP and last wave: `AskUserQuestion`:
- "Review all artifacts"
- "Proceed to cleanup (Recommended)"

If NO-SHIP: `AskUserQuestion`:
- "Fix failing integration points (Recommended)"
- "Re-plan affected tasks"

## Phase 7: Report & Cleanup

Summarize: what was built, verification results, iterations, integration status, remaining concerns.

**MANDATORY — DO NOT SKIP:** Invoke `rnd-framework:rnd-formatting` BEFORE doc-polish to run the project's formatter on pipeline-changed files.

**MANDATORY — DO NOT SKIP:** Invoke `rnd-framework:rnd-doc-polish` AFTER formatting but BEFORE presenting next steps.

Use `AskUserQuestion` for next steps (Tier 1 — 4 options):
- "Commit changes (Recommended)"
- "Create PR"
- "Run code review first"
- "More options…"

When the user picks "More options…", follow up with a second `AskUserQuestion` (Tier 2):
- "Bump version, tag and push"
- "Show development narrative"
- "Review all artifacts"
- "Finish session"

### Development Narrative

When the user selects "Show development narrative," generate a prose story of the pipeline run. If context was compressed, re-read `$RND_DIR/plan.md`, build manifests, verification reports, and `$RND_DIR/iteration-log.md` first. Cover: what was built and why, key decisions, obstacles and iterations, insights gained, and what's left. Write 3-5 paragraphs in first-person plural ("we"), not bullet points.

After showing the narrative, re-present the Tier 1 `AskUserQuestion` menu unchanged.
