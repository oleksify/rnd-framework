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

1. **Explore the codebase.** Call `Glob`/`Grep` (and `Read` when needed) **inline** to identify: existing patterns, relevant files/modules, architectural conventions, and constraints. Do NOT spawn the built-in `Explore` or `general-purpose` subagents — they have been observed to return with `0 tool uses` during rnd phases (and fail to spawn with "Prompt is too long" in MCP-heavy sessions), wasting the spawn and producing no findings. Run the searches in this context; when a genuinely broad sweep warrants a subagent, spawn `rnd-framework:rnd-explorer` (narrow read-only grant, spawns reliably) instead.

2. **Discover local experts.** Invoke `rnd-framework:rnd-local-experts` to scan `.claude/agents/` and `.claude/skills/` for project-local agents and skills. If none exist, record `Local Experts Discovered: none` and continue.

3. **Load coding practices.** Detect which languages/frameworks are present. Invoke `rnd-framework:rnd-kiss-practices` and `rnd-framework:rnd-fp-practices` in a single message (parallel).

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

**Determine framings.** Start with the 5 core framings from `rnd-framework:rnd-premortem`. Derive up to 2 task-specific framings from the task description. Bounds: `3 ≤ N ≤ 7`, default `N = 5`. See the `rnd-framework:rnd-premortem` skill for the framing labels, framing prompts, and per-agent prompt template.

**Spawn N agents in ONE message**, one per framing. Fill in `{FRAMING_LABEL}`, `{FRAMING_PROMPT}`, and `{TASK_DESCRIPTION}` from the per-agent prompt template in the `rnd-framework:rnd-premortem` skill:

```
Agent({ subagent_type: "rnd-premortem-imaginer", prompt: "<framing 1 prompt from premortem skill>" })
Agent({ subagent_type: "rnd-premortem-imaginer", prompt: "<framing 2 prompt from premortem skill>" })
... (repeat for each framing up to N)
```

Each agent returns a short failure narrative only — no file writes, no tool use.

**Aggregate.** Collect narratives in framing-assignment order. Deduplicate near-identical failure modes (same root cause AND mechanism — keep the more specific one). Assign stable `FM<k>` IDs starting at FM1. Write `$RND_DIR/premortem.md` using the `## FM<k> — {framing-label}` format from the `rnd-framework:rnd-premortem` skill.

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
_ov_shapes="$({ grep '^- Shape:' "$RND_DIR/outside-view.md" || true; } | \
  awk '{
    for (i=1;i<=NF;i++) {
      if ($i~/^Shape:/) shape=$(i+1)
      if ($i~/^task_count=/) tc=substr($i,12)
      if ($i~/^fail_count=/) fc=substr($i,12)
      if ($i~/^fail_rate=/) fr=substr($i,11)
    }
    printf "{\"shape\":\"%s\",\"task_count\":%s,\"fail_count\":%s,\"fail_rate\":%s}\n", shape,tc,fc,fr
  }' | jq -sc '.' 2>/dev/null)"
[[ -n "$_ov_shapes" ]] || _ov_shapes='[]'
_ov_framing="$(grep -q '^## Framing constraint' "$RND_DIR/outside-view.md" && printf true || printf false)"
"${CLAUDE_PLUGIN_ROOT}/lib/outside-view-emit.sh" \
  "${_ov_mode:-unavailable}" \
  "${_ov_n_total:-0}" \
  "${_ov_shapes:-[]}" \
  "${_ov_framing:-false}"
```

---

### Phase 1 pre-step: Scope-Lock

Before the Planner decomposes anything, freeze the deliverable list. The Scoper translates the raw task into a small set of user-visible, acceptance-level deliverables with stable `D<n>` IDs. The frozen `scope.json` is then handed to the Planner as immutable input, so the plan can only map tasks onto deliverables — it cannot invent or drop scope.

**Spawn the Scoper agent.** Pass the task, the Phase 0 discovery context, and the premortem (failure modes inform what must be explicitly in/out of scope).

```
Agent({
  description: "Lock deliverable scope",
  subagent_type: "rnd-framework:rnd-scoper",
  mode: "acceptEdits",
  prompt: "Task: <task description>\nRND_DIR: <path>\nDiscovery context: <Phase 0 findings>\nPremortem: $RND_DIR/premortem.md\n${SESSION_SKILLS_FRAGMENT}"
})
```

The Scoper writes `$RND_DIR/scope.json` (machine-readable deliverable manifest with frozen `D<n>` IDs) and `$RND_DIR/scope.md` (in/out boundary narrative).

**Ratification gate (mandatory).** Render `$RND_DIR/scope.md` to the user and present exactly ONE `AskUserQuestion` with three options:
- "Approve scope" — freeze the deliverable list and proceed to planning.
- "Edit scope" — capture free-text corrections and re-scope.
- "Reject scope" — the deliverable list is wrong at the root; halt or re-scope.

This ratification gate is a **scope gate, not a happy-path gate**. It fires **even when auto-continue mode is ON**. Auto-continue skips only happy-path confirmation gates (the build/verify boundaries in Phases 2, 3, and 5); it does NOT skip the scope ratification gate. The user must explicitly approve the frozen scope before any task is planned, regardless of auto-continue.

Handle the selection:

- **On "Edit scope":** capture the user's free-text edits verbatim and re-spawn the Scoper for a revision pass, forwarding the edits as additional context. Then re-render `scope.md` and re-present the same ratification `AskUserQuestion`. Loop until the user approves or rejects.

- **On "Approve scope":** the scope is frozen. Record the lock event, passing the comma-separated deliverable IDs and their count:

  ```bash
  "${CLAUDE_PLUGIN_ROOT}/lib/scope-emit.sh" "<D1,D2,...csv>" "<n_deliverables>"
  ```

  where `<D1,D2,...csv>` is read from `scope.json` (`jq -r '[.deliverables[].id] | join(",")' "$RND_DIR/scope.json"`) and `<n_deliverables>` is the count (`jq '.deliverables | length' "$RND_DIR/scope.json"`).

- **On "Reject scope":** the deliverable list is fundamentally wrong. Halt the pipeline or re-scope from the task description per orchestrator judgment (re-spawn the Scoper with the rejection rationale, or escalate to the user for a clarified task).

Only after the user approves the frozen scope do you proceed to the Planner spawn below.

---

**Spawn a Planner agent** to decompose the task.

```
Agent({
  description: "Plan task decomposition",
  subagent_type: "rnd-framework:rnd-planner",
  mode: "acceptEdits",
  prompt: "Task: <task description>\nRND_DIR: <path>\nFrozen scope: $RND_DIR/scope.json (immutable deliverable list — map each task to deliverableIds, do NOT add or drop deliverables)\nDiscovery context: <Phase 0 findings>\nPremortem: $RND_DIR/premortem.md (address/dismiss each FM<k> in protocol.md's ## Premortem Responses)\n${OUTSIDE_VIEW_BLOCK}\n${SESSION_SKILLS_FRAGMENT}"
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

### Phase 1 post-step: Assertion paraphrase hop

Once Gate 1 has passed and the validation contract is final, decorrelate the Verifier's read of the assertions from the Planner's exact phrasing. This is a single intervention: spawn ONE paraphraser that rewords the natural-language framing of every assertion into alternate wording with identical meaning, so that when the Verifier later reads its assertions it is not anchored on the literal phrasing the Planner chose. The paraphrased framing is consumed by the Phase 3 Verifier spawn (below), never authoritative over the exact assertions.

**Spawn ONE paraphraser agent.** Slice every `### <assertion-id>` block out of `$RND_DIR/validation-contract.md` (use the same slicing convention documented in Phase 2 below — each block runs from its heading line up to but not including the next `###` heading) and concatenate ALL of them, then paste the concatenated blocks into the prompt. The agent reads no file — the orchestrator passes the assertion text in the prompt — and it writes the whole `paraphrased-assertions.md` once over all assertions.

```
Agent({
  description: "Paraphrase pre-registered assertions",
  subagent_type: "rnd-framework:rnd-assertion-paraphraser",
  mode: "acceptEdits",
  prompt: "Output path (write exactly this one file): $RND_DIR/verifications/paraphrased-assertions.md\n\nAssertion blocks to paraphrase (one ### <assertion-id> heading each — reword the prose, preserve every literal verbatim):\n<all ### <assertion-id> blocks sliced and concatenated from $RND_DIR/validation-contract.md>"
})
```

**After the paraphraser returns — consumption-gated emit (FM2 defense).** Do NOT emit the `paraphrase_injected` event yet. The event is keyed to *consumption* of the paraphrased framing by the Verifier, NOT to the file being written. Two things must both hold before the event is emitted, and both are confirmed later in Phase 3:

1. The file exists and is non-empty — verified by an absolute-path `test -s "$RND_DIR/verifications/paraphrased-assertions.md"`.
2. Its content has been placed into the Phase 3 Verifier spawn prompt.

The emit step itself lives in Phase 3, immediately after the Verifier spawn prompt is constructed (see "Consumption-gated emit" there). Emitting merely because the paraphraser wrote the file is wrong — if the file is empty, or if the content never reaches the Verifier prompt, the event must NOT fire.

## Phase 2: Build (per wave)

**Before each wave:** Scan `$RND_DIR/builds/` and `$RND_DIR/verifications/` to confirm which tasks are complete. Skip tasks that already have build manifests or verification reports.

**For each task in the wave, spawn a Builder agent.**

**Shape-validity fast-path gate (pre-spawn, per build task).** Before building each task's Builder prompt, run the gate documented in `rnd-framework:rnd-orchestration` under "Shape-Validity Fast Path" to decide whether to emit a **fast profile**. Mirror the should_promote gate structure — call the helper, branch on its exit code:

```bash
# Criticality is a HARD FLOOR — checked FIRST. HIGH NEVER fast-paths regardless of validity.
if [[ "$criticality" != "HIGH" ]] \
   && "${CLAUDE_PLUGIN_ROOT}/lib/calibration.sh" validity "<task-shape>"; then
  : # expert (exit 0) AND criticality ∈ {LOW, NORMAL} → emit the FAST PROFILE
else
  : # novice, OR criticality == HIGH → FULL PATH
fi
```

The `<task-shape>` is the task's dominant assertion shape — read the task's `assertionIds[]` from `features.json`, look up each assertion's `Shape:` in `validation-contract.md`, and take the first assertion's shape (the same shape the post-review attribution chain and the validity ledger use).

| Shape validity | Criticality | Dispatch |
|----------------|-------------|----------|
| non-expert | LOW / NORMAL / HIGH | full path |
| expert | LOW / NORMAL | **fast profile** |
| expert | HIGH | full path (HIGH is a hard floor — never fast-paths) |

**Under the fast profile, all three imperatives still hold (the no-slop floor):** (a) the Builder STILL writes a `## Files written` manifest (named by the `M<NN>-T<NN>-<uuid>` convention) — load-bearing for post-review attribution; (b) verification ALWAYS runs — the Verifier is still spawned, lighter (prose / reduced-experiment) but never absent; (c) iteration collapses to a single build-verify pass. The fast profile reduces builder ceremony (recognition + lightweight self-check) and verifier rigor; it NEVER skips the manifest or the verifier. **Models stay at the criticality tier** — no tier drop.

**Models stay at the criticality tier** — the fast path adjusts the Builder/Verifier spawn prompts (less ceremony, lighter verification), it does NOT change model selection, which still follows the criticality-driven dispatch table.

Because the gate reads `calibration.sh validity` live on every dispatch, **one-strike demotion is real via recomputation**: a new post-review finding for a shape drops its consecutive-clean streak below 5, so the very next dispatch reads `novice` and takes the full path — no separate demotion or shadow record is written.

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

**Gate 2:** Verify the build manifest exists and is non-empty (use Bash `test -s`). Manifests are named by the task's canonical unique reference `M<NN>-T<NN>-<uuid>` — `$RND_DIR/builds/M<NN>-T<NN>-<uuid>-manifest.md` (e.g. `M02-T03-f6d3915b-manifest.md`), where `<uuid>` is the task's `uuid` from `features.json`. The `uuid` makes the filename globally unique so two tasks sharing a `T<NN>` slot across milestones never overwrite each other's manifest, and it is the join key the post-review writer matches exactly for attribution. If missing, report via `AskUserQuestion`. `TaskUpdate` each passing task to `completed`.

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
  prompt: "Task: T<id>\nRND_DIR: <path>\nManifest: $RND_DIR/builds/M<NN>-T<NN>-<uuid>-manifest.md (canonical unique reference; <uuid> from features.json)\nExternal dependencies: <External Dependencies field from the pre-registration document for T<id> in $RND_DIR/protocol.md under the ## Pre-Registration Documents section>\n${SESSION_SKILLS_FRAGMENT}"
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

**Inline the paraphrased framing (additive).** When constructing the Verifier prompt, slice the same `### <assertion-id>` blocks from `$RND_DIR/verifications/paraphrased-assertions.md` (the Phase 1 post-step wrote one per assertion) for the assertions in this wave, and append them AFTER the exact assertions under a clear label. The exact assertions come first and remain authoritative; the paraphrased framing is decorrelated wording for the same claims, read IN ADDITION TO — never INSTEAD OF — the exact assertions, and never overrides them. Use the `${PARAPHRASED_BLOCK}` slot below for that labelled section.

```
Agent({
  description: "Verify wave <N> tasks",
  subagent_type: "rnd-framework:rnd-verifier",
  mode: "acceptEdits",
  prompt: "Wave: <N>\nRND_DIR: <path>\nTasks in wave: T<id1>, T<id2>, ...\nAll task pre-registrations:\n<for each task in wave, slice validation-contract.md by that task's assertionIds from features.json and paste the concatenated assertion blocks here>\n\nParaphrased framing (decorrelated wording, same meaning — read IN ADDITION TO the exact assertions above; the exact assertion text above remains authoritative and the paraphrase never overrides or replaces it):\n${PARAPHRASED_BLOCK}\n${SESSION_SKILLS_FRAGMENT}"
})
```

Where `${PARAPHRASED_BLOCK}` is the concatenation of the paraphrased `### <assertion-id>` blocks for this wave's assertions, sliced from `$RND_DIR/verifications/paraphrased-assertions.md`.

**Consumption-gated emit (FM2 defense).** This is where the `paraphrase_injected` event fires — keyed to consumption, NOT to the earlier file write. Emit ONLY after BOTH of the following hold: (1) the absolute-path existence check below succeeds, AND (2) `${PARAPHRASED_BLOCK}` was actually placed into the Verifier spawn prompt above. Do NOT emit the event merely because the paraphraser wrote the file in Phase 1.

```bash
if test -s "$RND_DIR/verifications/paraphrased-assertions.md"; then
  # Only reached when the file is non-empty AND its blocks were inlined into the
  # Verifier prompt above. n_assertions = count of ### <assertion-id> blocks inlined.
  "${CLAUDE_PLUGIN_ROOT}/lib/paraphrase-emit.sh" "<n_assertions>"
fi
```

If the file is missing or empty, skip the emit and proceed — the Verifier still has the exact assertions, which are authoritative; the paraphrase hop is a best-effort decorrelation, not a hard dependency.

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

**Re-plan routing.** When the user selects "Re-plan failing tasks" from the Gate 3 prompt (or the equivalent option in Phase 5's budget-exhaustion prompt), do NOT iterate the Builder. Route instead to the [Re-plan flow](#re-plan-flow) subsection of Phase 5, which archives the prior plan, spawns a fresh Planner without inlining prior `validation-contract.md` or `protocol.md` content, and diffs the new plan against the archive before resuming from Phase 2.

## Phase 4: Cleanup (per task)

After each task passes Gate 3, spawn a Cleanup agent to sweep dead code and stale artifacts introduced or exposed by that task's changes.

**Spawn a Cleanup agent.**

```
Agent({
  description: "Cleanup task T<id>",
  subagent_type: "rnd-framework:rnd-cleanup",
  mode: "acceptEdits",
  prompt: "Task: T<id>\nRND_DIR: <path>\nPre-registration: <assertions sliced from validation-contract.md via features.json assertionIds for T<id>>\nBuild manifest: $RND_DIR/builds/M<NN>-T<NN>-<uuid>-manifest.md (canonical unique reference; <uuid> from features.json)\nVerifier artifact: $RND_DIR/verifications/T<id>-pass-receipt.json (PASS) or $RND_DIR/verifications/T<id>-verification.md (FAIL/NEEDS_ITERATION)\n${SESSION_SKILLS_FRAGMENT}"
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
   - "Re-plan failing tasks" — route to the [Re-plan flow](#re-plan-flow) subsection below
   - "Skip failing tasks and continue (Recommended)"
   - "Stop pipeline"

Track wave iterations in `$RND_DIR/iteration-log.md` using the `## Wave-<N> Iteration Log` template (see `rnd-framework:rnd-iteration`).

### Re-plan flow

The Re-plan flow runs when the user selects **"Re-plan failing tasks"** from one of two trigger conditions:

1. **Gate 3 FAIL** — the verdict map contains FAIL assertions and the post-Gate-3 `AskUserQuestion` offered "Re-plan failing tasks (Recommended)".
2. **Phase 5 budget exhaustion** — the wave rebuild still has failures after the wave iteration budget is spent, and the budget-exhaustion `AskUserQuestion` offered "Re-plan failing tasks".

In either case, do NOT inline the prior `validation-contract.md` or `protocol.md` content into the new Planner spawn. The intervention is to *hide the previous plan* from the fresh Planner — only the failing task IDs and their failing assertion IDs are forwarded, drawn from the latest wave verdict map.

**Step-by-step:**

1. **Archive the prior plan.** Invoke `lib/replan-archive.sh` to move the four canonical artifacts (`protocol.md`, `validation-contract.md`, `features.json`, `AGENTS.md`) into `$RND_DIR/prior-plans/replan-<k>/`. Capture the archive path printed on stdout.

   ```bash
   ARCHIVE_PATH="$("${CLAUDE_PLUGIN_ROOT}/lib/replan-archive.sh" "$RND_DIR")"
   ```

   `replan-archive.sh` **moves** the four canonical plan artifacts into the archive but **copies** the frozen `scope.json` and `scope.md`, leaving the originals at the session root. The scope is frozen for the whole pipeline run; the archived copies exist only so the scope-diff step below can compare the locked scope against any proposed change.

1.5. **Scope-diff step (scope stays frozen unless a change is accepted).** A re-plan re-decomposes the *tasks*, but the deliverable scope locked in Phase 1 is NOT automatically re-opened. Re-spawn the Scoper in proposal mode against the original task plus the failing-task signal; it proposes any scope changes (added, dropped, or reworded deliverables) without overwriting the frozen `scope.json`.

   ```
   Agent({
     description: "Propose scope delta",
     subagent_type: "rnd-framework:rnd-scoper",
     mode: "acceptEdits",
     prompt: "Task: <original task description>\nRND_DIR: <path>\nFrozen scope: $ARCHIVE_PATH/scope.json (the currently-locked deliverable list — do NOT overwrite $RND_DIR/scope.json; propose changes only)\nDiscovery context: <Phase 0 findings>\n${REPLAN_HINT_BLOCK}\nThis is a re-plan. Propose a scope DELTA only: which deliverables (if any) should be added, dropped, or reworded given the failing-task signal. Write the proposal to $RND_DIR/scope-proposed.json + $RND_DIR/scope-proposed.md.\n${SESSION_SKILLS_FRAGMENT}"
   })
   ```

   Render the proposed delta and present ONE `AskUserQuestion`: "Accept scope change" / "Keep scope frozen". The default is **frozen**: unless the user explicitly accepts a change, the locked `$RND_DIR/scope.json` is untouched and the re-plan proceeds against the original deliverable list. Only if the user accepts the delta do you promote `scope-proposed.json` to `scope.json` (and `scope-proposed.md` to `scope.md`) and re-emit the lock event via `lib/scope-emit.sh` with the updated deliverable IDs and count.

2. **Touch the marker file.** This enables the `is_replan_artifact_violation` barrier in `hooks/lib.sh`, which blocks the fresh Planner from reading the four canonical session-root plan paths (`$RND_DIR/{protocol.md,validation-contract.md,features.json,AGENTS.md}`). The archived copies under `$RND_DIR/prior-plans/` remain readable for the differ.

   ```bash
   touch "$RND_DIR/.replan-in-progress"
   ```

3. **Emit the `replan_started` audit event.** `<iteration>` is the 1-based re-plan counter (count the existing directories under `$RND_DIR/prior-plans/`).

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/lib/replan-emit.sh" started <iteration> "$ARCHIVE_PATH"
   ```

4. **Build the `${REPLAN_HINT_BLOCK}`.** Read `$RND_DIR/verifications/wave-<N>-verdict-map.json` (using the archive copy if it was moved during step 1 — the path is preserved under `$ARCHIVE_PATH/` for reference). Extract:
   - The set of `task_id` values whose aggregated verdict is `NEEDS_ITERATION` (per the Gate 3 aggregation rule).
   - For each failing task, the assertion IDs whose verdict is not `PASS`.

   Render as plain text — assertion IDs only, no assertion bodies, no evidence, no feedback strings:

   ```
   Re-plan trigger: <Gate 3 FAIL | Phase 5 budget exhaustion>
   Failing tasks (from prior plan):
     - <task_id_1>: failing assertions <assertion_id_a>, <assertion_id_b>
     - <task_id_2>: failing assertions <assertion_id_c>
   ```

5. **Spawn the fresh Planner.** Use the spawn template below. The prompt MUST NOT inline any prior `validation-contract.md`, `protocol.md`, `features.json`, or `AGENTS.md` content. Only the `${REPLAN_HINT_BLOCK}` is forwarded. (FM2 defense-in-depth: the barrier hook is the mechanical enforcer; this instruction is the prompt-level enforcer.)

   ```
   Agent({
     description: "Re-plan failing tasks",
     subagent_type: "rnd-framework:rnd-planner",
     mode: "acceptEdits",
     prompt: "Task: <original task description>\nRND_DIR: <path>\nFrozen scope: $RND_DIR/scope.json (immutable deliverable list — map each task to deliverableIds, do NOT add or drop deliverables unless the scope-diff step accepted a change)\nDiscovery context: <Phase 0 findings>\nPremortem: $RND_DIR/premortem.md\n${OUTSIDE_VIEW_BLOCK}\n${REPLAN_HINT_BLOCK}\n\nIMPORTANT: This is a re-plan after a prior plan's failure. The prior plan's protocol.md, validation-contract.md, features.json, and AGENTS.md have been archived under $RND_DIR/prior-plans/. You MUST NOT read or inline any prior plan artifact content. The barrier hook will block such reads. Treat the failing task IDs and assertion IDs in ${REPLAN_HINT_BLOCK} as the only signal about what went wrong; re-decompose the task from scratch.\n${SESSION_SKILLS_FRAGMENT}"
   })
   ```

6. **Wait for the Planner.** It will write fresh `protocol.md`, `validation-contract.md`, `features.json`, and `AGENTS.md` to `$RND_DIR`.

7. **Spawn the differ.** Pass the old/new path pairs for the four artifacts. The differ produces `$RND_DIR/replan-diff.md` summarizing what changed: task additions, removals, renames, and assertion-level diffs.

   ```
   Agent({
     description: "Diff old vs new plan",
     subagent_type: "rnd-framework:rnd-replan-differ",
     mode: "acceptEdits",
     prompt: "RND_DIR: <path>\nArchive: $ARCHIVE_PATH\nNew plan: $RND_DIR (protocol.md, validation-contract.md, features.json, AGENTS.md)\nWrite the diff to $RND_DIR/replan-diff.md."
   })
   ```

8. **Emit the `replan_diff_emitted` audit event.** Parse the diff for change counts (the differ records them in the report header).

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/lib/replan-emit.sh" diff_emitted <task_changes_count> <assertion_changes_count>
   ```

9. **Remove the marker.** This re-opens the archived paths to subsequent reads (e.g., the development narrative may reference them).

   ```bash
   rm -f "$RND_DIR/.replan-in-progress"
   ```

10. **Surface the diff to the user** via the brief-relay mechanism (`SendMessage` of the `[user-brief]` form pointing at `$RND_DIR/replan-diff.md`). Then resume the pipeline from **Phase 2** with the fresh plan — Gate 1 is implicit because the Planner just ran, but you may re-run the `jq -e` shape check on `features.json` defensively.

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
- "Run RND code review first"
- "More options…"

When the user picks "More options…", follow up with a second `AskUserQuestion` (Tier 2):
- "Bump version, tag and push"
- "Show development narrative"
- "Review all artifacts"
- "Finish session"

### Development Narrative

When the user selects "Show development narrative," generate a prose story of the pipeline run. If context was compressed, re-read `$RND_DIR/protocol.md`, `$RND_DIR/validation-contract.md`, `$RND_DIR/features.json`, build manifests, verification reports, and `$RND_DIR/iteration-log.md` first. Cover: what was built and why, key decisions, obstacles and iterations, insights gained, and what's left. Write 3-5 paragraphs in first-person plural ("we"), not bullet points.

After showing the narrative, re-present the Tier 1 `AskUserQuestion` menu unchanged.

### RND Code Review

When the user selects "Run RND code review first," run the **framework's own** seven-category review — the same flow as Phase 8: invoke `rnd-framework:rnd-code-review` to load the categories, severity levels, verdict taxonomy, and report template, review the pipeline diff, and write `$RND_DIR/review/post-ship-review.md` (surface it per the Report Surfacing Protocol). Equivalently, you may run `/rnd-framework:rnd-review`.

**Do NOT invoke Claude Code's native `/code-review` (or `/review`, `/security-review`) command here.** "Run RND code review first" means the framework's review, not the native diff-scan skill. If Phase 8 already produced `$RND_DIR/review/post-ship-review.md` this session, surface that report instead of re-running.

After the review, re-present the Tier 1 `AskUserQuestion` menu unchanged.

## Phase 8: Post-SHIP Code Review

**Trigger:** Run automatically after the final wave SHIPs (Gate 5 on the last wave returns SHIP). This is a closing phase run by the pipeline, not the user.

**Opt-out flag:** `--skip-post-review` (mirrors `--skip-reality-checks`). If the user passed `--skip-post-review` in `$ARGUMENTS` or otherwise indicated opt-out:

1. Emit a skip audit event so skip frequency is measurable:

   ```bash
   RND_DIR="$RND_DIR" bash "${CLAUDE_PLUGIN_ROOT}/lib/audit-event.sh" \
     post-review-skip "pipeline" "Phase8"
   ```

2. Skip Phase 8 entirely and proceed to session close.

**When opt-out is not set**, run the review automatically:

1. **Determine the scope.** The review covers all changes shipped in the pipeline. Resolve the commit range: compare the current `HEAD` against the git state at the start of the session (read `$RND_DIR/protocol.md` or use `git log` to find the first commit on this pipeline run). Use `git diff <base>..HEAD` as the scope, or default to `HEAD` against the session's starting SHA if available.

2. **Load review criteria.** Invoke `rnd-framework:rnd-code-review` to load the seven review categories, severity levels, verdict taxonomy, and report template.

3. **Systematically review the diff** against the seven categories (architecture, security, correctness, testing, KISS compliance, style, pipeline-context hygiene). For each category, examine every changed file. Use Read/Grep to inspect surrounding context. Produce findings with severity levels (critical, major, minor, info).

4. **Write the review report** to `$RND_DIR/review/post-ship-review.md` with an `## Overall Verdict: CLEAN | ISSUES_FOUND | CRITICAL_ISSUES` line. This reuses the same report format as `rnd-review.md` — do NOT duplicate the seven-category logic, load it via `rnd-framework:rnd-code-review`.

5. **For each finding**, call the post-review record writer (`lib/post-review-writer.sh`) to append one record to the slug-root `post-review.jsonl`:

   ```bash
   # For each finding <file> <severity> <category>:
   bash "${CLAUDE_PLUGIN_ROOT}/lib/post-review-writer.sh" \
     --session-dir    "$RND_DIR" \
     --session-id     "$(basename "$RND_DIR")" \
     --touched-file   "<touched_file>" \
     --severity       "<severity>" \
     --review-found   "true" \
     --category       "<category>"
   ```

   Where:
   - `<touched_file>` — the repo-relative path to the file the finding concerns
   - `<severity>` — one of: `critical`, `major`, `minor`, `info`
   - `<category>` — the finding's review category from the seven-category review report (`post-ship-review.md`): one of `architecture`, `security`, `correctness`, `testing`, `kiss`, `style`, `pipeline-hygiene`. Each finding in the review report appears under a named category heading — use that heading's slug as the `--category` value. The writer validates the value against `x-review-category-vocab` in `lib/event-schema.json` and rejects unknown slugs.
   - `--review-found` is hardcoded `"true"` here — every finding row is a real finding
   - `--verifier-said-pass` is now OPTIONAL for attributed findings. The writer resolves the finding's owning task and DERIVES `verifier_said_PASS` from that task's aggregated verdict in `$RND_DIR/verifications/wave-*-verdict-map.json` (true iff no entry for the task is `FAIL`/`NEEDS_ITERATION`), so the shape and the verdict come from the SAME owning task. Pass `--verifier-said-pass <bool>` only as a FALLBACK for an unattributable finding (one whose touched file maps to no owning task, where no verdict-map entry exists to derive from); for an attributed finding the derived value wins and an explicit flag is ignored.

   When the verdict is CLEAN (no findings), emit one clean record **per distinct in-scope shape** so the clean run credits exactly the shapes this session exercised — never more (false expertise), never fewer (starvation). The per-shape validity ledger counts consecutive clean runs PER SHAPE, so a single shapeless sentinel cannot credit any specific shape.

   Derive the session's distinct in-scope shapes from its own `audit.jsonl` `assertion_shape` events (the shapes actually exercised this session), then call the writer's `--clean-shape` mode once per distinct shape. The writer validates the shape against `x-shape-vocab`, runs no attribution, and records `{shape, review_found:false, severity:"none", ...}`:

   ```bash
   # Enumerate distinct in-scope shapes and emit one clean row per shape.
   # `sort -u` collapses duplicate shapes; `while read` avoids a hanging
   # bash for-loop. This is orchestrator-executed markdown, not a hook.
   jq -r 'select(.event == "assertion_shape") | .shape' "$RND_DIR/audit.jsonl" \
     | sort -u \
     | while IFS= read -r shape; do
         [[ -n "$shape" ]] || continue
         bash "${CLAUDE_PLUGIN_ROOT}/lib/post-review-writer.sh" \
           --session-id  "$(basename "$RND_DIR")" \
           --clean-shape "$shape"
       done
   ```

   The clean path emits NO shapeless `unattributable` sentinel — `unattributable` stays reserved for genuine findings (`review_found:true`) whose touched file maps to no task. The Section 8 view keys dirtiness off `review_found`, not `severity`, so the clean-distinct `"none"` severity is safe and never conflates a clean run with an `info` finding.

   **Degenerate fallback:** if the session's `audit.jsonl` carries zero `assertion_shape` events (no enumerable in-scope shapes), the loop emits nothing. In that rare case a single shapeless clean row is an acceptable fallback so the stats view still records that a clean review ran:

   ```bash
   if ! jq -e 'select(.event == "assertion_shape")' "$RND_DIR/audit.jsonl" >/dev/null 2>&1; then
     bash "${CLAUDE_PLUGIN_ROOT}/lib/post-review-writer.sh" \
       --session-dir    "$RND_DIR" \
       --session-id     "$(basename "$RND_DIR")" \
       --touched-file   "clean" \
       --severity       "none" \
       --verifier-said-pass "true" \
       --review-found   "false"
   fi
   ```

6. **Surface the report.** Print the path `$RND_DIR/review/post-ship-review.md` and its complete contents verbatim — per the Report Surfacing Protocol in your active output style — before presenting next steps.

7. **Present next steps** via `AskUserQuestion`:
   - If **CLEAN**: "Review complete — no issues found." Options:
     - "Finish session (Recommended)"
     - "Review report details"
   - If **ISSUES_FOUND** or **CRITICAL_ISSUES**:
     - "Track as future work (Recommended)"
     - "Fix with /rnd-framework:rnd-start"
     - "Review report details"

**Status/resume safety:** Phase 8 writes only to `$RND_DIR/review/` and the slug-root `post-review.jsonl`. Neither `commands/rnd-status.md` nor `commands/rnd-resume.md` scan these paths for phase-detection. Both commands classify pipeline completion by "All waves SHIP" via `integration/wave-*-report.md` — a Phase 8 artifact does not affect that determination. No edit is needed to either command.
