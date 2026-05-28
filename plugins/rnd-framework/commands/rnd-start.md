---
description: "Start the R&D orchestration framework for a complex task. Runs the full pipeline: Plan → Build → Verify → Integrate using specialized agents."
argument-hint: "<description of the feature, refactor, or bug fix>"
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

### Session-Local Skill Injection

Before each agent spawn, assemble a `SESSION_SKILLS_FRAGMENT` from session-local artifacts found in `$RND_DIR/AGENTS.md` and `$RND_DIR/skills/*/SKILL.md`. This fragment is appended to every spawn prompt so agents receive project-specific guidance authored by the Planner.

```bash
# Build the session-local context fragment.
# $RND_DIR/AGENTS.md  — session agent guidance written by the Planner.
# $RND_DIR/skills/*/SKILL.md — zero or more session-local skill files.

SESSION_SKILLS_FRAGMENT=""

if [[ -f "$RND_DIR/AGENTS.md" ]]; then
  SESSION_SKILLS_FRAGMENT+="## Session Context"$'\n'
  SESSION_SKILLS_FRAGMENT+="$(cat "$RND_DIR/AGENTS.md")"$'\n\n'
fi

skill_bodies=""
for skill_file in "$RND_DIR"/skills/*/SKILL.md; do
  [[ -f "$skill_file" ]] || continue
  # Strip YAML frontmatter (lines between leading --- delimiters).
  skill_bodies+="$(awk '/^---/{if(fm<2)fm++;next} fm==2' "$skill_file")"$'\n\n'
done

if [[ -n "$skill_bodies" ]]; then
  SESSION_SKILLS_FRAGMENT+="## Session Skills"$'\n'
  SESSION_SKILLS_FRAGMENT+="$skill_bodies"
fi
```

When `SESSION_SKILLS_FRAGMENT` is non-empty, append it to the `prompt:` of every Agent() spawn below **and** emit a `skill_injected` audit event:

```bash
# Call once per spawn when SESSION_SKILLS_FRAGMENT is non-empty.
# The 3-arg form records {event, task_id, tool, timestamp} — no assertion_id is set
# (audit-event.sh's optional 4th arg is reserved for assertion_id semantics; do not
# overload it with a skill_name here).
RND_DIR="$RND_DIR" bash "${CLAUDE_PLUGIN_ROOT}/lib/audit-event.sh" \
  skill_injected "<task_id>" "<agent_type>"
```

## Task Input

If `$ARGUMENTS` is empty (user ran `/rnd-framework:rnd-start` with no task description):

1. **Quick codebase scan:** `git log --oneline -10`, TODO/FIXME comments, recent changes.
2. **Ask with `AskUserQuestion`:** 2-4 concrete suggestions based on what you found, plus "Describe a different task".
3. Use the selected or typed task as the task description and proceed to Phase 0.

**Never fall back to plain text** — `AskUserQuestion` is mandatory at every decision point.

If `$ARGUMENTS` is provided, skip this section and proceed directly.

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
     - **If fresh** (commits match): Use the facts directly — they will populate `protocol.md`'s Environment Setup, Infrastructure, Worker Guidelines, and Testing Strategy sections during Phase 1. Skip the manual discovery checklist.
     - **If stale** (commits differ): Use `AskUserQuestion`: "Rescan project facts (Recommended)" — run `/rnd-framework:rnd-scan`, then continue; "Use existing facts" — proceed with stale facts; "Do manual discovery" — fall through to the checklist below.
   - **If `project-facts.md` does not exist:** Use `AskUserQuestion`: "Scan project now (Recommended)" — run `/rnd-framework:rnd-scan`, then continue; "Do manual discovery" — run the environment checklist below.

   **Manual discovery fallback** (only when project-facts.md is missing and user declines scan):
   - **Package manager:** Glob for package.json, Cargo.toml, mix.exs, go.mod, pyproject.toml
   - **Test framework:** Grep for test runner configs (vitest, jest, pytest, etc.), count existing tests, identify exact run commands
   - **CI config:** Read .github/workflows/ or equivalent — extract build/test/deploy commands
   - **External services:** Grep for https:// URLs in source to catalog APIs, databases, third-party services (note auth requirements)
   - **Environment variables:** Read .env.example or .env.template, Grep for process.env/ENV references
   - **Secrets and off-limits:** Infer from .gitignore, CI secrets config, and sensitive file paths

   Present findings to the user via `AskUserQuestion` for confirmation and gap-filling. This feeds into the Environment Setup, Infrastructure, and Testing Strategy sections of `protocol.md`.

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

### Phase 1 pre-step: Premortem fan-out

Before spawning the Planner, run a premortem: spawn N parallel `rnd-premortem-imaginer` agents, each imagining one failure framing. Aggregate their narratives into `$RND_DIR/premortem.md`.

**Determine framings.** Start with the 5 core framings from `rnd-framework:premortem`. Derive up to 2 task-specific framings from the task description. Bounds: `3 ≤ N ≤ 7`, default `N = 5`. See the `rnd-framework:premortem` skill for the framing labels, framing prompts, and per-agent prompt template.

**Spawn N agents in ONE message**, one per framing. Fill in `{FRAMING_LABEL}`, `{FRAMING_PROMPT}`, and `{TASK_DESCRIPTION}` from the per-agent prompt template in the `rnd-framework:premortem` skill:

```
Agent({ subagent_type: "rnd-premortem-imaginer", prompt: "<framing 1 prompt from premortem skill>" })
Agent({ subagent_type: "rnd-premortem-imaginer", prompt: "<framing 2 prompt from premortem skill>" })
... (repeat for each framing up to N)
```

Each agent returns a short failure narrative only — no file writes, no tool use.

**Aggregate.** Collect narratives in framing-assignment order. Deduplicate near-identical failure modes (same root cause AND mechanism — keep the more specific one). Assign stable `FM<k>` IDs starting at FM1. Write `$RND_DIR/premortem.md` using the `## FM<k> — {framing-label}` format from the `rnd-framework:premortem` skill.

**Emit** the audit event after writing `premortem.md`:

```bash
"${CLAUDE_PLUGIN_ROOT}/lib/premortem-emit.sh" "<framings_csv>" "<failure_mode_count>"
```

Where `framings_csv` is the comma-joined list of framing labels used and `failure_mode_count` is the count of `FM<k>` entries written.

---

### Phase 1 pre-step: Outside-view injection

Before spawning the Planner, query the historical session corpus for per-shape FAIL rates and inject the result into the Planner's context as a calibration anchor.

Run the injector to populate `$RND_DIR/outside-view.md` and capture the rendered block:

```bash
OUTSIDE_VIEW_BLOCK="$("${CLAUDE_PLUGIN_ROOT}/lib/outside-view.sh")"
```

After the block is rendered, emit the audit event:

```bash
_ov_mode="$(grep -m1 '^- Mode:' "$RND_DIR/outside-view.md" | sed 's/^- Mode: //')"
_ov_n_total="$(grep -m1 '^- n_total:' "$RND_DIR/outside-view.md" | sed 's/^- n_total: //')"
_ov_shapes="$(grep '^- Shape:' "$RND_DIR/outside-view.md" | \
  awk '{
    for (i=1;i<=NF;i++) {
      if ($i~/^Shape:/) shape=$(i+1)
      if ($i~/^task_count=/) tc=substr($i,12)
      if ($i~/^fail_count=/) fc=substr($i,12)
      if ($i~/^fail_rate=/) fr=substr($i,11)
    }
    printf "{\"shape\":\"%s\",\"task_count\":%s,\"fail_count\":%s,\"fail_rate\":%s}\n", shape,tc,fc,fr
  }' | jq -sc '.' 2>/dev/null || printf '[]')"
_ov_framing="$(grep -q '^## Framing constraint' "$RND_DIR/outside-view.md" && printf true || printf false)"
"${CLAUDE_PLUGIN_ROOT}/lib/outside-view-emit.sh" \
  "${_ov_mode:-unavailable}" \
  "${_ov_n_total:-0}" \
  "${_ov_shapes:-[]}" \
  "${_ov_framing:-false}"
```

---

**Spawn a Planner agent** to decompose the task.

```
Agent({
  description: "Plan task decomposition",
  subagent_type: "rnd-framework:rnd-planner",
  mode: "acceptEdits",
  prompt: "Task: <task description>\nRND_DIR: <path>\nDiscovery context: <Phase 0 findings>\nPremortem: $RND_DIR/premortem.md (address/dismiss each FM<k> in protocol.md's ## Premortem Responses)\n${OUTSIDE_VIEW_BLOCK}\n${SESSION_SKILLS_FRAGMENT}"
})
```

The Planner writes four artifact files to `$RND_DIR`: `protocol.md` (strategic scope, heuristic ceiling, environment setup), `validation-contract.md` (assertions keyed by `M<N>.<area>.<slug>` headings), `features.json` (machine-readable task manifest with `assertionIds` per task), and `AGENTS.md` (session-local agent guidance).

**Planner-output sanity check:** Before reading Planner output, check whether `$RND_DIR/protocol.md` exists. If it does not exist after the Planner returns, the Planner malfunctioned or wrote a legacy single-file artifact instead — abort, notify the user via `AskUserQuestion`, and point them to `/rnd-framework:rnd-history` for read-only access. A correctly-running v5 Planner always produces `protocol.md`; its absence is an unrecoverable mismatch. (Pre-v5 resume detection lives in `commands/rnd-resume.md` Step 0.5.)

**Gate 1:** Read `$RND_DIR/protocol.md`, `$RND_DIR/validation-contract.md`, `$RND_DIR/features.json`, and `$RND_DIR/AGENTS.md`. Every criterion in `validation-contract.md` must be empirically verifiable — a skeptical Verifier must produce a true/false result from evidence alone. "Works correctly", "handles errors", "is performant" are automatic rejections. If any criterion is vague, send the Planner back with specific feedback. Also confirm `features.json` is valid JSON (run `jq -e . "$RND_DIR/features.json"`) and that every `assertionIds` entry exists as a `### <id>` heading in `validation-contract.md`.

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

**Slicing convention:** To assemble the pre-registration prose for task `T<id>`, read `$RND_DIR/features.json` with `jq` to get that task's `assertionIds` array. Then open `$RND_DIR/validation-contract.md` and extract the `### <assertion-id>` heading block for each ID (the block runs from the heading line up to but not including the next `###` heading or end of file). Concatenate the extracted blocks in order. This concatenated text is the `<pre-registration>` to paste into the spawn prompt.

```
Agent({
  description: "Build task T<id>",
  subagent_type: "rnd-framework:rnd-builder",
  mode: "acceptEdits",
  prompt: "Task: T<id>\nRND_DIR: <path>\nPre-registration: <assertions sliced from validation-contract.md via features.json assertionIds>\nLearnings: <language-specific learnings if any>\n${SESSION_SKILLS_FRAGMENT}"
})
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

```
Agent({
  description: "Audit external contracts",
  subagent_type: "rnd-framework:rnd-reality-auditor",
  mode: "acceptEdits",
  prompt: "Task: T<id>\nRND_DIR: <path>\nManifest: $RND_DIR/builds/T<id>-manifest.md\nExternal dependencies: <External Dependencies field from the pre-registration document for T<id> in $RND_DIR/protocol.md under the ## Pre-Registration Documents section>\n${SESSION_SKILLS_FRAGMENT}"
})
```

Statuses: `VALIDATED_ALL`, `VALIDATED_PARTIAL`, `INVALID_FOUND`, `SKIPPED`. If `INVALID_FOUND`, route back to Phase 2 with the reality report as feedback before verification.

## Phase 3: Verify (per wave — batch verification)

**CRITICAL: Information Barrier.** The Verifier runs in a separate context window and cannot see the Builder's reasoning. The `read-gate.sh` hook blocks reads of self-assessment files. Do NOT pass self-assessment content to the Verifier.

**Batch verification:** Spawn ONE Verifier agent per wave with ALL task pre-registrations in the prompt. The Verifier processes each task in the wave sequentially, then returns a per-assertion verdict map JSON saved to `$RND_DIR/verifications/wave-<N>-verdict-map.json`.

**Verdict map schema:** the map is keyed by assertion ID (format: `M<N>.<area>.<slug>`). Each entry carries the assertion verdict, evidence, feedback, and the task that owns the assertion.

```json
{
  "M1.verifier.verdict-map-shape": {
    "verdict": "PASS",
    "evidence": ["grep for assertion_id returned 4 lines", "jq parse succeeded"],
    "feedback": "",
    "task_id": "M1.T01.verifier-per-assertion"
  },
  "M1.verifier.prose-report-per-assertion": {
    "verdict": "NEEDS_ITERATION",
    "evidence": ["rnd-verification/SKILL.md does not enumerate per-assertion content"],
    "feedback": "Assertion M1.verifier.prose-report-per-assertion: rnd-verification/SKILL.md does not enumerate per-assertion content in the Full Prose Report section.",
    "task_id": "M1.T01.verifier-per-assertion"
  }
}
```

Valid verdict values per assertion entry: `PASS`, `PASS_QUALITY_NEEDS_ITERATION`, `NEEDS_ITERATION`, `FAIL`. The `feedback` field is required and non-empty for any non-PASS verdict; empty string for PASS.

**Spawn a single Verifier agent per wave.** HIGH criticality is handled via the per-agent dispatch policy (model boost to opus/xhigh) — there is no parallel-judge mode.

```
Agent({
  description: "Verify wave <N> tasks",
  subagent_type: "rnd-framework:rnd-verifier",
  mode: "acceptEdits",
  prompt: "Wave: <N>\nRND_DIR: <path>\nTasks in wave: T<id1>, T<id2>, ...\nAll task pre-registrations:\n<for each task in wave, slice validation-contract.md by that task's assertionIds from features.json and paste the concatenated assertion blocks here>\n${SESSION_SKILLS_FRAGMENT}"
})
```

The Verifier writes a `T<id>-pass-receipt.json` for PASS tasks, a full `T<id>-verification.md` prose report for FAIL/NEEDS_ITERATION tasks (auto-materialized), and saves the aggregate verdict map to `$RND_DIR/verifications/wave-<N>-verdict-map.json`. PASS_QUALITY_NEEDS_ITERATION tasks get both.

Do NOT verify tasks yourself. The Verifier agent independently writes experiment tests, runs them, inspects the code, and produces per-task verification reports.

**Gate 3:** Verify `$RND_DIR/verifications/wave-<N>-verdict-map.json` exists and is non-empty. Then aggregate per-assertion entries into per-task verdicts using a two-step process.

**Step 1: Read the per-assertion verdict map.**

```bash
jq '.' "$RND_DIR/verifications/wave-<N>-verdict-map.json"
```

Each entry is keyed by assertion ID and carries `verdict`, `evidence`, `feedback`, and `task_id`.

**Step 2: Aggregate per task using `jq`.**

```bash
jq '
  group_by(.task_id)
  | map({
      task_id: .[0].task_id,
      verdict: (
        if any(.[]; .verdict == "FAIL") then "NEEDS_ITERATION"
        elif any(.[]; .verdict == "NEEDS_ITERATION") then "NEEDS_ITERATION"
        elif any(.[]; .verdict == "PASS_QUALITY_NEEDS_ITERATION") then "PASS_QUALITY_NEEDS_ITERATION"
        else "PASS"
        end
      ),
      failing_assertion_ids: [.[] | select(.verdict != "PASS") | .key]
    })
' <(jq 'to_entries | map(.value + {key: .key})' "$RND_DIR/verifications/wave-<N>-verdict-map.json")
```

**Aggregation rule:** for each unique `task_id`, if any assertion is `FAIL` or `NEEDS_ITERATION` → task verdict is `NEEDS_ITERATION`; if any assertion is `PASS_QUALITY_NEEDS_ITERATION` and none are `FAIL`/`NEEDS_ITERATION` → task verdict is `PASS_QUALITY_NEEDS_ITERATION`; if all assertions are `PASS` → task verdict is `PASS`.

Dispatch each task based on its aggregated verdict:

| Aggregated Task Verdict | Action |
|-------------------------|--------|
| `PASS` | `TaskUpdate` to `completed`. Route to Phase 4 (cleanup). |
| `PASS_QUALITY_NEEDS_ITERATION` | Same as PASS. Save quality feedback. Does NOT block integration. Route to Phase 4. |
| `NEEDS_ITERATION` | Keep `in_progress`. Track with `metadata: {"iteration": N}`. Enter Phase 5 for this task. |

**After Gate 3:** Summarize per-task aggregated verdicts. Then route:

- All PASS/PASS_QUALITY: auto-continue to Phase 4, or `AskUserQuestion`: "Proceed to cleanup (Recommended)", "Review verification reports".
- Any NEEDS_ITERATION: auto-continue to Phase 5, or `AskUserQuestion`: "Iterate on failing tasks (Recommended)", "Skip failing tasks and continue".
- Any FAIL assertions (always pauses — task routes to NEEDS_ITERATION above, but if re-planning is warranted): `AskUserQuestion`: "Re-plan failing tasks (Recommended)", "Iterate anyway", "Skip failing tasks and continue".

When routing a task to Phase 5 (iteration), the feedback packet sent to the Builder **must cite the failing assertion IDs verbatim** from the verdict map — list each assertion ID whose verdict is not PASS along with its `feedback` string. Do not paraphrase or summarize assertion IDs.

## Phase 4: Cleanup (per task)

After each task passes Gate 3, spawn a Cleanup agent to sweep dead code and stale artifacts introduced or exposed by that task's changes.

**Spawn a Cleanup agent.**

```
Agent({
  description: "Cleanup task T<id>",
  subagent_type: "rnd-framework:rnd-cleanup",
  mode: "acceptEdits",
  prompt: "Task: T<id>\nRND_DIR: <path>\nPre-registration: <assertions sliced from validation-contract.md via features.json assertionIds for T<id>>\nBuild manifest: $RND_DIR/builds/T<id>-manifest.md\nVerifier artifact: $RND_DIR/verifications/T<id>-pass-receipt.json (PASS) or $RND_DIR/verifications/T<id>-verification.md (FAIL/NEEDS_ITERATION)\n${SESSION_SKILLS_FRAGMENT}"
})
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
  prompt: "Wave: <N>\nRND_DIR: <path>\nTasks in wave: T<id1>, T<id2>, ...\n${SESSION_SKILLS_FRAGMENT}"
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

1. **Collect the full wave failure report**: read `$RND_DIR/verifications/wave-<N>-verdict-map.json` and group assertions by `task_id`. For each task that aggregated to `NEEDS_ITERATION` at Gate 3, collect every assertion entry where `verdict != "PASS"` — these form the failing slice. Include each assertion's ID and `feedback` string verbatim. Do not iterate tasks that passed.
2. **Spawn ONE Builder agent** with the full wave failure report (the failing assertion IDs and their feedback strings for all failing tasks — not just a summary). Do NOT fix the code yourself. The Builder must address every failing task in a single pass.
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
  prompt: "Wave: <N>\nRND_DIR: <path>\nVerified tasks: <list of T<id>s>\n${SESSION_SKILLS_FRAGMENT}"
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

When the user selects "Show development narrative," generate a prose story of the pipeline run. If context was compressed, re-read `$RND_DIR/protocol.md`, `$RND_DIR/validation-contract.md`, `$RND_DIR/features.json`, build manifests, verification reports, and `$RND_DIR/iteration-log.md` first. Cover: what was built and why, key decisions, obstacles and iterations, insights gained, and what's left. Write 3-5 paragraphs in first-person plural ("we"), not bullet points.

After showing the narrative, re-present the Tier 1 `AskUserQuestion` menu unchanged.
